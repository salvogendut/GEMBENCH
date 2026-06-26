/* helix - woven harmonograph curves screensaver for GEOBENCH (#219 family).
 *
 * Ported from the xscreensaver helix hack. Two points orbit the centre at integer
 * multiples of a base angle (radius * sin(angle*factor)); connecting them as the angle
 * sweeps weaves a dense lissajous/harmonograph figure. The original keys a precomputed
 * sin/cos table; here it's a 60-entry integer sin table, lines drawn straight to the
 * #C000 Mode-1 screen. A fresh figure with new radii/factors every few seconds.
 * Card-only (the floppy pack is full). */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG    0          /* blue background */
#define CXp   160
#define CYp   100
#define STEPS 120        /* line-pairs per figure */
#define HOLD  150         /* frames a figure lingers */

static const signed char sintab[60] = {
    0, 7, 13, 20, 26, 32, 38, 43, 48, 52, 55, 58, 61, 63, 64, 64, 64, 63, 61, 58,
    55, 52, 48, 43, 38, 32, 26, 20, 13, 7, 0, -7, -13, -20, -26, -32, -38, -43, -48, -52,
    -55, -58, -61, -63, -64, -64, -64, -63, -61, -58, -55, -52, -48, -43, -38, -32, -26, -20, -13, -7
};
#define SN(k) (sintab[(((k) % 60) + 60) % 60])
#define CS(k) (sintab[((((k) + 15) % 60) + 60) % 60])

static unsigned char lmx, lmy, armed, hold;
static unsigned int  rng;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

static volatile unsigned char brd_ink;
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

static const unsigned char pens[3] = { 1, 3, 2 };  /* white, red, black */
static unsigned char penix;

static void draw_figure(void)
{
    int r1 = (int)(45 + rnd() % 35);
    int r2 = (int)(45 + rnd() % 35);
    int f1 = (int)(1 + rnd() % 5);
    int f2 = (int)(1 + rnd() % 5);
    int f3 = (int)(1 + rnd() % 5);
    int f4 = (int)(1 + rnd() % 5);
    unsigned char a, pen = pens[penix];
    penix = (penix + 1) % 3;
    for (a = 0; a < STEPS; a++) {
        int x1 = CXp + (r1 * SN(a * f1)) / 64;
        int y1 = CYp + (r2 * CS(a * f2)) / 64;
        int x2 = CXp + (r2 * SN(a * f3)) / 64;
        int y2 = CYp + (r1 * CS(a * f4)) / 64;
        vram_line(x1, y1, x2, y2, pen);
    }
}

static void ss_paint(void)
{
    gb_fill(0, 0, 80, 200, BG);
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
    if (hold) { hold--; return; }
    ss_paint();
    draw_figure();
    hold = HOLD;
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0; hold = 0; penix = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x4858u);
    if (!rng) rng = 0x4858u;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    draw_figure();
    hold = HOLD;
    gb_wm_add(&sswin);
}
