/* Host tests for the bounded DNS wire parser and retry loop. */
#include <stdio.h>
#include <string.h>

#define DNS_TEST 1
#define DNS_ATTEMPTS 3
#define DNS_SPINS_PER_ATTEMPT 3UL
#include "dns.c"

static unsigned char reply[DNS_BUF_SZ];
static unsigned int reply_len;
static unsigned char reply_ready;
static unsigned char reply_wrong_id;
static unsigned int send_count;
static unsigned int respond_on_send;
static unsigned int open_port;
static int failures;

static void make_a_reply(const unsigned char *query, unsigned int len)
{
    unsigned int i, p = 0;
    reply[p++] = query[0]; reply[p++] = query[1];
    if (reply_wrong_id) reply[1]++;
    reply[p++] = 0x81; reply[p++] = 0x80;
    reply[p++] = 0; reply[p++] = 1;       /* one question */
    reply[p++] = 0; reply[p++] = 1;       /* one answer */
    reply[p++] = 0; reply[p++] = 0;
    reply[p++] = 0; reply[p++] = 0;
    for (i = 12; i < len; i++) reply[p++] = query[i];
    reply[p++] = 0xC0; reply[p++] = 0x0C; /* answer name -> question */
    reply[p++] = 0; reply[p++] = 1;       /* A */
    reply[p++] = 0; reply[p++] = 1;       /* IN */
    reply[p++] = 0; reply[p++] = 0; reply[p++] = 0; reply[p++] = 60;
    reply[p++] = 0; reply[p++] = 4;
    reply[p++] = 192; reply[p++] = 0; reply[p++] = 2; reply[p++] = 42;
    reply_len = p;
    reply_ready = 1;
}

int udp_open(unsigned int src_port)
{
    open_port = src_port;
    return 0;
}

int udp_sendto(const unsigned char *dst_ip, unsigned int dst_port,
               const unsigned char *buf, unsigned int len)
{
    (void)dst_ip;
    if (dst_port != DNS_PORT) return -1;
    send_count++;
    if (send_count == respond_on_send) make_a_reply(buf, len);
    return 0;
}

unsigned int udp_rx_available(void)
{
    return reply_ready ? reply_len : 0;
}

unsigned int udp_recv(unsigned char *buf, unsigned int maxlen)
{
    unsigned int i, n = reply_len < maxlen ? reply_len : maxlen;
    if (!reply_ready) return 0;
    for (i = 0; i < n; i++) buf[i] = reply[i];
    reply_ready = 0;
    return n;
}

void udp_close(void) {}

static void reset_transport(unsigned int response_attempt)
{
    reply_len = reply_ready = reply_wrong_id = 0;
    send_count = 0;
    respond_on_send = response_attempt;
    open_port = 0;
}

static void check(int ok, const char *name)
{
    if (ok) printf("ok   %s\n", name);
    else { printf("FAIL %s\n", name); failures++; }
}

int main(void)
{
    static const unsigned char dns_server[4] = { 192, 0, 2, 53 };
    unsigned char ip[4];
    unsigned char long_label[66];
    unsigned int i, n;

    n = dns_build_query("www.example.com", 0xBEEF);
    check(n > 20 && dns_qbuf[0] == 0xBE && dns_qbuf[1] == 0xEF,
          "query carries varying transaction ID");
    check(dns_qbuf[12] == 3 && dns_qbuf[16] == 7,
          "query encodes hostname labels");
    check(dns_build_query("bad..name", 1) == 0,
          "query rejects empty labels");
    for (i = 0; i < 64; i++) long_label[i] = 'a';
    long_label[64] = 0;
    check(dns_build_query((const char *)long_label, 1) == 0,
          "query rejects labels longer than 63 bytes");

    reset_transport(2);
    check(dns_resolve(dns_server, "example.com", ip) == 0 && send_count == 2,
          "resolver retries a dropped first query");
    check(ip[0] == 192 && ip[1] == 0 && ip[2] == 2 && ip[3] == 42,
          "resolver returns matching A record");
    check(open_port >= DNS_SRC_PORT && open_port != DNS_SRC_PORT,
          "resolver varies its UDP source port");

    reset_transport(0);
    check(dns_resolve(dns_server, "example.com", ip) == -3 &&
          send_count == DNS_ATTEMPTS,
          "resolver stops after bounded retries");

    reset_transport(1);
    reply_wrong_id = 1;
    check(dns_resolve(dns_server, "example.com", ip) == -3,
          "resolver ignores mismatched transaction IDs");

    if (failures) {
        printf("\n%d DNS test(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall DNS tests passed\n");
    return 0;
}
