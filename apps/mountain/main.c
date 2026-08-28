/* mountain - a 3D isometric terrain screensaver for GEOBENCH (#219/#446).
 *
 * Ported from the SymbOS symsav-mountain screensaver (itself after Pascal Pensa's
 * xlockmore "mountain", 1995). A 20x20 height map is seeded with random peaks,
 * smoothed, then drawn cell by cell as an isometric grid. MSX Screen 7 maps the
 * average cell height through eight stable palette entries; four-colour targets
 * keep a compact low/high treatment. Cells are drawn back-to-front so near
 * terrain occludes far. The finished landscape is held, then regenerated.
 *
 * CPC writes its native Mode-1 framebuffer directly; MSX and PCW use the shared
 * line primitive. The configuration UI is supplied by the same-stem
 * MOUNTAIN.MOD companion, keeping saver-specific controls out of Settings. */
#include "gb.h"
#include "gbcfg.h"
#include "gbsaver.h"

#define WM_FS (*(volatile unsigned char *)0x130A)

#define WW       20      /* terrain grid is WW x WW */
#define MAXH     220     /* initial random peak height */
#define TH_MID   25      /* avg height >= this -> red fill, else black */
#define YOFF     70      /* vertical screen offset of the grid */

#define CELLS_SLOW    1
#define CELLS_NORMAL  3
#define CELLS_FAST    7

#define CLEAR_LINES_PER_FRAME 32
#define MAP_CELLS_PER_FRAME   40
#define PEAKS_PER_FRAME        4

#define ST_CLEAR    0
#define ST_ZERO     1
#define ST_PEAKS    2
#define ST_SPREAD1  3
#define ST_SPREAD2  4
#define ST_NOISE    5
#define ST_DRAW     6
#define ST_HOLD     7

/* Logical pens 0..3 follow each target's configured base palette. Screen 7 can
 * also address the fixed extended palette at indices 4..15. */
#define COL_BG_4      0
#define COL_WIRE_4    1
#define COL_FILL_HI   3
#define COL_FILL_LO   2
#ifdef GB_MSX2
#define COL_BLACK     0       /* GEMBENCH MSX2 canvas */
#else
#define COL_BLACK     2       /* inherited target palette */
#endif
#define COL_WHITE     1

#ifdef GB_MSX2
#define MSX_SCRMOD (*(volatile unsigned char *)0xFCAF)
#define KCFG_INKS ((volatile unsigned char *)0x122C)
#elif !defined(GB_PCW)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])
#endif

static int h[WW][WW];                 /* height map */
static int draw_x, draw_y;
static unsigned char anim_stage;
static int stage_timer;
static unsigned char gen_x, gen_y, peak_index, clear_y;
static unsigned char lmx, lmy, armed;
static unsigned char mountain_peaks, mountain_hold, cells_per_frame;
#ifdef GB_MSX2
static unsigned char mode7, saved_paper_ink, saved_text_ink, saved_edge_ink;
#endif
static unsigned int  rng;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* Line/span primitive. CPC writes the #C000 Mode-1 screen. MSX uses the V9938
 * LINE command and PCW uses the kernel's slot-3 Bresenham path. A filled span
 * is one horizontal line, avoiding per-pixel calls on those targets. */
#if defined(GB_MSX2) || defined(GB_PCW)
#ifdef GB_MSX2
#define GLINE_X0  (*(volatile unsigned int  *)0xC030)
#define GLINE_Y0  (*(volatile unsigned int  *)0xC032)
#define GLINE_X1  (*(volatile unsigned int  *)0xC034)
#define GLINE_Y1  (*(volatile unsigned int  *)0xC036)
#define GLINE_PEN (*(volatile unsigned char *)0xC038)
#else
#define GLINE_X0  (*(volatile unsigned int  *)0x0F10)
#define GLINE_Y0  (*(volatile unsigned int  *)0x0F12)
#define GLINE_X1  (*(volatile unsigned int  *)0x0F14)
#define GLINE_Y1  (*(volatile unsigned int  *)0x0F16)
#define GLINE_PEN (*(volatile unsigned char *)0x0F18)
#endif
static void fw_line(void) __naked
{
__asm
    call 0x8009
    ret
__endasm;
}
static int clampx(int v) { return v < 0 ? 0 : v > GB_XPIX - 1 ? GB_XPIX - 1 : v; }
static int clampy(int v) { return v < 0 ? 0 : v > GB_LINES - 1 ? GB_LINES - 1 : v; }
static void draw_line(int x0, int y0, int x1, int y1, unsigned char ink)
{
    GLINE_X0 = (unsigned int)clampx(x0); GLINE_Y0 = (unsigned int)clampy(y0);
    GLINE_X1 = (unsigned int)clampx(x1); GLINE_Y1 = (unsigned int)clampy(y1);
    GLINE_PEN = ink; fw_line();
}
#define plot_span(xl, xr, y, ink) draw_line((xl), (y), (xr), (y), (ink))
#else
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
static void draw_line(int x0, int y0, int x1, int y1, unsigned char ink)
{
    int dx, dy, sx, sy, err, e2;
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
#define plot_span(xl, xr, y, ink) do { int _x; for (_x = (xl); _x <= (xr); _x++) vram_pixel(_x, (y), (ink)); } while (0)
#endif

#ifdef GB_MSX2
static volatile unsigned char pal_pen, pal_ink;

static void pal_set_call(void) __naked
{
__asm
    ld   a,(_pal_ink)
    ld   b,a
    ld   a,(_pal_pen)
    call 0x8006
    ret
__endasm;
}

static void set_ink(unsigned char pen, unsigned char ink)
{
    pal_pen = pen;
    pal_ink = ink;
    pal_set_call();
}

static void mountain_palette(void)
{
    saved_paper_ink = KCFG_INKS[0];
    if (mode7) {
        saved_text_ink = KCFG_INKS[1];
        saved_edge_ink = KCFG_INKS[2];
        set_ink(COL_WHITE, 26);
        set_ink(COL_BLACK, 0);
    }
    set_ink(0, 0);
}

static void restore_palette(void)
{
    if (mode7) {
        set_ink(COL_WHITE, saved_text_ink);
        set_ink(COL_BLACK, saved_edge_ink);
    }
    set_ink(0, saved_paper_ink);
}
#elif defined(GB_PCW)
static void mountain_palette(void) { }
static void restore_palette(void) { }
#else
static volatile unsigned char border_ink;

static void set_border(void) __naked
{
__asm
    ld   a,(_border_ink)
    ld   b,a
    ld   c,a
    call 0xBC38
    ret
__endasm;
}

static void mountain_palette(void)
{
    border_ink = KCFG_INK(COL_BG_4);
    set_border();
}

static void restore_palette(void)
{
    border_ink = KCFG_BORDER;
    set_border();
}
#endif

/* Screen 7 mirrors the original xlockmore c/10 height selection, but uses a
 * fixed low-to-high ramp rather than rotating the palette each landscape. */
static unsigned char terrain_fill(int avg)
{
#ifdef GB_MSX2
    if (mode7) {
        if (avg < 10) return 4;   /* green */
        if (avg < 20) return 12;  /* yellow-green */
        if (avg < 30) return 15;  /* pale green */
        if (avg < 40) return 6;   /* yellow */
        if (avg < 50) return 9;   /* orange */
        if (avg < 60) return 10;  /* light red */
        if (avg < 70) return 14;  /* rock grey */
        return COL_WHITE;         /* snow */
    }
#endif
#ifdef GB_PCW
    return (avg >= TH_MID) ? COL_FILL_HI : COL_BG_4;
#else
    return (avg >= TH_MID) ? COL_FILL_HI : COL_FILL_LO;
#endif
}

static unsigned char terrain_bg(void)
{
#if defined(GB_PCW)
    return COL_BLACK;
#elif defined(GB_MSX2)
    return mode7 ? COL_BLACK : COL_BG_4;
#else
    return COL_BG_4;
#endif
}

static unsigned char terrain_wire(void)
{
#ifdef GB_MSX2
    if (mode7) return COL_BLACK;
#endif
    return COL_WIRE_4;
}

/* edge_x: if edge (ax,ay)-(bx,by) crosses scanline y (half-open [ay,by)), widen
   the [*xl,*xr] span by the crossing x. */
static void edge_x(int ax, int ay, int bx, int by, int y, int *xl, int *xr)
{
    int x;
    if ((ay <= y && by > y) || (by <= y && ay > y)) {
        x = ax + (bx - ax) * (y - ay) / (by - ay);
        if (x < *xl) *xl = x;
        if (x > *xr) *xr = x;
    }
}

/* fill_quad: solid-fill the convex quad P0..P3 by scanlines. */
static void fill_quad(int x0, int y0, int x1, int y1, int x2, int y2,
                      int x3, int y3, unsigned char ink)
{
    int ymin, ymax, y, xl, xr;
    ymin = y0; if (y1 < ymin) ymin = y1; if (y2 < ymin) ymin = y2; if (y3 < ymin) ymin = y3;
    ymax = y0; if (y1 > ymax) ymax = y1; if (y2 > ymax) ymax = y2; if (y3 > ymax) ymax = y3;
    if (ymin < 0) ymin = 0;
    if (ymax > GB_LINES - 1) ymax = GB_LINES - 1;
    for (y = ymin; y <= ymax; y++) {
        xl = 9999; xr = -9999;
        edge_x(x0, y0, x1, y1, y, &xl, &xr);
        edge_x(x1, y1, x2, y2, y, &xl, &xr);
        edge_x(x2, y2, x3, y3, y, &xl, &xr);
        edge_x(x3, y3, x0, y0, y, &xl, &xr);
        if (xr >= xl) plot_span(xl, xr, y, ink);
    }
}

/* spread: average one cell into its 3x3 neighbourhood (terrain smoothing). */
static void spread(int x, int y)
{
    int x2, y2, hv = h[x][y];
    for (y2 = y - 1; y2 <= y + 1; y2++)
        for (x2 = x - 1; x2 <= x + 1; x2++)
            if (x2 >= 0 && y2 >= 0 && x2 < WW && y2 < WW)
                h[x2][y2] = (h[x2][y2] + hv) / 2;
}

/* Isometric projection: preserve the original 320x200 formula, then scale to
 * the target framebuffer. CPC remains byte-for-byte in the original space. */
#ifdef GB_MSX2
static int proj_sx(int gx, int gy) { return ((gx * 640 / 60) - (gy * 400 / 60) / 2 + 80) * 8 / 5; }
static int proj_sy(int gy, int hv) { return ((gy * 400 / 60) - hv + YOFF) * 53 / 50; }
#elif defined(GB_PCW)
static int proj_sx(int gx, int gy) { return ((gx * 640 / 60) - (gy * 400 / 60) / 2 + 80) * 9 / 8; }
static int proj_sy(int gy, int hv) { return ((gy * 400 / 60) - hv + YOFF) * 31 / 25; }
#else
static int proj_sx(int gx, int gy) { return (gx * 640 / 60) - (gy * 400 / 60) / 2 + 80; }
static int proj_sy(int gy, int hv) { return (gy * 400 / 60) - hv + YOFF; }
#endif

static void draw_terrain_cell(int cx, int cy)
{
    int x0, y0, x1, y1, x2, y2, x3, y3, avg;
    unsigned char fill, wire;
    x0 = proj_sx(cx,     cy);     y0 = proj_sy(cy,     h[cx][cy]);
    x1 = proj_sx(cx + 1, cy);     y1 = proj_sy(cy,     h[cx + 1][cy]);
    x2 = proj_sx(cx + 1, cy + 1); y2 = proj_sy(cy + 1, h[cx + 1][cy + 1]);
    x3 = proj_sx(cx,     cy + 1); y3 = proj_sy(cy + 1, h[cx][cy + 1]);
    avg = (h[cx][cy] + h[cx + 1][cy] + h[cx][cy + 1] + h[cx + 1][cy + 1]) / 4;
    fill = terrain_fill(avg);
    wire = terrain_wire();
    fill_quad(x0, y0, x1, y1, x2, y2, x3, y3, fill);
    draw_line(x0, y0, x1, y1, wire);
    draw_line(x1, y1, x2, y2, wire);
    draw_line(x2, y2, x3, y3, wire);
    draw_line(x3, y3, x0, y0, wire);
}

static unsigned char next_map_cell(void)
{
    if (++gen_x == WW) {
        gen_x = 0;
        if (++gen_y == WW) return 1;
    }
    return 0;
}

static void begin_terrain(void)
{
    anim_stage = ST_CLEAR;
    clear_y = 0;
    gen_x = gen_y = peak_index = 0;
    draw_x = draw_y = 0;
}

static void anim_tick(void)
{
    unsigned char n, rows;
    int x, y, noise;

    if (anim_stage == ST_CLEAR) {
        rows = CLEAR_LINES_PER_FRAME;
        if ((unsigned int)clear_y + rows > GB_LINES)
            rows = (unsigned char)(GB_LINES - clear_y);
        gb_fill(0, clear_y, GB_COLS, rows, terrain_bg());
        clear_y = (unsigned char)(clear_y + rows);
        if (clear_y >= GB_LINES) {
            gen_x = gen_y = 0;
            anim_stage = ST_ZERO;
        }
    } else if (anim_stage == ST_ZERO) {
        for (n = 0; n < MAP_CELLS_PER_FRAME; n++) {
            h[gen_x][gen_y] = 0;
            if (next_map_cell()) {
                peak_index = 0;
                anim_stage = ST_PEAKS;
                break;
            }
        }
    } else if (anim_stage == ST_PEAKS) {
        for (n = 0; n < PEAKS_PER_FRAME && peak_index < mountain_peaks; n++, peak_index++) {
            x = 1 + (int)(rnd() % (WW - 2));
            y = 1 + (int)(rnd() % (WW - 2));
            h[x][y] = MAXH / 4 + (int)(rnd() % (MAXH * 3 / 4));
        }
        if (peak_index == mountain_peaks) {
            gen_x = gen_y = 0;
            anim_stage = ST_SPREAD1;
        }
    } else if (anim_stage == ST_SPREAD1 || anim_stage == ST_SPREAD2) {
        for (n = 0; n < MAP_CELLS_PER_FRAME; n++) {
            if (h[gen_x][gen_y] > 0) spread(gen_x, gen_y);
            if (next_map_cell()) {
                gen_x = gen_y = 0;
                anim_stage = anim_stage == ST_SPREAD1 ? ST_SPREAD2 : ST_NOISE;
                break;
            }
        }
    } else if (anim_stage == ST_NOISE) {
        for (n = 0; n < MAP_CELLS_PER_FRAME; n++) {
            noise = (int)(rnd() % 11) - 5;
            h[gen_x][gen_y] += noise;
            if (h[gen_x][gen_y] < 0) h[gen_x][gen_y] = 0;
            if (next_map_cell()) {
                draw_x = draw_y = 0;
                anim_stage = ST_DRAW;
                break;
            }
        }
    } else if (anim_stage == ST_DRAW) {
        for (n = 0; n < cells_per_frame; n++) {
            if (draw_x >= WW - 1) { draw_x = 0; draw_y++; }
            if (draw_y >= WW - 1) {
                anim_stage = ST_HOLD;
                stage_timer = mountain_hold;
                break;
            }
            draw_terrain_cell(draw_x, draw_y);
            draw_x++;
        }
    } else if (anim_stage == ST_HOLD) {
        if (stage_timer > 0) stage_timer--;
        else begin_terrain();
    } else {
        begin_terrain();
    }
}

static void ss_paint(void)
{
    begin_terrain();
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
        restore_palette();
        WM_FS = 0;
        gb_wm_close();
        return;
    }
    anim_tick();
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n, speed;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
#ifdef GB_MSX2
    mode7 = (MSX_SCRMOD == 7);
#endif
    speed = gbcfg_u8(GB_MOUNTAIN_SPEED_KEY, GB_MOUNTAIN_SPEED_DEFAULT,
                     GB_MOUNTAIN_SPEED_MIN, GB_MOUNTAIN_SPEED_MAX);
    mountain_peaks = gbcfg_u8(GB_MOUNTAIN_PEAKS_KEY,
                              GB_MOUNTAIN_PEAKS_DEFAULT,
                              GB_MOUNTAIN_PEAKS_MIN,
                              GB_MOUNTAIN_PEAKS_MAX);
    mountain_hold = gbcfg_u8(GB_MOUNTAIN_HOLD_KEY,
                             GB_MOUNTAIN_HOLD_DEFAULT,
                             GB_MOUNTAIN_HOLD_MIN,
                             GB_MOUNTAIN_HOLD_MAX);
    cells_per_frame = speed == 1 ? CELLS_SLOW :
                      speed == 3 ? CELLS_FAST : CELLS_NORMAL;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x3217u);
    if (!rng) rng = 0x3217u;
    mountain_palette();
    WM_FS = 1;
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
