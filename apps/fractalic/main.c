/* fractalic - a fractal screensaver for GEOBENCH (#219 family).
 *
 * Ported from the SymbOS symsav-fractalic screensaver. Picks one of two fractals at
 * random and draws it incrementally, holds it, then clears and picks another:
 *   - Sierpinski triangle  (chaos game)
 *   - Koch snowflake       (iterative segment expansion)
 * (The original's Dragon curve and Barnsley fern are dropped: the Dragon misbehaved
 *  on the CPC, and the fern's IFS needs a better-distributed RNG than our 16-bit
 *  xorshift's rnd()%100 to form its fronds.)
 *
 * Like mountain, it plots single pixels straight to the #C000 Mode-1 screen
 * (always mapped, not banked) - the original's per-pixel plot ports verbatim, no
 * Bank_Copy. The SymbOS config dialog is dropped: depth/speed are baked in and the
 * type is always random (the user asked for a random pick each cycle). This is the
 * biggest saver, so it ships on the Albireo card only (the floppy is too tight). */
#include "gb.h"
#include "../savdraw.h"

#define WM_FS (*(volatile unsigned char *)0x130A)

#define F_SIER   1
#define F_KOCH   2
static const unsigned char ftypes[2] = { F_SIER, F_KOCH };

#define DEPTH    2       /* fractal detail (1-3) */
#define SPD      3       /* draw speed multiplier */
#define PAUSE    150     /* frames a finished fractal is held */
#define BG       0       /* blue background */

#define KOCH_MAX 200
static int kx0[KOCH_MAX], ky0[KOCH_MAX], kx1[KOCH_MAX], ky1[KOCH_MAX];
static int tx0[KOCH_MAX], ty0[KOCH_MAX], tx1[KOCH_MAX], ty1[KOCH_MAX];

static int sax, say, sbx, sby, scx, scy, spx, spy, sstep, stotal;  /* sierpinski */
static int draw_idx, draw_total;

static unsigned char frac_type, anim_stage;
static int anim_timer;
static unsigned char lmx, lmy, armed;
static unsigned int  rng;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* plot one Mode-1 pixel straight into #C000 (same as mountain). */
#ifndef GB_MSX2
static void vram_pixel(int x, int y, unsigned char ink)
{
    unsigned char *p, pos, lo, hi, b;
    if (x < 0 || x >= 320 || y < 0 || y >= 200) return;
    p = (unsigned char *)(0xC000u + (unsigned int)(y >> 3) * 80u
        + (unsigned int)(y & 7) * 0x800u + (unsigned int)(x >> 2));
    pos = (unsigned char)(x & 3);
    lo = (unsigned char)(0x80u >> pos);
    hi = (unsigned char)(0x08u >> pos);
    b = (unsigned char)(*p & ~(lo | hi));
    if (ink & 1) b |= lo;
    if (ink & 2) b |= hi;
    *p = b;
}

static void vram_line(int x0, int y0, int x1, int y1, unsigned char ink)
{
    long dx, dy, sx, sy, err, e2;   /* long: a stray long line can't overflow the
                                       16-bit Bresenham accumulator and hang */
    if (x0 < -999 || x0 > 999 || y0 < -999 || y0 > 999 ||
        x1 < -999 || x1 > 999 || y1 < -999 || y1 > 999) return;   /* guard bogus coords */
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

/* ---- Sierpinski (chaos game) -------------------------------------------- */
static const unsigned char sier_ink[3] = { 3, 2, 1 };   /* red, black, white */

static void sierpinski_init(void)
{
    sax = 160; say = 10;
    sbx = 20;  sby = 188;
    scx = 300; scy = 188;
    spx = sax; spy = say;
    sstep = 0;
    stotal = (DEPTH == 1) ? 8000 : (DEPTH == 3) ? 30000 : 18000;
}
static void sierpinski_steps(int n)
{
    int v, nx, ny, i;
    for (i = 0; i < n && sstep < stotal; i++, sstep++) {
        v = (int)(rnd() % 3);
        if (v == 0)      { nx = (spx + sax) >> 1; ny = (spy + say) >> 1; }
        else if (v == 1) { nx = (spx + sbx) >> 1; ny = (spy + sby) >> 1; }
        else             { nx = (spx + scx) >> 1; ny = (spy + scy) >> 1; }
        spx = nx; spy = ny;
        vram_pixel(nx, ny, sier_ink[v]);
    }
}

/* ---- Koch snowflake (iterative segment expansion) ----------------------- */
static void koch_init(void)
{
    int i, j, n, ns, p1x, p1y, p2x, p2y, mx, my, px, py, dx, dy, apx, apy, W;
    W = 6 * (200 - 13) / 7;
    p1x = 160; p1y = 7;
    p2x = p1x - W / 2; p2y = p1y + W * 7 / 8;
    mx = p1x + W / 2;  my = p2y;
    kx0[0] = p1x; ky0[0] = p1y; kx1[0] = p2x; ky1[0] = p2y;
    kx0[1] = p2x; ky0[1] = p2y; kx1[1] = mx;  ky1[1] = my;
    kx0[2] = mx;  ky0[2] = my;  kx1[2] = p1x; ky1[2] = p1y;
    n = 3;
    for (i = 0; i < DEPTH; i++) {
        ns = 0;
        for (j = 0; j < n && ns + 4 <= KOCH_MAX; j++) {
            p1x = kx0[j]; p1y = ky0[j];
            p2x = kx1[j]; p2y = ky1[j];
            mx = p1x + (p2x - p1x) / 3;       my = p1y + (p2y - p1y) / 3;
            px = p1x + (p2x - p1x) * 2 / 3;   py = p1y + (p2y - p1y) * 2 / 3;
            dx = px - mx; dy = py - my;
            apx = (mx + px) / 2 - dy * 7 / 8;
            apy = (my + py) / 2 + dx * 7 / 8;
            tx0[ns] = p1x; ty0[ns] = p1y; tx1[ns] = mx;  ty1[ns] = my;  ns++;
            tx0[ns] = mx;  ty0[ns] = my;  tx1[ns] = apx; ty1[ns] = apy; ns++;
            tx0[ns] = apx; ty0[ns] = apy; tx1[ns] = px;  ty1[ns] = py;  ns++;
            tx0[ns] = px;  ty0[ns] = py;  tx1[ns] = p2x; ty1[ns] = p2y; ns++;
        }
        for (j = 0; j < ns; j++) {
            kx0[j] = tx0[j]; ky0[j] = ty0[j];
            kx1[j] = tx1[j]; ky1[j] = ty1[j];
        }
        n = ns;
    }
    draw_idx = 0; draw_total = n;
}
static void koch_steps(int count)
{
    int i;
    for (i = 0; i < count && draw_idx < draw_total; i++, draw_idx++)
        vram_line(kx0[draw_idx], ky0[draw_idx], kx1[draw_idx], ky1[draw_idx],
                  (unsigned char)((draw_idx & 1) ? 3 : 1));   /* red / white segments */
}

/* ---- dispatch ----------------------------------------------------------- */
static void fractal_init(void)
{
    if (frac_type == F_SIER) sierpinski_init();
    else                     koch_init();
}
static unsigned char fractal_done(void)
{
    if (frac_type == F_SIER) return (unsigned char)(sstep >= stotal);
    return (unsigned char)(draw_idx >= draw_total);
}
static void fractal_step(void)
{
    if (frac_type == F_SIER) sierpinski_steps(SPD * 200);
    else                     koch_steps(SPD);
}

static void anim_tick(void)
{
    if (anim_stage == 0) {
        fractal_step();
        if (fractal_done()) { anim_stage = 1; anim_timer = PAUSE; }
    } else if (anim_stage == 1) {
        if (--anim_timer <= 0) anim_stage = 2;
    } else {
        frac_type = ftypes[rnd() % 2];                  /* a new random fractal */
        gb_fill(0, 0, GB_COLS, GB_LINES, BG);
        fractal_init();
        anim_stage = 0;
    }
}

static void ss_paint(void)
{
    gb_fill(0, 0, GB_COLS, GB_LINES, BG);
    anim_stage = 0;
    fractal_init();
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
        WM_FS = 0;
        gb_wm_close();
        return;
    }
    anim_tick();
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0xF7A3u);
    if (!rng) rng = 0xF7A3u;
    frac_type = ftypes[rnd() % 2];                /* random fractal at start */
    WM_FS = 1;
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
