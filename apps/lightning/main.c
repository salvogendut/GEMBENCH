/* lightning - fractal lightning screensaver for GEOBENCH (#219 family).
 *
 * Ported from the xscreensaver lightning hack (Keith Romberg). A bolt is built top-to-
 * bottom by midpoint displacement: the y values march linearly down the screen while the
 * x of each midpoint is jittered by an amount that shrinks with the segment length, giving
 * the jagged forked look. One random fork branches off a mid vertex. The bolt flashes,
 * holds, blanks, and strikes again. Integer Bresenham lines straight to #C000; coords stay
 * on-screen so no overflow. Card-only (the floppy pack is full). */
#include "gb.h"
#include "../savdraw.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#ifdef GB_MSX2
#define KCFG_BORDER (*(volatile unsigned char *)0x122C) /* MSX: border==paper==palette[0] (INKS[0]) */
#else
#define KCFG_BORDER (*(volatile unsigned char *)0x1230) /* CPC: desktop's border ink (INKS= 5th) */
#endif
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG    2          /* black sky */
#define NSEG  32         /* bolt segments (power of two) */
#define NPTS  (NSEG + 1)
#define FSEG  8          /* fork segments */
#define FPTS  (FSEG + 1)
#define HOLD  6          /* frames a bolt stays lit */

static unsigned char lmx, lmy, armed;
static unsigned int  rng;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

static volatile unsigned char brd_ink;
#ifdef GB_MSX2
static void set_border(void) __naked
{
__asm
    ld   a,(_brd_ink)     ; A = the border ink number
    ld   b,a              ; B = ink (GB_SETINK arg)
    xor  a                ; A = 0 = pen 0; on Screen 6 the border/backdrop = palette[0]
    call 0x8006           ; GB_SETINK -> set palette[0] (blacks or restores the border)
    ret
__endasm;
}
#else
static void set_border(void) __naked
{
__asm
    ld   a,(_brd_ink)
    ld   b,a
    ld   c,a
    call 0xBC38
    ret
__endasm;
}
#endif

#ifndef GB_MSX2
static void vram_pixel(int sx, int sy, unsigned char ink)
{
    unsigned char *p, pos, lo, hi, b;
    if (sx < 0 || sx >= 320 || sy < 0 || sy >= 200) return;
    p = (unsigned char *)(0xC000u + (unsigned int)(sy >> 3) * 80u
        + (unsigned int)(sy & 7) * 0x800u + (unsigned int)(sx >> 2));
    pos = (unsigned char)(sx & 3);
    lo = (unsigned char)(0x80u >> pos);
    hi = (unsigned char)(0x08u >> pos);
    b = (unsigned char)(*p & ~(lo | hi));
    if (ink & 1) b |= lo;
    if (ink & 2) b |= hi;
    *p = b;
}

static void vram_line(int x0, int y0, int x1, int y1, unsigned char ink)
{
    long dx, dy, sx, sy, err, e2;
    if (x0 < -999 || x0 > 999 || y0 < -999 || y0 > 999 ||
        x1 < -999 || x1 > 999 || y1 < -999 || y1 > 999) return;
    dx = x1 - x0; if (dx < 0) dx = -dx;
    dy = y1 - y0; if (dy < 0) dy = -dy;
    sx = (x0 < x1) ? 1 : -1;
    sy = (y0 < y1) ? 1 : -1;
    err = dx - dy;
    for (;;) {
        vram_pixel(x0, y0, ink);
        if (x0 == x1 && y0 == y1) break;
        e2 = err + err;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 <  dx) { err += dx; y0 += sy; }
    }
}
#endif

static int xs[NPTS], ys[NPTS];
static int fxs[FPTS], fys[FPTS];
static unsigned char fork_at, phase, timer;

static int clampx(int x) { return x < 2 ? 2 : (x > 317 ? 317 : x); }

static void subdivide(int *px, int *py, unsigned char n)  /* midpoint-displace px[0..n] */
{
    unsigned char level, half, i;
    for (level = n; level > 1; level >>= 1) {
        half = (unsigned char)(level >> 1);
        for (i = half; i < n; i = (unsigned char)(i + level)) {
            px[i] = clampx((px[i - half] + px[i + half]) / 2
                           + (int)(rnd() % (2 * level + 1)) - level);
            py[i] = (py[i - half] + py[i + half]) / 2;
        }
    }
}

static void gen_bolt(void)
{
    unsigned char i;
    xs[0]    = clampx(40 + (int)(rnd() % 240)); ys[0]    = 0;
    xs[NSEG] = clampx(40 + (int)(rnd() % 240)); ys[NSEG] = 199;
    for (i = 1; i < NSEG; i++) ys[i] = (int)((long)i * 199 / NSEG);  /* linear y seed */
    subdivide(xs, ys, NSEG);

    fork_at = (unsigned char)(8 + rnd() % (NSEG - 16));              /* fork vertex */
    fxs[0]    = xs[fork_at];                 fys[0]    = ys[fork_at];
    fxs[FSEG] = clampx(40 + (int)(rnd() % 240)); fys[FSEG] = 199;
    for (i = 1; i < FSEG; i++) fys[i] = fys[0] + (int)((long)i * (199 - fys[0]) / FSEG);
    subdivide(fxs, fys, FSEG);
}

static void draw_bolt(unsigned char ink)
{
    unsigned char i;
    for (i = 0; i < NSEG; i++) {
        vram_line(xs[i], ys[i], xs[i+1], ys[i+1], ink);
        vram_line(xs[i]+1, ys[i], xs[i+1]+1, ys[i+1], ink);   /* 2px = brighter */
    }
    for (i = 0; i < FSEG; i++)
        vram_line(fxs[i], fys[i], fxs[i+1], fys[i+1], ink);
}

static void ss_paint(void)
{
    gb_fill(0, 0, GB_COLS, GB_LINES, BG);
}

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
        brd_ink = KCFG_BORDER;
        set_border();
        WM_FS = 0;
        gb_wm_close();
        return;
    }
    if (timer) { timer--; return; }
    if (phase == 0) {                 /* bolt was lit -> blank + dark gap */
        ss_paint();
        phase = 1;
        timer = (unsigned char)(8 + rnd() % 32);
    } else {                          /* gap over -> new strike */
        gen_bolt();
        draw_bolt(1);                 /* white bolt */
        phase = 0;
        timer = HOLD;
    }
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x4C49u);
    if (!rng) rng = 0x4C49u;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gen_bolt();
    draw_bolt(1);
    phase = 0; timer = HOLD;
    gb_wm_add(&sswin);
}
