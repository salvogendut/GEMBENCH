/* forest - recursive fractal trees screensaver for GEOBENCH (#219 family).
 *
 * Ported from the xscreensaver forest hack. Each tree is grown by recursion: draw a
 * tapering branch, then sprout a slightly-straightened continuation plus a couple of
 * angled side branches, shrinking the thickness/length until twigs end in red blossoms.
 * The original uses double trig; here angles are integer 60ths-of-a-circle indexed into
 * a sin table, lines drawn straight to the #C000 Mode-1 screen. A fresh stand of trees
 * is grown every few seconds. Card-only (the floppy pack is full). */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG    0          /* blue sky */
#define WOOD  2          /* black trunk/branches */
#define LEAF  3          /* red blossoms */
#define HOLD  150         /* frames between re-growths */

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

/* Drawing primitive. CPC: Bresenham to the #C000 Mode-1 screen + a firmware
   SET-BORDER. MSX2: the V9938 hardware LINE command (GB_LINE #8009, as the clock
   uses); the tree works in the 320x200 space, so scale each endpoint to fill the
   512x212 Screen 6 (both 4:3, so proportions hold). MSX has no #BC38 SET-BORDER
   firmware, so that's a no-op there (like ANT). (#287) */
#ifdef GB_MSX2
#define GLINE_X0  (*(volatile unsigned int  *)0xC030)
#define GLINE_Y0  (*(volatile unsigned int  *)0xC032)
#define GLINE_X1  (*(volatile unsigned int  *)0xC034)
#define GLINE_Y1  (*(volatile unsigned int  *)0xC036)
#define GLINE_PEN (*(volatile unsigned char *)0xC038)
static void fw_line(void) __naked
{
__asm
    call 0x8009
    ret
__endasm;
}
static int sclx(int v) { v = v * 8 / 5;   return v < 0 ? 0 : v > GB_XPIX - 1  ? GB_XPIX - 1  : v; }
static int scly(int v) { v = v * 53 / 50; return v < 0 ? 0 : v > GB_LINES - 1 ? GB_LINES - 1 : v; }
static void draw_line(int x0, int y0, int x1, int y1, unsigned char ink)
{
    GLINE_X0 = (unsigned int)sclx(x0); GLINE_Y0 = (unsigned int)scly(y0);
    GLINE_X1 = (unsigned int)sclx(x1); GLINE_Y1 = (unsigned int)scly(y1);
    GLINE_PEN = ink; fw_line();
}
static void plot_dot(int x, int y, unsigned char ink) { draw_line(x, y, x, y, ink); }
static void set_border(void) { (void)brd_ink; }
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
static void plot_dot(int sx, int sy, unsigned char ink)
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
static void draw_line(int x0, int y0, int x1, int y1, unsigned char ink)
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
        plot_dot(x0, y0, ink);
        if (x0 == x1 && y0 == y1) break;
        e2 = err + err;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 <  dx) { err += dx; y0 += sy; }
    }
}
#endif

static void blossom(int x, int y)
{
    unsigned char k;
    for (k = 0; k < 5; k++) {
        int dx = (int)(rnd() % 9) - 4, dy = (int)(rnd() % 9) - 4;
        plot_dot(x + dx, y + dy, LEAF);
        plot_dot(x + dx + 1, y + dy, LEAF);
    }
}

/* grow one branch: a tapering stroke from (x,y) at angle `ang` (60ths), then recurse. */
static void branch(int x, int y, int ang, int len, int thick)
{
    int a = x - (len * SN(ang)) / 64;
    int b = y - (len * CS(ang)) / 64;
    int w, pdx = CS(ang), pdy = -SN(ang);          /* perpendicular for thickness */
    for (w = -(thick / 2); w <= thick / 2; w++)
        draw_line(x + (w * pdx) / 64, y + (w * pdy) / 64,
                  a + (w * pdx) / 64, b + (w * pdy) / 64, WOOD);
    if (thick > 2) {
        branch(a, b, (ang * 4) / 5 + (int)(rnd() % 3) - 1, (len * 2) / 3, (thick * 2) / 3);
        branch(a, b, ang + 2 + (int)(rnd() % 7),           (len * 2) / 3, (thick * 2) / 3);
        branch((a + x) / 2, (b + y) / 2,
               ang - 2 - (int)(rnd() % 7),                 (len * 2) / 3, (thick * 2) / 3);
    } else {
        blossom(a, b);
    }
}

static void grow_forest(void)
{
    branch(70,  195, 0,  34, 11);
    branch(160, 198, 0,  40, 13);
    branch(250, 195, 0,  34, 11);
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
    if (hold) { hold--; return; }
    ss_paint();
    grow_forest();
    hold = HOLD;
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0; hold = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x464Fu);
    if (!rng) rng = 0x464Fu;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    grow_forest();
    hold = HOLD;
    gb_wm_add(&sswin);
}
