/* truchet - Truchet-tile screensaver for GEOBENCH (#219 family).
 *
 * Ported from the xscreensaver truchet hack (its line "draw_angles" variant). Each cell
 * of a grid randomly picks one of two orientations and draws two edge-midpoint-to-edge-
 * midpoint segments; tiled across the screen the segments join into flowing maze-like
 * curves. A fresh random tiling is drawn every few seconds in a cycling pen. Pure
 * integer line drawing straight to #C000. Card-only (the floppy pack is full). */
#include "gb.h"
#include "../savdraw.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG   0          /* blue background (desktop-like) */
#define CW   20         /* cell width  */
#define CH   20         /* cell height */
#define COLS 16         /* 16*20 = 320 */
#define ROWS 10         /* 10*20 = 200 */
#define HOLD 150        /* frames between re-tilings */
#define TILES_PER_FRAME 8

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

static unsigned char pen, hold, tile_x, tile_y, drawing;
static const unsigned char pens[3] = { 1, 3, 1 };  /* white, red, white */
static unsigned char penix;

static void begin_tiling(void)
{
    pen = pens[penix]; penix = (penix + 1) % 3;
    tile_x = 0;
    tile_y = 0;
    drawing = 1;
}

static void draw_tiling_step(void)
{
    unsigned char n;
    int x0, y0;

    for (n = 0; n < TILES_PER_FRAME && drawing; n++) {
        x0 = tile_x * CW; y0 = tile_y * CH;
        if (rnd() & 1) {                 /* "\" tile */
            vram_line(x0 + CW/2, y0,        x0 + CW,   y0 + CH/2, pen);
            vram_line(x0,        y0 + CH/2, x0 + CW/2, y0 + CH,   pen);
        } else {                         /* "/" tile */
            vram_line(x0 + CW/2, y0,        x0,        y0 + CH/2, pen);
            vram_line(x0 + CW,   y0 + CH/2, x0 + CW/2, y0 + CH,   pen);
        }
        if (++tile_x == COLS) {
            tile_x = 0;
            if (++tile_y == ROWS) {
                drawing = 0;
                hold = HOLD;
            }
        }
    }
}

static void ss_paint(void)
{
    gb_fill(0, 0, GB_COLS, GB_LINES, BG);
    begin_tiling();
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
    if (drawing) { draw_tiling_step(); return; }
    if (hold) { hold--; return; }
    ss_paint();
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0; penix = 0; hold = 0; drawing = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x5452u);
    if (!rng) rng = 0x5452u;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
