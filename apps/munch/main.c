/* munch - "munching squares" screensaver for GEOBENCH (#219 family).
 *
 * Ported from the xscreensaver munch hack (Jackson Wright's classic PDP-1 display
 * program, 1962). The recurrence  y = (x XOR ((t+kT) mod W) + kY) mod W  sweeps a
 * moving moire of triangles across a W-wide power-of-two square; once a square fills
 * over W frames a fresh one starts elsewhere in a new pen. Pure integer XOR + mod,
 * plotted straight to the #C000 Mode-1 screen. Card-only (the floppy pack is full). */
#include "gb.h"
#include "../savdraw.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG  2          /* black background (classic munch screen) */

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
#endif

/* current muncher */
static unsigned char mW, mask, t, kX, kT, kY, grav, pen, atY;
static unsigned int  atX;            /* 4-aligned left edge */
static const unsigned char pens[3] = { 1, 3, 1 };  /* white, red, white */
static unsigned char penix;

static void new_square(void)
{
    mW   = (unsigned char)(32u << (rnd() & 1));      /* 32 or 64 wide */
    mask = mW - 1;
    atX  = (unsigned int)((rnd() % (320 - mW)) & ~3);
    atY  = (unsigned char)(rnd() % (200 - mW));
    kX   = (rnd() & 1) ? (unsigned char)(rnd() & mask) : 0;
    kT   = (rnd() & 1) ? (unsigned char)(rnd() & mask) : 0;
    kY   = (rnd() & 1) ? (unsigned char)(rnd() & mask) : 0;
    grav = (unsigned char)(rnd() & 1);
    pen  = pens[penix]; penix = (penix + 1) % 3;
    t    = 0;
    gb_fill((unsigned char)(atX >> 2), atY, (unsigned char)(mW >> 2), mW, BG);  /* clear region */
}

static void munch_tick(void)
{
    unsigned char x, y, dy;
    unsigned int dx;
    for (x = 0; x < mW; x++) {
        y  = (unsigned char)(((x ^ ((t + kT) & mask)) + kY) & mask);
        dx = atX + ((x + kX) & mask);
        dy = grav ? (unsigned char)(atY + y) : (unsigned char)(atY + mask - y);
        vram_pixel((int)dx, (int)dy, pen);
    }
    if (++t > mask) new_square();
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
    munch_tick();
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0; penix = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x4D55u);
    if (!rng) rng = 0x4D55u;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    new_square();
    gb_wm_add(&sswin);
}
