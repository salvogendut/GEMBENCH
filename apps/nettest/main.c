/* nettest - GBNET.MOD smoke test (#238 Phase 0). Connects to a local TCP server via the
 * gb_net_* API (the paged W5100 module) and prints the reply. Fullscreen; any key/click
 * closes it. Test against tools/netspike/server.py on 127.0.0.1:2323. */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)

/* ip[4] mask[4] gw[4] dns[4] mac[6] - host-socket mode ignores most of it. */
static const unsigned char cfg[22] = {
    192,168,99,50, 255,255,255,0, 192,168,99,1, 192,168,99,1,
    0xDE,0xAD,0xBE,0xEF,0x00,0xFF
};
static unsigned char rx[64];
static unsigned char lmx, lmy, armed;

static void say(unsigned char line, const char *s) { gb_text(2, line, s); }

static void run_test(void)
{
    unsigned char dst[4] = {127,0,0,1};
    unsigned int n, idle, ln;
    say(8, "GBNET TEST");
    if (!gb_net_init(cfg))        { say(24, "NO CHIP"); return; }
    say(24, "init ok");
    if (!gb_net_open())           { say(32, "open fail"); return; }
    say(32, "open ok");
    if (!gb_net_connect(dst, 2323)) { say(40, "connect FAIL"); return; }
    say(40, "CONNECTED!");
    gb_net_send((const unsigned char *)"hi\r\n", 4);
    ln = 48; idle = 0;
    while (idle < 25) {
        n = gb_net_recv(rx, sizeof(rx) - 1);
        if (n) {
            unsigned int i;
            for (i = 0; i < n; i++) if (rx[i] < 0x20 && rx[i] != 0) rx[i] = ' ';
            rx[n] = 0;
            gb_text(2, (unsigned char)ln, (const char *)rx);
            ln += 8; if (ln > 184) ln = 48;
            idle = 0;
        } else idle++;
    }
    gb_net_close();
    say(184, "DONE");
}

static void ss_paint(void) { gb_fill(0, 0, 80, 200, 2); }   /* black */

static void ss_frame(void)
{
    unsigned char f = gb_flags();
    if (!armed) {
        while (gb_getkey()) ;
        if (!(f & (GB_CLICK | GB_FIRE | GB_QUIT))) { lmx = gb_mx(); lmy = gb_my(); armed = 1; }
        return;
    }
    if (gb_getkey() || (f & (GB_CLICK | GB_FIRE | GB_QUIT)) ||
        gb_mx() != lmx || gb_my() != lmy) {
        WM_FS = 0;
        gb_wm_close();
    }
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    lmx = gb_mx(); lmy = gb_my(); armed = 0;
    WM_FS = 1;
    gb_curhide();
    ss_paint();
    run_test();             /* do the net round-trip, draw the result */
    gb_wm_add(&sswin);      /* hold the screen; wake on input */
}
