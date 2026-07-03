/* pyro - fireworks screensaver for GEOBENCH (#219 family).
 *
 * Ported from the xscreensaver pyro hack. Rockets launch from the bottom of the screen,
 * coast upward under gravity using 1/64-pixel fixed-point motion, and when their fuse
 * burns out they burst into a shower of shrapnel that arcs and fades. All integer/fixed-
 * point - no float - plotted straight to the #C000 Mode-1 screen on a black night sky.
 * Card-only (the floppy pack is full). */
#include "gb.h"
#include "../savdraw.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG     2          /* black night sky */
#define NPART  120
#define GRAV   5           /* downward accel per frame (fixed <<6) */
#define FP     6           /* fixed-point shift */

static const signed char sintab[60] = {
    0, 7, 13, 20, 26, 32, 38, 43, 48, 52, 55, 58, 61, 63, 64, 64, 64, 63, 61, 58,
    55, 52, 48, 43, 38, 32, 26, 20, 13, 7, 0, -7, -13, -20, -26, -32, -38, -43, -48, -52,
    -55, -58, -61, -63, -64, -64, -64, -63, -61, -58, -55, -52, -48, -43, -38, -32, -26, -20, -13, -7
};
#define SN(k) (sintab[(((k) % 60) + 60) % 60])
#define CS(k) (sintab[((((k) + 15) % 60) + 60) % 60])

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

typedef struct {
    int x, y, dx, dy;          /* fixed-point <<FP */
    int ox, oy;                /* last plotted pixel (to erase) */
    unsigned char life;        /* frames left (0 = dead) */
    unsigned char primary;     /* 1 = rocket (fuse), 0 = shrapnel */
    unsigned char pen;
} Part;

static Part part[NPART];

static unsigned char find_dead(void)
{
    unsigned char i;
    for (i = 0; i < NPART; i++) if (!part[i].life) return i;
    return 0xFF;
}

static void launch(void)
{
    unsigned char i = find_dead();
    Part *p;
    if (i == 0xFF) return;
    p = &part[i];
    p->x = (int)(40 + rnd() % 240) << FP;
    p->y = 199 << FP;
    p->dx = (int)(rnd() % 129) - 64;          /* slight drift */
    p->dy = -(int)(180 + rnd() % 80);         /* upward */
    p->ox = p->x >> FP; p->oy = p->y >> FP;
    p->life = (unsigned char)(34 + rnd() % 22);  /* fuse */
    p->primary = 1;
    p->pen = 1;                               /* white rocket */
}

static void burst(int x, int y)
{
    unsigned char k, i, pen = (rnd() & 1) ? 3 : 1;   /* red or white shower */
    for (k = 0; k < 18; k++) {
        int dir, spd;
        Part *p;
        i = find_dead();
        if (i == 0xFF) return;
        p = &part[i];
        dir = (int)(rnd() % 60);
        spd = (int)(48 + rnd() % 96);
        p->x = x; p->y = y;
        p->dx = (spd * SN(dir)) / 64;
        p->dy = (spd * CS(dir)) / 64;
        p->ox = x >> FP; p->oy = y >> FP;
        p->life = (unsigned char)(18 + rnd() % 18);
        p->primary = 0;
        p->pen = pen;
    }
}

static void step(void)
{
    unsigned char i;
    for (i = 0; i < NPART; i++) {
        Part *p = &part[i];
        int nx, ny;
        if (!p->life) continue;
        if (p->ox >= 0) vram_pixel(p->ox, p->oy, BG);       /* erase */
        p->dy += GRAV;
        p->x += p->dx; p->y += p->dy;
        nx = p->x >> FP; ny = p->y >> FP;
        p->life--;
        if (p->primary && p->life == 0) { burst(p->x, p->y); p->ox = -1; continue; }
        if (!p->life || nx < 0 || nx >= 320 || ny < 0 || ny >= 200) { p->ox = -1; continue; }
        vram_pixel(nx, ny, p->pen);
        p->ox = nx; p->oy = ny;
    }
    if ((rnd() % 7) == 0) launch();
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
    step();
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x5059u);
    if (!rng) rng = 0x5059u;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
