/* rorschach - symmetric ink-blot screensaver for GEOBENCH (#219 family).
 *
 * Ported from the xscreensaver rorschach hack. A random walk wanders from screen
 * centre; each plotted point is mirrored across both axes (4-fold symmetry) to grow a
 * symmetric ink-blot. After ~3000 points the blot is held, then erased and a fresh one
 * starts in a new pen. Pure integer single-pixel plotting straight to #C000. Card-only
 * (the floppy pack is full). */
#include "gb.h"
#include "../savdraw.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG       0          /* blue background */
#define OFFSET   3          /* random-walk step radius */
#define BLOTPTS  3000       /* points per blot */
#define HOLD     90         /* frames to admire a finished blot */
#define PERFRAME 60         /* walk steps per frame */

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

static int cx, cy;                   /* current walk position */
static unsigned int left;            /* points remaining this blot */
static unsigned char pen, hold;
static const unsigned char pens[3] = { 2, 3, 1 };  /* black, red, white */
static unsigned char penix;

static void new_blot(void)
{
    cx = 160; cy = 100;
    left = BLOTPTS;
    pen = pens[penix]; penix = (penix + 1) % 3;
}

static void blot_step(void)
{
    unsigned char i;
    for (i = 0; i < PERFRAME && left; i++, left--) {
        cx += (int)(rnd() % (1 + (OFFSET << 1))) - OFFSET;
        cy += (int)(rnd() % (1 + (OFFSET << 1))) - OFFSET;
        vram_pixel(cx, cy, pen);            /* 4-fold symmetry -> ink-blot */
        vram_pixel(319 - cx, cy, pen);
        vram_pixel(cx, 199 - cy, pen);
        vram_pixel(319 - cx, 199 - cy, pen);
    }
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
    if (left) {
        blot_step();
    } else if (hold) {
        hold--;
    } else {
        ss_paint();
        new_blot();
        hold = HOLD;
    }
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0; penix = 0; hold = HOLD;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x524Fu);
    if (!rng) rng = 0x524Fu;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    new_blot();
    gb_wm_add(&sswin);
}
