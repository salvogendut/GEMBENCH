/* saver - the GEOBENCH screensaver: a handful of coloured balls bouncing around
 * the full screen.
 *
 * A screensaver is just an app (built like any other, shipped with a .SAV extension
 * instead of .APP). The desktop's idle timer launches it via gb_wm_open after the
 * SAVER timeout; it runs as a normal co-resident window. What makes it a "saver":
 *   - it sets WM_FS so the desktop's top bar steps aside and it owns all 200 lines;
 *   - its per-frame handler animates, and closes the moment it sees ANY input
 *     (a typed key, a click/fire/ESC, or a pointer move), handing back to the desktop.
 *
 * Design (#281): a FIXED POOL of balls. Every frame each ball erases its own previous
 * position (redraw in the background pen) before moving and redrawing. Because the
 * pool is bounded and self-cleaning, the screen never accumulates - so it can't pile
 * circles into the solid bands the old spray-and-periodically-clear version produced,
 * and the balls stay recognisably round. */
#include "gb.h"

/* WM_FS (#130A): the app-side full-screen flag the desktop's bar_draw reads each
 * frame. 1 = a borderless window owns lines 0-7, so the bar suppresses itself. */
#define WM_FS (*(volatile unsigned char *)0x130A)

#define NBALL 10                 /* balls on screen (kept sparse: no crowding, stays fast) */

static unsigned char lmx, lmy;   /* pointer position at launch - a change = wake */
static unsigned char armed;      /* 0 until one clean frame: swallows the launch click */
static unsigned char started;    /* the pool has been initialised */
static unsigned int  rng;        /* PRNG state (16-bit LCG) */

/* Per-ball state. The centre is fixed-point: bx/by are (byte-column * 8) and
 * (line * 8), so a ball drifts a fraction of a cell per frame; >> 3 recovers the
 * integer byte-column (0..79) / line (0..199). Velocity is in those eighths. */
static int          bx[NBALL], by[NBALL];
static signed char  bvx[NBALL], bvy[NBALL];
static unsigned char br[NBALL], bp[NBALL];   /* radius (px) and pen */

/* rnd: 16-bit LCG (full 65536 period). Its HIGH byte is the well-distributed part;
 * rr() reduces that onto 0..n-1 uniformly, avoiding the weak low bits. */
static unsigned int rnd(void) { rng = (unsigned int)(rng * 25173u + 13849u); return rng; }
static unsigned char rr(unsigned char n) { return (unsigned char)(((rnd() >> 8) * (unsigned int)n) >> 8); }

/* isqrt: integer square root (0..255) of v, for the disc's per-scanline half-width. */
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

/* disc: a solid circle centred at byte-column cxb, line cy, radius R px, in pen.
 * One horizontal gb_fill per scanline, clipped to the screen so a ball may sit
 * partly off an edge. Drawing in pen 0 (the background) erases it. */
static void disc(int cxb, int cy, unsigned char R, unsigned char pen)
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

/* vel: a non-zero signed speed, +/- (2..6) eighths of a cell per frame. */
static signed char vel(void)
{
    unsigned char s = (unsigned char)(2 + rr(5));
    return rr(2) ? (signed char)s : (signed char)-(int)s;
}

static void init_balls(void)
{
    unsigned char i;
    for (i = 0; i < NBALL; i++) {
        br[i] = (unsigned char)(6 + rr(9));          /* radius 6..14 px */
        bp[i] = (unsigned char)(1 + rr(3));          /* pens 1..3 (not the background) */
        bx[i] = (int)(6 + rr(68)) << 3;              /* centre byte-col ~6..73 */
        by[i] = (int)(14 + rr(172)) << 3;            /* centre line ~14..185 */
        bvx[i] = vel();
        bvy[i] = vel();
    }
    started = 1;
}

/* advance: move ball i and bounce its centre off the screen edges. */
static void advance(unsigned char i)
{
    int x = bx[i] + bvx[i], y = by[i] + bvy[i];
    if (x < 0)         { x = 0;         bvx[i] = (signed char)-bvx[i]; }
    if (x > (79 << 3)) { x = 79 << 3;   bvx[i] = (signed char)-bvx[i]; }
    if (y < 0)         { y = 0;         bvy[i] = (signed char)-bvy[i]; }
    if (y > (199 << 3)){ y = 199 << 3;  bvy[i] = (signed char)-bvy[i]; }
    bx[i] = x; by[i] = y;
}

static void ss_frame(void)
{
    unsigned char i, f = gb_flags();
    /* The click/key that launched us is still settling on the first frame(s) - a held
       fire reads as GB_FIRE and would close us instantly. Wait for one clean frame
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
    if (!started) init_balls();
    /* Blank the whole screen, then move and redraw every ball. Repainting from a clean
       slate every frame means nothing is ever left behind - no trails, no accumulation,
       so the screen can never build up into the solid bands the old version produced. */
    gb_fill(0, 0, 80, 200, 0);
    for (i = 0; i < NBALL; i++) advance(i);
    for (i = 0; i < NBALL; i++) disc(bx[i] >> 3, by[i] >> 3, br[i], bp[i]);
}

static void ss_paint(void)
{
    gb_fill(0, 0, 80, 200, 0);   /* blank to pen 0; the balls draw over it */
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();   /* baseline: wake when the pointer leaves here */
    armed = 0; started = 0;
    gb_time();                      /* seed the PRNG from the clock (differs each launch) */
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0xACE1u);
    if (!rng) rng = 0xACE1u;
    WM_FS = 1;                      /* full screen: the desktop bar steps aside */
    gb_curhide();                   /* no pointer over the blank screen */
    for (n = 64; n; n--) if (!gb_getkey()) break;  /* drain any launch keystrokes */
    ss_paint();                     /* clear now (don't wait for the first repaint) */
    gb_wm_add(&sswin);              /* register the window, return to the opener */
}
