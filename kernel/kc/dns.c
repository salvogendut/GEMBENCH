#include "dns.h"
#include "udp.h"

/* #238: in GEOBENCH this runs as a paged module (GBNET.MOD) and the firmware 50 Hz
 * frame counter at 0xB5CB may be frozen while we run. Timeouts therefore use bounded
 * spin counts. Several shorter attempts are more tolerant of a dropped UDP query than
 * the old single long wait, without making the total blocking time unbounded. */

#define DNS_PORT    53
#define DNS_SRC_PORT 1053
#ifndef DNS_ATTEMPTS
#define DNS_ATTEMPTS 3
#endif
#ifndef DNS_SPINS_PER_ATTEMPT
#define DNS_SPINS_PER_ATTEMPT 120000UL
#endif
#define DNS_BUF_SZ  512
#define DNS_PARSE_IGNORE -5

#ifdef DNS_TEST
#define DNS_FRAME_SEED 0x5A3CU
#else
#define DNS_FRAME_SEED (*(volatile unsigned int *)0xB5CB)
#endif

static unsigned char dns_qbuf[DNS_BUF_SZ];
static unsigned char dns_rbuf[DNS_BUF_SZ];

/* Encode hostname into DNS wire-format QNAME at dst.
 * "www.example.com" -> \x03www\x07example\x03com\x00
 * Returns pointer to byte after the trailing 0x00. */
static unsigned char *dns_encode_name(unsigned char *dst, unsigned char *end,
                                      const char *hostname) {
    const char *p = hostname;
    unsigned char *len_byte;

    if (!*p) return 0;
    while (*p) {
        if (dst >= end) return 0;
        len_byte = dst++;
        *len_byte = 0;
        while (*p && *p != '.') {
            if (*len_byte >= 63 || dst >= end) return 0;
            *dst++ = (unsigned char)*p++;
            (*len_byte)++;
        }
        if (!*len_byte) return 0;
        if (*p == '.') {
            p++;
            if (!*p) break;             /* accept a fully-qualified trailing dot */
        }
    }
    if (dst >= end) return 0;
    *dst++ = 0x00;  /* root label */
    return dst;
}

/* Build a DNS query into dns_qbuf for hostname.
 * Returns total query length, or 0 if the hostname is invalid/too long. */
static unsigned int dns_build_query(const char *hostname, unsigned int query_id) {
    unsigned char *p = dns_qbuf;
    unsigned char *end = dns_qbuf + DNS_BUF_SZ;

    *p++ = (unsigned char)(query_id >> 8);
    *p++ = (unsigned char)query_id;
    /* Flags: standard query, recursion desired */
    *p++ = 0x01; *p++ = 0x00;
    /* QDCOUNT=1 */
    *p++ = 0x00; *p++ = 0x01;
    /* ANCOUNT=0, NSCOUNT=0, ARCOUNT=0 */
    *p++ = 0x00; *p++ = 0x00;
    *p++ = 0x00; *p++ = 0x00;
    *p++ = 0x00; *p++ = 0x00;

    p = dns_encode_name(p, end - 4, hostname);
    if (!p) return 0;

    /* QTYPE=A (1), QCLASS=IN (1) */
    *p++ = 0x00; *p++ = 0x01;
    *p++ = 0x00; *p++ = 0x01;

    return (unsigned int)(p - dns_qbuf);
}

/*
 * Advance past a DNS name (label chain or compression pointer).
 * Returns pointer to byte after the name.
 */
static const unsigned char *skip_name(const unsigned char *p,
                                      const unsigned char *end) {
    unsigned char label;
    while (p < end) {
        if (*p == 0x00) {
            return p + 1;
        }
        if ((*p & 0xC0) == 0xC0) {
            if (p + 1 >= end) return 0;
            /* Compression pointer: 2 bytes total, then name is done */
            return p + 2;
        }
        if (*p & 0xC0) return 0;
        label = *p;
        if (!label || label > 63 || (unsigned int)(end - p) < (unsigned int)label + 1)
            return 0;
        p += (unsigned int)label + 1;
    }
    return 0;
}

/*
 * Parse DNS response in dns_rbuf (len bytes).
 * Extracts first TYPE A answer and writes 4 bytes into result_ip.
 * Returns 0 on success, -4 on failure.
 */
static int dns_parse_response(unsigned int len, unsigned int query_id,
                              unsigned char *result_ip) {
    const unsigned char *p   = dns_rbuf;
    const unsigned char *end = dns_rbuf + len;
    unsigned int qdcount, ancount, i;
    unsigned int rtype, rdlen;

    if (len < 12)
        return -4;

    /* A delayed response from an earlier attempt is not an error in this attempt. */
    if (p[0] != (unsigned char)(query_id >> 8) || p[1] != (unsigned char)query_id)
        return DNS_PARSE_IGNORE;

    /* Check QR=1 (response) and RCODE=0 (no error) */
    if (!(p[2] & 0x80))
        return -4;
    if ((p[3] & 0x0F) != 0)
        return -4;

    qdcount = ((unsigned int)p[4] << 8) | p[5];
    ancount = ((unsigned int)p[6] << 8) | p[7];

    if (ancount == 0)
        return -4;

    p += 12;

    /* Skip question section */
    for (i = 0; i < qdcount; i++) {
        p = skip_name(p, end);
        if (!p || (unsigned int)(end - p) < 4) return -4;
        p += 4;  /* QTYPE + QCLASS */
    }

    /* Walk answer records */
    for (i = 0; i < ancount; i++) {
        if (p >= end)
            return -4;

        p = skip_name(p, end);
        if (!p || (unsigned int)(end - p) < 10) return -4;

        rtype = ((unsigned int)p[0] << 8) | p[1];
        /* skip TYPE(2) CLASS(2) TTL(4) */
        rdlen = ((unsigned int)p[8] << 8) | p[9];
        p += 10;

        if (rtype == 1 && rdlen == 4) {
            /* TYPE A, 4-byte IPv4 */
            if (p + 4 > end)
                return -4;
            result_ip[0] = p[0];
            result_ip[1] = p[1];
            result_ip[2] = p[2];
            result_ip[3] = p[3];
            return 0;
        }

        if ((unsigned int)(end - p) < rdlen) return -4;
        p += rdlen;
    }

    return -4;
}

static unsigned int dns_make_query_id(const char *hostname) {
    unsigned int id = (unsigned int)(DNS_FRAME_SEED ^ 0xA5C3U);
    while (*hostname) {
        id ^= (unsigned int)(unsigned char)*hostname++ << 8;
        id = (unsigned int)((id << 1) | (id >> 15));
        id += 0x1F3DU;
    }
    return id ? id : 0x6D5AU;
}

int dns_resolve(const unsigned char *dns_server_ip, const char *hostname,
                unsigned char *result_ip) {
    unsigned int qlen, rlen, query_id, attempt;
    unsigned long spins;
    int parse_result = -3;

    query_id = dns_make_query_id(hostname);
    qlen = dns_build_query(hostname, query_id);
    if (!qlen) return -4;

    if (udp_open((unsigned int)(DNS_SRC_PORT + (query_id & 0x1FFFU))) != 0)
        return -1;

    for (attempt = 0; attempt < DNS_ATTEMPTS; attempt++) {
        if (attempt) query_id = (unsigned int)(query_id + 0x1F3DU);
        qlen = dns_build_query(hostname, query_id);
        if (udp_sendto(dns_server_ip, DNS_PORT, dns_qbuf, qlen) != 0) {
            parse_result = -2;
            continue;
        }
        parse_result = -3;
        for (spins = DNS_SPINS_PER_ATTEMPT; spins; spins--) {
            if (udp_rx_available() >= 8) {
                rlen = udp_recv(dns_rbuf, DNS_BUF_SZ);
                if (!rlen) continue;
                parse_result = dns_parse_response(rlen, query_id, result_ip);
                if (parse_result == DNS_PARSE_IGNORE) continue;
                if (parse_result == 0) {
                    udp_close();
                    return 0;
                }
                break;
            }
        }
    }

    udp_close();
    return parse_result;
}
