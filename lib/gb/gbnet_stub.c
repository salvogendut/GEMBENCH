/* gbnet_stub.c - app-side stubs for the paged W5100 networking module (#238).
 *
 * Apps that want networking link this (build_capp NET=1). Each gb_net_* call marshals an
 * op + args into the fixed low-RAM GBNET block and calls gb_net() (the GB_NET kernel
 * call), which pages in GBNET.MOD and runs the real socket driver. Mirrors gbui_stub.c.
 * Buffers cross via the #2200 low-RAM data region (shared with the file-write modules,
 * mutually exclusive). The driver is socket 0, TCP. */
#include "gb.h"

#define GBNET_OP   (*(volatile unsigned char *)0x1490)   /* op selector */
#define GBNET_RES  (*(volatile unsigned char *)0x1491)   /* status byte */
#define GBNET_RES2 (*(volatile unsigned int  *)0x1492)   /* word result (recv len / rx avail) */
#define GBNET_IP   ((unsigned char *)0x1494)             /* connect dest IP (4 bytes) */
#define GBNET_PORT (*(volatile unsigned int  *)0x1498)   /* connect dest port */
#define GBNET_LEN  (*(volatile unsigned int  *)0x149A)   /* send/recv length */
#define GBNET_BUF  ((unsigned char *)0x2200)             /* data + net_config_t (init) */
#define GBNET_MAXIO 1024U                                /* per-call chunk cap */

extern unsigned char gb_net(void);   /* GB_NET trampoline -> GBNET_RES in A */

/* gb_net_init: cfg22 = ip[4] mask[4] gw[4] dns[4] mac[6]. Returns 1 = chip ok. */
unsigned char gb_net_init(const unsigned char *cfg22)
{
    unsigned char i;
    for (i = 0; i < 22; i++) GBNET_BUF[i] = cfg22[i];
    GBNET_OP = 1;
    return gb_net();
}

unsigned char gb_net_open(void) { GBNET_OP = 2; return gb_net(); }

unsigned char gb_net_connect(const unsigned char *ip, unsigned int port)
{
    GBNET_IP[0] = ip[0]; GBNET_IP[1] = ip[1]; GBNET_IP[2] = ip[2]; GBNET_IP[3] = ip[3];
    GBNET_PORT = port;
    GBNET_OP = 3;
    return gb_net();
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
    for (i = 0; i < n; i++) buf[i] = GBNET_BUF[i];
    return n;
}

void gb_net_close(void) { GBNET_OP = 6; gb_net(); }

unsigned int gb_net_rxavail(void) { GBNET_OP = 7; gb_net(); return GBNET_RES2; }

unsigned char gb_net_connected(void) { GBNET_OP = 8; return gb_net(); }

/* gb_net_resolve: resolve a hostname to ip4[4] via DNS (UDP socket 1; uses the DNS
 * server from gb_net_init's cfg). Returns 1 = resolved, 0 = failed. Blocks (~seconds)
 * on a lost reply. Call after gb_net_init. */
unsigned char gb_net_resolve(const char *host, unsigned char *ip4)
{
    unsigned int i = 0;
    while (host[i] && i < GBNET_MAXIO - 1) { GBNET_BUF[i] = (unsigned char)host[i]; i++; }
    GBNET_BUF[i] = 0;
    GBNET_OP = 9;
    if (!gb_net()) return 0;
    ip4[0] = GBNET_IP[0]; ip4[1] = GBNET_IP[1]; ip4[2] = GBNET_IP[2]; ip4[3] = GBNET_IP[3];
    return 1;
}
