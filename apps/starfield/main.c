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
#include "gbcfg.h"
#include "gbsaver.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#ifdef GB_MSX2
#define KCFG_BORDER (*(volatile unsigned char *)0x122C) /* MSX: border==paper==palette[0] (INKS[0]) */
#else
#define KCFG_BORDER (*(volatile unsigned char *)0x1230) /* CPC: desktop's border ink (INKS= 5th) */
#endif

#define ZMAX   255      /* spawn depth (far) */
#define ZMIN   2        /* respawn at/under this depth */
#define FOCAL  64       /* projection scale */
#define BG     2        /* black background */
#define STAR_WORK_PER_FRAME 24

static int x[GB_STARFLD_STARS_MAX], y[GB_STARFLD_STARS_MAX], z[GB_STARFLD_STARS_MAX];
static int px[GB_STARFLD_STARS_MAX], py[GB_STARFLD_STARS_MAX];
static unsigned char star_count, star_speed, star_cursor, star_stride;

static unsigned char lmx, lmy, armed;
static unsigned int  rng;

/* SCR SET BORDER (&BC38): drive the CPC border to the hardware ink in brd_ink.
   Black (0) makes the border vanish into the star-field; on exit we restore the
   desktop's configured border so the screen looks untouched. */
static volatile unsigned char brd_ink;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* plot_dot: one star pixel. CPC writes the #C000 Mode-1 screen and drives the
   firmware SET-BORDER (&BC38). MSX2 has no memory-mapped screen or that firmware,
   so it plots via a zero-length GB_LINE (V9938 point) and skips the border; the
   320x200 star coords scale up to fill the 512x212 Screen 6. (#287) */
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
static void plot_dot(int sx, int sy, unsigned char ink)
{
    unsigned int mx = (unsigned int)sclx(sx), my = (unsigned int)scly(sy);
    GLINE_X0 = mx; GLINE_Y0 = my; GLINE_X1 = mx; GLINE_Y1 = my;
    GLINE_PEN = ink; fw_line();
}
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
#endif

/* spawn star i far away with a random direction. */
static void spawn(unsigned char i)
{
    x[i] = (int)(rnd() & 255) - 128;
    y[i] = (int)(rnd() & 255) - 128;
    z[i] = ZMAX;
}

static void star_tick(void)
{
    unsigned char i, col, work;
    int sx, sy;
    int delta = (int)star_speed * star_stride;

    work = STAR_WORK_PER_FRAME;
    while (work-- && star_cursor < star_count) {
        i = star_cursor++;
        plot_dot(px[i], py[i], BG);              /* erase the old position */
        z[i] -= delta;                            /* account for round-robin interval */
        if (z[i] <= ZMIN) spawn(i);
        sx = 160 + (x[i] * FOCAL) / z[i];          /* perspective projection */
        sy = 100 + (y[i] * FOCAL) / z[i];
        if (sx < 0 || sx >= 320 || sy < 0 || sy >= 200) { /* flew off the edge -> respawn */
            spawn(i);
            sx = 160 + (x[i] * FOCAL) / z[i];
            sy = 100 + (y[i] * FOCAL) / z[i];
        }
        col = (z[i] > 170) ? 0 : (z[i] > 85) ? 3 : 1;   /* blue far, red mid, white near */
        plot_dot(sx, sy, col);
        px[i] = sx; py[i] = sy;
    }
    if (star_cursor >= star_count) star_cursor = 0;
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
        brd_ink = KCFG_BORDER;        /* restore the desktop's border */
        set_border();
        WM_FS = 0;
        gb_wm_close();
        return;
    }
    star_tick();
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char i, n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    star_speed = gbcfg_u8(GB_STARFLD_SPEED_KEY, GB_STARFLD_SPEED_DEFAULT,
                          GB_STARFLD_SPEED_MIN, GB_STARFLD_SPEED_MAX);
    star_count = gbcfg_u8(GB_STARFLD_STARS_KEY, GB_STARFLD_STARS_DEFAULT,
                          GB_STARFLD_STARS_MIN, GB_STARFLD_STARS_MAX);
    star_cursor = 0;
    star_stride = (unsigned char)((star_count + STAR_WORK_PER_FRAME - 1) /
                                  STAR_WORK_PER_FRAME);
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x57A4u);
    if (!rng) rng = 0x57A4u;
    for (i = 0; i < star_count; i++) {              /* random initial depths -> staggered */
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
