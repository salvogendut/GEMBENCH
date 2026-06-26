/* catclock - a Kit-Cat-Klock screensaver for GEOBENCH (#219 family).
 *
 * Inspired by the classic X11 "catclock". The cat body (face, ears, bow tie and the
 * numbered clock dial) is a pre-drawn bitmap converted from assets/catclockbody.png by
 * tools/png2catclock.py into catimg.h (packed CPC Mode-1 bytes), blitted once straight
 * to the #C000 screen. Over it we animate only the moving parts: the pupils slide left
 * and right once per second (the "seconds"), and the hour/minute hands ("arms") point at
 * the real time from gb_time(). Card-only (the floppy pack is full). */
#include "gb.h"
#include "catimg.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG    0          /* blue background (matches the bitmap's own background) */
#define HAND  2          /* black hands */
#define PUP   2          /* black pupils */
#define PUPR  3          /* pupil radius */
#define PUPDX 4          /* how far pupils slide each way */

static const signed char sintab[60] = {
    0, 7, 13, 20, 26, 32, 38, 43, 48, 52, 55, 58, 61, 63, 64, 64, 64, 63, 61, 58,
    55, 52, 48, 43, 38, 32, 26, 20, 13, 7, 0, -7, -13, -20, -26, -32, -38, -43, -48, -52,
    -55, -58, -61, -63, -64, -64, -64, -63, -61, -58, -55, -52, -48, -43, -38, -32, -26, -20, -13, -7
};

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

static void fill_disc(int cx, int cy, int r, unsigned char ink)
{
    int x, y, rr = r * r;
    for (y = -r; y <= r; y++) {
        int yy = y * y;
        for (x = -r; x <= r; x++)
            if (x * x + yy <= rr) vram_pixel(cx + x, cy + y, ink);
    }
}

/* blit a byte-column / row sub-rectangle of the cat bitmap straight to #C000. */
static void blit(unsigned char c0, unsigned char c1, int r0, int r1)
{
    int y;
    unsigned char c;
    for (y = r0; y <= r1; y++) {
        const unsigned char *src = &cat_img[y * CAT_BPR];
        for (c = c0; c <= c1; c++) {
            unsigned char *d = (unsigned char *)(0xC000u + (unsigned int)(y >> 3) * 80u
                + (unsigned int)(y & 7) * 0x800u + (CAT_X0COL + c));
            *d = src[c];
        }
    }
}

static void hand(int pos, int len)
{
    int i = pos % 60;
    vram_line(CLK_CX, CLK_CY,
              CLK_CX + (len * sintab[i]) / 64,
              CLK_CY - (len * sintab[(i + 15) % 60]) / 64, HAND);
}

static void draw_hands(void)
{
    blit(DIAL_C0, DIAL_C1, DIAL_R0, DIAL_R1);                 /* restore clean dial + numbers */
    hand((gb_hour % 12) * 5 + gb_min / 12, CLK_R / 2);        /* hour ("arm") */
    hand(gb_min, (CLK_R * 8) / 10);                           /* minute ("arm") */
    fill_disc(CLK_CX, CLK_CY, 2, HAND);                       /* hub */
}

static void draw_pupils(signed char dx)
{
    blit(EYE_L_C0, EYE_R_C1, EYE_R0, EYE_R1);                 /* restore clean eyes */
    fill_disc(EYE_LX + dx, EYE_LY, PUPR, PUP);
    fill_disc(EYE_RX + dx, EYE_RY, PUPR, PUP);
}

static unsigned char last_sec = 0xFF, last_min = 0xFF;

static void ss_paint(void)
{
    gb_fill(0, 0, 80, 200, BG);
    blit(0, CAT_BPR - 1, 0, CAT_H - 1);     /* the cat body */
    last_sec = last_min = 0xFF;             /* force hands + pupils to draw */
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
    gb_time();
    if (gb_min != last_min) { draw_hands(); last_min = gb_min; }
    if (gb_sec != last_sec) {                                 /* pupils tick back and forth */
        draw_pupils((gb_sec & 1) ? PUPDX : -PUPDX);
        last_sec = gb_sec;
    }
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x4341u);
    if (!rng) rng = 0x4341u;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    draw_hands(); last_min = gb_min;
    draw_pupils(-PUPDX); last_sec = gb_sec;
    gb_wm_add(&sswin);
}
