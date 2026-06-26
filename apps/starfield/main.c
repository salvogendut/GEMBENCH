/* starfield - a 3D star-field screensaver for GEOBENCH (#219 family).
 *
 * Inspired by the SymbOS symsav-starfield (which is pure Z80 asm, Mode 0) - this is
 * a fresh, from-scratch implementation of the classic effect: stars fly toward the
 * viewer out of the centre, accelerating and fading from blue (far) through red to
 * white (near) until they pass the screen edge and respawn far away.
 *
 * Each star has a 3D position (x, y, z); each frame z shrinks (the star approaches)
 * and the point is perspective-projected sx = 160 + x*FOCAL/z, sy = 100 + y*FOCAL/z,
 * plotted as a single pixel straight to the #C000 Mode-1 screen (always mapped). No
 * lines, no IFS - just bounded integer division, so none of fractalic's pitfalls.
 * Small enough to ship on both the floppy and the card. */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230) /* desktop's configured border ink (INKS= 5th) */

#define NSTARS 64
#define ZMAX   255      /* spawn depth (far) */
#define ZMIN   2        /* respawn at/under this depth */
#define FOCAL  64       /* projection scale */
#define SPEED  4        /* depth shrink per frame */
#define BG     2        /* black background */

static int x[NSTARS], y[NSTARS], z[NSTARS];   /* 3D position */
static int px[NSTARS], py[NSTARS];            /* last plotted screen position (to erase) */

static unsigned char lmx, lmy, armed;
static unsigned int  rng;

/* SCR SET BORDER (&BC38): drive the CPC border to the hardware ink in brd_ink.
   Black (0) makes the border vanish into the star-field; on exit we restore the
   desktop's configured border so the screen looks untouched. */
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

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* plot one Mode-1 pixel straight into #C000 (clips off-screen). */
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

/* spawn star i far away with a random direction. */
static void spawn(unsigned char i)
{
    x[i] = (int)(rnd() & 255) - 128;
    y[i] = (int)(rnd() & 255) - 128;
    z[i] = ZMAX;
}

static void star_tick(void)
{
    unsigned char i, col;
    int sx, sy;
    for (i = 0; i < NSTARS; i++) {
        vram_pixel(px[i], py[i], BG);              /* erase the old position */
        z[i] -= SPEED;                             /* approach */
        if (z[i] <= ZMIN) spawn(i);
        sx = 160 + (x[i] * FOCAL) / z[i];          /* perspective projection */
        sy = 100 + (y[i] * FOCAL) / z[i];
        if (sx < 0 || sx >= 320 || sy < 0 || sy >= 200) { /* flew off the edge -> respawn */
            spawn(i);
            sx = 160 + (x[i] * FOCAL) / z[i];
            sy = 100 + (y[i] * FOCAL) / z[i];
        }
        col = (z[i] > 170) ? 0 : (z[i] > 85) ? 3 : 1;   /* blue far, red mid, white near */
        vram_pixel(sx, sy, col);
        px[i] = sx; py[i] = sy;
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
        brd_ink = KCFG_BORDER;        /* restore the desktop's border */
        set_border();
        WM_FS = 0;
        gb_wm_close();
        return;
    }
    star_tick();
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char i, n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x57A4u);
    if (!rng) rng = 0x57A4u;
    for (i = 0; i < NSTARS; i++) {                 /* random initial depths -> staggered */
        spawn(i);
        z[i] = (int)(ZMIN + 1 + rnd() % (ZMAX - ZMIN));
        px[i] = py[i] = -1;
    }
    WM_FS = 1;
    brd_ink = 0;                 /* black border -> continuous with the star-field */
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
