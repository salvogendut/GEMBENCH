/* gbnet_init.c - W5100S chip init for GBNET.MOD (#238).
 * Extracted from cpc-sdcc src/netinit.c: just net_init(cfg) + helpers; the CAS/POKE
 * config-file readers are dropped (GEOBENCH passes the net_config_t via the transfer
 * buffer). */
#include "w5100.h"
#include "netinit.h"

/* Verify chip presence: MR (#FD20) must read back 0x03 (AI + IND bits set). */
static unsigned char chip_present(void) __naked {
    __asm
        push    bc
        ld      bc, #0xFD20
        in      a, (c)
        cp      #3
        ld      a, #0
        jr      nz, 00001$
        ld      a, #1
    00001$:
        pop     bc
        ret
    __endasm;
}

static void write_bytes(unsigned int reg, const unsigned char *src, unsigned int n) {
    while (n--)
        w5100_write_reg(reg++, (unsigned int)*src++);
}

int net_init(const net_config_t *cfg) {
    if (!chip_present())
        return -1;

    /* 1-second ARP retry time (10000 = 0x2710), 10 retries */
    w5100_write_reg(N_RTR0,     0x27);
    w5100_write_reg(N_RTR0 + 1, 0x10);
    w5100_write_reg(N_RCR,      10);

    write_bytes(N_SHAR0, cfg->mac,     6);
    write_bytes(N_GAR0,  cfg->gateway, 4);
    write_bytes(N_SUBR0, cfg->netmask, 4);
    write_bytes(N_SIPR0, cfg->ip,      4);
    write_bytes(N_DNS0,  cfg->dns,     4);

    /* 2 KB TX + 2 KB RX per socket on all four sockets */
    w5100_write_reg(N_TMSR, 0x55);
    w5100_write_reg(N_RMSR, 0x55);

    return 0;
}
