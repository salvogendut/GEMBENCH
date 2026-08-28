/* netspike - minimal Net4CPC (W5100S) round-trip test, used to de-risk #238 Phase 0.
 * Connects to a local TCP server and prints what it receives. Built against the
 * cpc-sdcc C driver (~/Dev/cpc-sdcc/src: w5100.c/net.c/netinit.c). See README.md. */
#include "cpcbios.h"
#include "netinit.h"
#include "net.h"
#include "w5100.h"

static unsigned char rxbuf[64];

void main(void) {
    static net_config_t cfg = {
        {192,168,99,50}, {255,255,255,0}, {192,168,99,1},
        {192,168,99,1}, {0xDE,0xAD,0xBE,0xEF,0x00,0xFF}
    };
    unsigned char dst[4] = {127,0,0,1};   /* host loopback (emulator host-socket mode) */
    unsigned int received, idle;
    cpc_set_mode(1);
    cpc_cls();
    cpc_print("NET SPIKE\r\n");
    if (net_init(&cfg))       { cpc_print("NO CHIP\r\n"); while(1); }
    cpc_print("init ok\r\n");
    if (net_socket_open())    { cpc_print("OPEN FAIL\r\n"); while(1); }
    cpc_print("open ok\r\n");
    if (net_connect(dst, 2323)) { cpc_print("CONNECT FAIL\r\n"); while(1); }
    cpc_print("CONNECTED!\r\n");
    net_send((const unsigned char *)"hi\r\n", 4);
    idle = 0;
    while (idle < 400U) {
        received = net_recv(rxbuf, sizeof(rxbuf));
        if (received) {
            unsigned int i;
            for (i = 0; i < received; i++) {
                unsigned char c = rxbuf[i];
                if (c >= 0x20 || c == '\r' || c == '\n') cpc_print_char(c);
            }
            idle = 0;
        } else idle++;
    }
    net_close();
    cpc_print("\r\nDONE\r\n");
    while(1);
}
