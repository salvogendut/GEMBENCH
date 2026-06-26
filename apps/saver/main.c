/* saver - the first GEOBENCH screensaver (#219).
 *
 * A screensaver is just an app (built like any other, but shipped with a .SAV
 * extension). The desktop's idle timer launches the configured module via gb_wm_open
 * after the SAVER timeout; it runs as a normal co-resident window. What makes it a
 * "saver":
 *   - it sets WM_FS so the desktop's top-bar handler steps aside -> the window owns
 *     all 200 lines (a true full-screen blank);
 *   - its per-frame handler animates, and watches for ANY input - a typed key, a
 *     click/fire/ESC, or a pointer move - and closes itself the moment it sees one,
 *     handing control back to the desktop.
 *
 * This module: random-sized circles popping at random positions in random inks,
 * continuously, with a periodic clear. New screensavers are new apps with the same
 * shape - full-screen window, animate in on_frame, close on input. */
#include "gb.h"

/* WM_FS (#130A): the app-side full-screen flag the desktop's bar_draw reads each
 * frame. 1 = a borderless window owns lines 0-7, so the bar suppresses itself. */
#define WM_FS (*(volatile unsigned char *)0x130A)

#define CLEAR_EVERY 180    /* frames between full clears (~3.6s) so it never saturates */

static unsigned char lmx, lmy;   /* pointer position at launch - a change = wake */
static unsigned char armed;      /* 0 until one clean frame: swallows the launch click */
static unsigned int  rng;        /* PRNG state (xorshift16) */
static unsigned int  tick;       /* frames since the last clear */

/* rnd: 16-bit xorshift PRNG - a different stream each launch (seeded from the clock). */
static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* isqrt: integer square root (0..255) of v, for the circle's per-scanline width. */
static unsigned char isqrt(unsigned int v)
{
    unsigned int rem = v, root = 0, bit = 1u << 14;
    while (bit > rem) bit >>= 2;
    while (bit) {
        if (rem >= root + bit) { rem -= root + bit; root = (root >> 1) + bit; }
        else root >>= 1;
        bit >>= 2;
    }
    return (unsigned char)root;
}

/* draw_circle: a solid disc centred at byte column cxb, line cy, radius R pixels, in
 * pen. One horizontal gb_fill per scanline; clips to the screen so the centre can sit
 * anywhere (off-screen parts are dropped). */
static void draw_circle(int cxb, int cy, unsigned char R, unsigned char pen)
{
    int dy;
    for (dy = -(int)R; dy <= (int)R; dy++) {
        int line = cy + dy, x0, x1, hwb;
        unsigned char hwp;
        if (line < 0 || line > 199) continue;
        hwp = isqrt((unsigned int)((int)R * R - dy * dy));   /* half width, pixels */
        hwb = (hwp + 2) / 4;                                  /* -> byte columns */
        if (hwb <= 0) continue;
        x0 = cxb - hwb; x1 = cxb + hwb;
        if (x0 < 0) x0 = 0;
        if (x1 > 80) x1 = 80;
        if (x1 <= x0) continue;
        gb_fill((unsigned char)x0, (unsigned char)line, (unsigned char)(x1 - x0), 1, pen);
    }
}

/* step: one frame of animation - a fresh random circle, and a periodic clear. */
static void step(void)
{
    unsigned char R   = (unsigned char)(3 + rnd() % 22);   /* 3..24 px */
    unsigned char cxb = (unsigned char)(rnd() % 80);       /* random column */
    unsigned char cy  = (unsigned char)(rnd() % 200);      /* random line */
    unsigned char pen = (unsigned char)(1 + rnd() % 3);    /* pens 1..3 (not the bg) */
    draw_circle((int)cxb, (int)cy, R, pen);
    if (++tick >= CLEAR_EVERY) { tick = 0; gb_fill(0, 0, 80, 200, 0); }
}

static void ss_paint(void)
{
    gb_fill(0, 0, 80, 200, 0);   /* blank to pen 0; step() fills it in */
    tick = 0;
}

static void ss_frame(void)
{
    unsigned char f = gb_flags();
    /* The click (or key) that launched us is still settling on the first frame(s) - a
       held fire reads as GB_FIRE and would close us instantly. Wait for one clean frame
       before we start watching for a wake; keep animating meanwhile. */
    if (!armed) {
        while (gb_getkey()) ;                            /* drain residual keystrokes */
        if (!(f & (GB_CLICK | GB_FIRE | GB_QUIT))) {
            lmx = gb_mx(); lmy = gb_my();                /* re-baseline the pointer */
            armed = 1;
        }
    } else if (gb_getkey() ||                            /* a typed key */
               (f & (GB_CLICK | GB_FIRE | GB_QUIT)) ||   /* a click / fire / ESC */
               gb_mx() != lmx || gb_my() != lmy) {       /* the pointer moved */
        WM_FS = 0;                                       /* let the top bar redraw */
        gb_wm_close();                                   /* hand control to the desktop */
        return;
    }
    step();
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();   /* baseline: wake when the pointer leaves here */
    armed = 0;
    gb_time();                      /* seed the PRNG from the clock (differs each launch) */
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0xACE1u);
    if (!rng) rng = 0xACE1u;
    WM_FS = 1;                      /* full screen: the desktop bar steps aside */
    gb_curhide();                   /* no pointer over the blank screen */
    for (n = 64; n; n--) if (!gb_getkey()) break;  /* drain any launch keystrokes */
    ss_paint();                     /* clear now (don't wait for the first repaint) */
    gb_wm_add(&sswin);              /* register the window, return to the opener */
}
