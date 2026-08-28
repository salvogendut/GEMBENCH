/* dnsspike - exercise the GEOBENCH-ported DNS resolver (kernel/kc/dns.c + udp.c, the
 * down-counter-timeout variant) standalone, to de-risk #238 Phase 2. Resolves a
 * hostname via the emulator's host-socket UDP path (to the real 8.8.8.8) and prints
 * the answer. Built by build_dns.sh against kernel/kc/. */
#include "cpcbios.h"
#include "netinit.h"
#include "net.h"
#include "dns.h"
#include "w5100.h"

static void print_u8(unsigned char v) {
    unsigned char h = 0, t = 0;
    while (v >= 100) { v -= 100; h++; }
    while (v >= 10)  { v -= 10;  t++; }
    if (h) cpc_print_char('0' + h);
    if (h || t) cpc_print_char('0' + t);
    cpc_print_char('0' + v);
}
static void print_ip(const unsigned char *ip) {
    print_u8(ip[0]); cpc_print_char('.');
    print_u8(ip[1]); cpc_print_char('.');
    print_u8(ip[2]); cpc_print_char('.');
    print_u8(ip[3]);
}

void main(void) {
    static net_config_t cfg = {
        {192,168,99,50}, {255,255,255,0}, {192,168,99,1},
        {8,8,8,8}, {0xDE,0xAD,0xBE,0xEF,0x00,0xFF}     /* DNS = 8.8.8.8 */
    };
    unsigned char ip[4], dns_srv[4];
    int rc;
    cpc_set_mode(1);
    cpc_cls();
    cpc_print("DNS SPIKE\r\n");
    if (net_init(&cfg)) { cpc_print("NO CHIP\r\n"); while (1) ; }
    cpc_print("init ok\r\n");
    dns_srv[0] = w5100_read_reg(N_DNS0);
    dns_srv[1] = w5100_read_reg(N_DNS0 + 1);
    dns_srv[2] = w5100_read_reg(N_DNS0 + 2);
    dns_srv[3] = w5100_read_reg(N_DNS0 + 3);
    cpc_print("dns "); print_ip(dns_srv); cpc_print("\r\n");
    cpc_print("resolve example.com\r\n");
    rc = dns_resolve(dns_srv, "example.com", ip);
    if (rc == 0) { cpc_print("IP "); print_ip(ip); cpc_print("\r\n"); }
    else { cpc_print("FAIL rc="); cpc_print_char('0' - rc); cpc_print("\r\n"); }
    cpc_print("DONE\r\n");
    while (1) ;
}
