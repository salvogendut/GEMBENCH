/* mountain - a 3D isometric terrain screensaver for GEOBENCH (#219 family).
 *
 * Ported from the SymbOS symsav-mountain screensaver (itself after Pascal Pensa's
 * xlockmore "mountain", 1995). A 20x20 height map is seeded with random peaks,
 * smoothed, then drawn cell by cell as an isometric grid: each cell is a filled
 * quad (red = higher ground, black = valleys) outlined in a white wireframe, on
 * the blue sky. Cells are drawn back-to-front so near terrain occludes far. Holds
 * the finished landscape, then regenerates.
 *
 * The original is already CPC Mode 1 (4 colours) and plots single pixels straight
 * to the #C000 screen. GEOBENCH's screen is the same standard #C000 layout and is
 * always mapped (not banked), so we write it directly - no kernel pixel primitive
 * and none of the SymbOS Bank_Copy / shadow-buffer dance is needed. The SymbOS
 * config dialog + message protocol are dropped; this is just a fullscreen window
 * that animates and closes on input, like the other .SAV savers. */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)

#define WW       20      /* terrain grid is WW x WW */
#define MAXH     220     /* initial random peak height */
#define TH_MID   25      /* avg height >= this -> red fill, else black */
#define YOFF     70      /* vertical screen offset of the grid */
#define PAUSE    120     /* frames the finished landscape is held */
#define NPEAKS   8       /* random peaks seeded into the terrain */
#define CELLS    6       /* grid cells drawn per frame */

/* GEOBENCH pens: 0 blue, 1 white, 2 black, 3 red. */
#define COL_BG      0    /* blue sky (background) */
#define COL_WIRE    1    /* white wireframe edges */
#define COL_FILL_HI 3    /* red - higher ground */
#define COL_FILL_LO 2    /* black - valleys */

static int h[WW][WW];                 /* height map */
static int draw_x, draw_y;
static unsigned char anim_stage;      /* 0 = drawing, 1 = pause, 2 = regen */
static int stage_timer;
static unsigned char lmx, lmy, armed;
static unsigned int  rng;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* vram_pixel: plot one Mode-1 pixel straight into the #C000 screen.
   addr = #C000 + (y>>3)*80 + (y&7)*#800 + (x>>2); pen bits 0x80>>pos / 0x08>>pos. */
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

static void vram_line(int x0, int y0, int x1, int y1, unsigned char ink)
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
    int ymin, ymax, y, x, xl, xr;
    ymin = y0; if (y1 < ymin) ymin = y1; if (y2 < ymin) ymin = y2; if (y3 < ymin) ymin = y3;
    ymax = y0; if (y1 > ymax) ymax = y1; if (y2 > ymax) ymax = y2; if (y3 > ymax) ymax = y3;
    if (ymin < 0) ymin = 0;
    if (ymax > 199) ymax = 199;
    for (y = ymin; y <= ymax; y++) {
        xl = 9999; xr = -9999;
        edge_x(x0, y0, x1, y1, y, &xl, &xr);
        edge_x(x1, y1, x2, y2, y, &xl, &xr);
        edge_x(x2, y2, x3, y3, y, &xl, &xr);
        edge_x(x3, y3, x0, y0, y, &xl, &xr);
        for (x = xl; x <= xr; x++) vram_pixel(x, y, ink);
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

static void init_terrain(void)
{
    int x, y, i, noise;
    for (y = 0; y < WW; y++) for (x = 0; x < WW; x++) h[x][y] = 0;
    for (i = 0; i < NPEAKS; i++) {
        x = 1 + (int)(rnd() % (WW - 2));
        y = 1 + (int)(rnd() % (WW - 2));
        h[x][y] = MAXH / 4 + (int)(rnd() % (MAXH * 3 / 4));
    }
    for (y = 0; y < WW; y++) for (x = 0; x < WW; x++) if (h[x][y] > 0) spread(x, y);
    for (y = 0; y < WW; y++) for (x = 0; x < WW; x++) if (h[x][y] > 0) spread(x, y);
    for (y = 0; y < WW; y++)
        for (x = 0; x < WW; x++) {
            noise = (int)(rnd() % 11) - 5;
            h[x][y] += noise;
            if (h[x][y] < 0) h[x][y] = 0;
        }
}

/* isometric projection (screen 320x200): same formula as the original. */
static int proj_sx(int gx, int gy) { return (gx * 640 / 60) - (gy * 400 / 60) / 2 + 80; }
static int proj_sy(int gy, int hv) { return (gy * 400 / 60) - hv + YOFF; }

static void draw_terrain_cell(int cx, int cy)
{
    int x0, y0, x1, y1, x2, y2, x3, y3, avg;
    unsigned char fill;
    x0 = proj_sx(cx,     cy);     y0 = proj_sy(cy,     h[cx][cy]);
    x1 = proj_sx(cx + 1, cy);     y1 = proj_sy(cy,     h[cx + 1][cy]);
    x2 = proj_sx(cx + 1, cy + 1); y2 = proj_sy(cy + 1, h[cx + 1][cy + 1]);
    x3 = proj_sx(cx,     cy + 1); y3 = proj_sy(cy + 1, h[cx][cy + 1]);
    avg = (h[cx][cy] + h[cx + 1][cy] + h[cx][cy + 1] + h[cx + 1][cy + 1]) / 4;
    fill = (avg >= TH_MID) ? COL_FILL_HI : COL_FILL_LO;
    fill_quad(x0, y0, x1, y1, x2, y2, x3, y3, fill);     /* red/black fill ... */
    vram_line(x0, y0, x1, y1, COL_WIRE);                 /* ... white wireframe edges */
    vram_line(x1, y1, x2, y2, COL_WIRE);
    vram_line(x2, y2, x3, y3, COL_WIRE);
    vram_line(x3, y3, x0, y0, COL_WIRE);
}

static void anim_tick(void)
{
    unsigned char n;
    if (anim_stage == 0) {                  /* draw the grid, CELLS cells per frame */
        for (n = 0; n < CELLS; n++) {
            if (draw_x >= WW - 1) { draw_x = 0; draw_y++; }
            if (draw_y >= WW - 1) { anim_stage = 1; stage_timer = PAUSE; break; }
            draw_terrain_cell(draw_x, draw_y);
            draw_x++;
        }
    } else if (anim_stage == 1) {           /* hold the finished landscape */
        if (--stage_timer <= 0) anim_stage = 2;
    } else {                                /* regenerate */
        gb_fill(0, 0, 80, 200, COL_BG);
        init_terrain();
        draw_x = 0; draw_y = 0; anim_stage = 0;
    }
}

static void ss_paint(void)
{
    gb_fill(0, 0, 80, 200, COL_BG);         /* blue sky */
    draw_x = 0; draw_y = 0; anim_stage = 0;
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
        WM_FS = 0;
        gb_wm_close();
        return;
    }
    anim_tick();
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x3217u);
    if (!rng) rng = 0x3217u;
    init_terrain();
    WM_FS = 1;
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
