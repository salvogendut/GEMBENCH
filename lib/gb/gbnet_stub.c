/* gbnet_stub.c - app-side stubs for the paged networking module (#238/#259).
 *
 * Apps that want networking link this (build_capp NET=1). Each gb_net_* call marshals an
 * op + args into the fixed low-RAM GBNET block and calls gb_net() (the GB_NET kernel
 * call), which pages in the backend module selected by the kernel. Mirrors gbui_stub.c.
 * Buffers cross via the #2200 low-RAM data region (shared with the file-write modules,
 * mutually exclusive). The app-visible driver is one TCP socket. */
#include "gb.h"

#define GBNET_OP   (*(volatile unsigned char *)0x1490)   /* op selector */
#define GBNET_RES  (*(volatile unsigned char *)0x1491)   /* status byte */
#define GBNET_RES2 (*(volatile unsigned int  *)0x1492)   /* word result (recv len / rx avail) */
#define GBNET_IP   ((unsigned char *)0x1494)             /* connect dest IP (4 bytes) */
#define GBNET_PORT (*(volatile unsigned int  *)0x1498)   /* connect dest port */
#define GBNET_LEN  (*(volatile unsigned int  *)0x149A)   /* send/recv length */
#define GBNET_BUF  ((unsigned char *)0x2200)             /* data + net_config_t (init) */
#define GBNET_MAXIO 1024U                                /* per-call chunk cap */
#define GBNET_DNS_MAX_HOST 239U                          /* M4 command packet ceiling */
#define GBNET_DNS_CACHE_MAX 63U                          /* current app URL/host limit */

extern unsigned char gb_net(void);   /* GB_NET trampoline -> GBNET_RES in A */

/* Per-app state: no resident kernel allocation. Keeping one recently resolved host
 * avoids repeating a blocking DNS transaction when an app reconnects. */
static unsigned char recv_status = GB_NET_RX_IDLE;
static unsigned char dns_cache_valid;
static unsigned char dns_cache_ip[4];
static char dns_cache_host[GBNET_DNS_CACHE_MAX + 1];

/* gb_net_init: cfg22 = ip[4] mask[4] gw[4] dns[4] mac[6]. Returns 1 = chip ok. */
unsigned char gb_net_init(const unsigned char *cfg22)
{
    unsigned char i;
    for (i = 0; i < 22; i++) GBNET_BUF[i] = cfg22[i];
    GBNET_OP = 1;
    i = gb_net();
    recv_status = i ? GB_NET_RX_IDLE : GB_NET_RX_ERROR;
    return i;
}

unsigned char gb_net_open(void)
{
    unsigned char ok;
    GBNET_OP = 2;
    ok = gb_net();
    recv_status = ok ? GB_NET_RX_IDLE : GB_NET_RX_ERROR;
    return ok;
}

unsigned char gb_net_connect(const unsigned char *ip, unsigned int port)
{
    unsigned char ok;
    GBNET_IP[0] = ip[0]; GBNET_IP[1] = ip[1]; GBNET_IP[2] = ip[2]; GBNET_IP[3] = ip[3];
    GBNET_PORT = port;
    GBNET_OP = 3;
    ok = gb_net();
    recv_status = ok ? GB_NET_RX_IDLE : GB_NET_RX_ERROR;
    return ok;
}

/* gb_net_send: returns 1 = ok. len capped to GBNET_MAXIO (chunk in the caller if more). */
unsigned char gb_net_send(const unsigned char *buf, unsigned int len)
{
    unsigned int i;
    if (len > GBNET_MAXIO) len = GBNET_MAXIO;
    for (i = 0; i < len; i++) GBNET_BUF[i] = buf[i];
    GBNET_LEN = len;
    GBNET_OP = 4;
    gb_net();
    return GBNET_RES;
}

/* gb_net_recv: up to maxlen bytes into buf; returns bytes received (0 if none ready). */
unsigned int gb_net_recv(unsigned char *buf, unsigned int maxlen)
{
    unsigned int n, i;
    if (maxlen > GBNET_MAXIO) maxlen = GBNET_MAXIO;
    GBNET_LEN = maxlen;
    GBNET_OP = 5;
    gb_net();
    n = GBNET_RES2;
    recv_status = GBNET_RES;
    if (recv_status < GB_NET_RX_DATA || recv_status > GB_NET_RX_ERROR)
        recv_status = n ? GB_NET_RX_DATA : GB_NET_RX_ERROR;
    for (i = 0; i < n; i++) buf[i] = GBNET_BUF[i];
    return n;
}

unsigned char gb_net_recv_status(void) { return recv_status; }

void gb_net_close(void)
{
    GBNET_OP = 6;
    gb_net();
    recv_status = GB_NET_RX_CLOSED;
}

unsigned int gb_net_rxavail(void) { GBNET_OP = 7; gb_net(); return GBNET_RES2; }

unsigned char gb_net_connected(void) { GBNET_OP = 8; return gb_net(); }

/* gb_net_resolve: resolve a hostname to ip4[4] via DNS (UDP socket 1; uses the DNS
 * server from gb_net_init's cfg). Returns 1 = resolved, 0 = failed. Blocks (~seconds)
 * on a lost reply. Call after gb_net_init. */
unsigned char gb_net_resolve(const char *host, unsigned char *ip4)
{
    unsigned int i = 0, j;
    if (dns_cache_valid) {
        while (i <= GBNET_DNS_CACHE_MAX && host[i] == dns_cache_host[i]) {
            if (!host[i]) {
                ip4[0] = dns_cache_ip[0]; ip4[1] = dns_cache_ip[1];
                ip4[2] = dns_cache_ip[2]; ip4[3] = dns_cache_ip[3];
                return 1;
            }
            i++;
        }
    }
    i = 0;
    while (host[i] && i < GBNET_DNS_MAX_HOST) {
        GBNET_BUF[i] = (unsigned char)host[i]; i++;
    }
    if (host[i]) return 0;
    GBNET_BUF[i] = 0;
    GBNET_OP = 9;
    if (!gb_net()) return 0;
    ip4[0] = GBNET_IP[0]; ip4[1] = GBNET_IP[1]; ip4[2] = GBNET_IP[2]; ip4[3] = GBNET_IP[3];
    if (i <= GBNET_DNS_CACHE_MAX) {
        for (j = 0; j <= i; j++) dns_cache_host[j] = host[j];
        dns_cache_ip[0] = ip4[0]; dns_cache_ip[1] = ip4[1];
        dns_cache_ip[2] = ip4[2]; dns_cache_ip[3] = ip4[3];
        dns_cache_valid = 1;
    }
    return 1;
}
