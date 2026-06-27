/* gbnet_mod.c - GBNET.MOD dispatcher (#238 Phase 0).
 *
 * A paged kernel module (loaded at DATA_MODTOP #6000 in PAGE_DATA on a GB_NET call)
 * that wraps the cpc-sdcc W5100S socket-0 driver (w5100.c/net.c/gbnet_init.c) behind a
 * one-entry, op-selector ABI - exactly like gbui_mod.c's UI_OP dispatch. The app marshals
 * an operation + args into a fixed low-RAM transfer area and the kernel pages us in; we
 * read the cells, call the driver, write results back. The cells are a PER-CALL handoff
 * (nothing runs between the app writing them and us reading them), so #1490 (a free
 * 16-byte low-RAM gap) is safe; the bulk TX/RX/cfg buffer reuses the #2200 module-data
 * region (shared with GBFAT/FLOPPYSV - never live during a net op). */
#include "w5100.h"
#include "net.h"
#include "netinit.h"
#include "dns.h"

/* ---- transfer area (fixed low RAM, always mapped) ---------------------------- */
#define GBNET_OP   (*(volatile unsigned char *)0x1490)   /* IN:  operation selector */
#define GBNET_RES  (*(volatile unsigned char *)0x1491)   /* OUT: 1 = ok / status byte */
#define GBNET_RES2 (*(volatile unsigned int  *)0x1492)   /* OUT: word result (recv len / rx avail) */
#define GBNET_IP   ((unsigned char *)0x1494)             /* IN:  connect dest IP (4 bytes) */
#define GBNET_PORT (*(volatile unsigned int  *)0x1498)   /* IN:  connect dest port */
#define GBNET_LEN  (*(volatile unsigned int  *)0x149A)   /* IN:  send/recv length */
#define GBNET_BUF  ((unsigned char *)0x2200)             /* IN/OUT: data + net_config_t (init) */

#define OP_INIT      1
#define OP_OPEN      2
#define OP_CONNECT   3
#define OP_SEND      4
#define OP_RECV      5
#define OP_CLOSE     6
#define OP_RXAVAIL   7
#define OP_CONNECTED 8
#define OP_RESOLVE   9      /* IN: hostname (NUL-term) in GBNET_BUF; OUT: 4-byte IP in GBNET_IP */

void main(void)
{
    unsigned char op = GBNET_OP;
    if (op == OP_INIT) {
        GBNET_RES = (net_init((const net_config_t *)GBNET_BUF) == 0) ? 1 : 0;
    } else if (op == OP_OPEN) {
        GBNET_RES = (net_socket_open() == 0) ? 1 : 0;
    } else if (op == OP_CONNECT) {
        GBNET_RES = (net_connect(GBNET_IP, GBNET_PORT) == 0) ? 1 : 0;
    } else if (op == OP_SEND) {
        GBNET_RES = (net_send(GBNET_BUF, GBNET_LEN) == 0) ? 1 : 0;
    } else if (op == OP_RECV) {
        GBNET_RES2 = net_recv(GBNET_BUF, GBNET_LEN);
        GBNET_RES = 1;
    } else if (op == OP_CLOSE) {
        net_close();
        GBNET_RES = 1;
    } else if (op == OP_RXAVAIL) {
        GBNET_RES2 = net_rx_available();
        GBNET_RES = 1;
    } else if (op == OP_CONNECTED) {
        GBNET_RES = net_is_connected();
    } else if (op == OP_RESOLVE) {
        /* DNS server was written to the chip by net_init (cfg.dns); read it back and
         * resolve the hostname in GBNET_BUF -> 4-byte IP in GBNET_IP (UDP socket 1). */
        unsigned char dns_srv[4];
        dns_srv[0] = w5100_read_reg(N_DNS0);
        dns_srv[1] = w5100_read_reg(N_DNS0 + 1);
        dns_srv[2] = w5100_read_reg(N_DNS0 + 2);
        dns_srv[3] = w5100_read_reg(N_DNS0 + 3);
        GBNET_RES = (dns_resolve(dns_srv, (const char *)GBNET_BUF, GBNET_IP) == 0) ? 1 : 0;
    } else {
        GBNET_RES = 0;
    }
}
