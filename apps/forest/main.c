/* forest - fractal trees screensaver for GEOBENCH (#219 family).
 *
 * Ported from the xscreensaver forest hack. An explicit depth-first stack grows
 * tapering branches and angled side branches until the twigs end in blossoms.
 * The original uses double trig; here angles are integer 60ths-of-a-circle indexed
 * into a sin table. A fresh stand of trees is grown every few seconds. */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG    0          /* blue sky */
#define WOOD  2          /* black trunk/branches */
#define LEAF  3          /* red blossoms */
#define HOLD  150         /* frames between re-growths */
#define CLEAR_LINES_PER_FRAME 16
#define BRANCH_WORK_PER_FRAME 4
#define BRANCH_STACK_MAX      8

#define FOREST_CLEAR 0
#define FOREST_GROW  1
#define FOREST_HOLD  2

#ifdef GB_MSX2
#define MSX_SCRMOD (*(volatile unsigned char *)0xFCAF)
#define BLOSSOM_SET   0
#define BLOSSOM_TREE  1
#define BLOSSOM_MIXED 2
static unsigned char mode7;
static unsigned char blossom_mode, set_blossom_ink, tree_blossom_ink[3];
#endif

static const signed char sintab[60] = {
    0, 7, 13, 20, 26, 32, 38, 43, 48, 52, 55, 58, 61, 63, 64, 64, 64, 63, 61, 58,
    55, 52, 48, 43, 38, 32, 26, 20, 13, 7, 0, -7, -13, -20, -26, -32, -38, -43, -48, -52,
    -55, -58, -61, -63, -64, -64, -64, -63, -61, -58, -55, -52, -48, -43, -38, -32, -26, -20, -13, -7
};
#define SN(k) (sintab[(((k) % 60) + 60) % 60])
#define CS(k) (sintab[((((k) + 15) % 60) + 60) % 60])

static unsigned char lmx, lmy, armed, hold;
static unsigned int  rng;
static unsigned char forest_stage, clear_y, forest_tree, branch_top;
static int branch_x[BRANCH_STACK_MAX], branch_y[BRANCH_STACK_MAX];
static int branch_ang[BRANCH_STACK_MAX], branch_len[BRANCH_STACK_MAX];
static int branch_end_x[BRANCH_STACK_MAX], branch_end_y[BRANCH_STACK_MAX];
static unsigned char branch_thick[BRANCH_STACK_MAX], branch_phase[BRANCH_STACK_MAX];

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
static int nclampx(int v) { return v < 0 ? 0 : v > GB_XPIX - 1 ? GB_XPIX - 1 : v; }
static int nclampy(int v) { return v < 0 ? 0 : v > GB_LINES - 1 ? GB_LINES - 1 : v; }
static void draw_native_line(int x0, int y0, int x1, int y1, unsigned char ink)
{
    GLINE_X0 = (unsigned int)nclampx(x0); GLINE_Y0 = (unsigned int)nclampy(y0);
    GLINE_X1 = (unsigned int)nclampx(x1); GLINE_Y1 = (unsigned int)nclampy(y1);
    GLINE_PEN = ink; fw_line();
}
static void draw_line(int x0, int y0, int x1, int y1, unsigned char ink)
{
    draw_native_line(sclx(x0), scly(y0), sclx(x1), scly(y1), ink);
}
/* Adjacent source-space strokes spread apart when scaled from 320 to 512
   pixels. Step along the native-space normal instead, producing a solid band. */
static void draw_branch(int x0, int y0, int x1, int y1, int ang,
                        unsigned char thick)
{
    int nx0 = sclx(x0), ny0 = scly(y0), nx1 = sclx(x1), ny1 = scly(y1);
    int dx = nx1 - nx0, dy = ny1 - ny0;
    int adx = dx < 0 ? -dx : dx, ady = dy < 0 ? -dy : dy;
    int half = thick / 2, off, ox, oy;

    (void)ang;

    if (!adx && !ady) {
        draw_native_line(nx0, ny0, nx1, ny1, WOOD);
        return;
    }
    if (adx >= ady) {
        half = (half * 53 + 25) / 50;
        for (off = -half; off <= half; off++) {
            oy = off;
            ox = dx ? -(dy * off) / dx : 0;
            draw_native_line(nx0 + ox, ny0 + oy, nx1 + ox, ny1 + oy, WOOD);
        }
    } else {
        half = (half * 8 + 2) / 5;
        for (off = -half; off <= half; off++) {
            ox = off;
            oy = dy ? -(dx * off) / dy : 0;
            draw_native_line(nx0 + ox, ny0 + oy, nx1 + ox, ny1 + oy, WOOD);
        }
    }
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
static void draw_branch(int x0, int y0, int x1, int y1, int ang,
                        unsigned char thick)
{
    int w, pdx = CS(ang), pdy = -SN(ang);
    for (w = -(thick / 2); w <= thick / 2; w++)
        draw_line(x0 + (w * pdx) / 64, y0 + (w * pdy) / 64,
                  x1 + (w * pdx) / 64, y1 + (w * pdy) / 64, WOOD);
}
#endif

static unsigned char blossom_ink(void)
{
#ifdef GB_MSX2
    if (mode7) {
        if (blossom_mode == BLOSSOM_SET) return set_blossom_ink;
        if (blossom_mode == BLOSSOM_TREE) return tree_blossom_ink[forest_tree];
        return (unsigned char)(4 + rnd() % 12);
    }
#endif
    return LEAF;
}

static void blossom(int x, int y)
{
    unsigned char k, ink = blossom_ink();
    for (k = 0; k < 5; k++) {
        int dx = (int)(rnd() % 9) - 4, dy = (int)(rnd() % 9) - 4;
        plot_dot(x + dx, y + dy, ink);
        plot_dot(x + dx + 1, y + dy, ink);
    }
}

static void push_branch(int x, int y, int ang, int len, unsigned char thick)
{
    unsigned char i;
    if (branch_top >= BRANCH_STACK_MAX) return;
    i = branch_top++;
    branch_x[i] = x; branch_y[i] = y;
    branch_ang[i] = ang; branch_len[i] = len;
    branch_thick[i] = thick; branch_phase[i] = 0;
}

static void push_tree(void)
{
    if (forest_tree == 0) push_branch(70, 195, 0, 34, 11);
    else if (forest_tree == 1) push_branch(160, 198, 0, 40, 13);
    else push_branch(250, 195, 0, 34, 11);
}

/* One explicit recursion-frame transition. Child calls are pushed only when
   their parent reaches that phase, preserving the original depth-first RNG. */
static void branch_work(void)
{
    unsigned char i, thick;
    int x, y, ang, len, a, b;

    i = (unsigned char)(branch_top - 1);
    x = branch_x[i]; y = branch_y[i];
    ang = branch_ang[i]; len = branch_len[i];
    thick = branch_thick[i];

    if (branch_phase[i] == 0) {
        a = x - (len * SN(ang)) / 64;
        b = y - (len * CS(ang)) / 64;
        branch_end_x[i] = a; branch_end_y[i] = b;
        draw_branch(x, y, a, b, ang, thick);
        if (thick <= 2) {
            blossom(a, b);
            branch_top--;
            return;
        }
        branch_phase[i] = 1;
        push_branch(a, b, (ang * 4) / 5 + (int)(rnd() % 3) - 1,
                    (len * 2) / 3, (unsigned char)((thick * 2) / 3));
    } else if (branch_phase[i] == 1) {
        branch_phase[i] = 2;
        push_branch(branch_end_x[i], branch_end_y[i],
                    ang + 2 + (int)(rnd() % 7),
                    (len * 2) / 3, (unsigned char)((thick * 2) / 3));
    } else if (branch_phase[i] == 2) {
        branch_phase[i] = 3;
        push_branch((branch_end_x[i] + x) / 2, (branch_end_y[i] + y) / 2,
                    ang - 2 - (int)(rnd() % 7),
                    (len * 2) / 3, (unsigned char)((thick * 2) / 3));
    } else {
        branch_top--;
    }
}

static void begin_forest(void)
{
#ifdef GB_MSX2
    if (mode7) {
        blossom_mode = (unsigned char)(rnd() % 3);
        set_blossom_ink = (unsigned char)(4 + rnd() % 12);
        tree_blossom_ink[0] = (unsigned char)(4 + rnd() % 12);
        do {
            tree_blossom_ink[1] = (unsigned char)(4 + rnd() % 12);
        } while (tree_blossom_ink[1] == tree_blossom_ink[0]);
        do {
            tree_blossom_ink[2] = (unsigned char)(4 + rnd() % 12);
        } while (tree_blossom_ink[2] == tree_blossom_ink[0] ||
                 tree_blossom_ink[2] == tree_blossom_ink[1]);
    }
#endif
    forest_stage = FOREST_CLEAR;
    clear_y = 0;
    forest_tree = 0;
    branch_top = 0;
}

static void forest_tick(void)
{
    unsigned char n, rows;

    if (forest_stage == FOREST_CLEAR) {
        rows = CLEAR_LINES_PER_FRAME;
        if ((unsigned int)clear_y + rows > GB_LINES)
            rows = (unsigned char)(GB_LINES - clear_y);
        gb_fill(0, clear_y, GB_COLS, rows, BG);
        clear_y = (unsigned char)(clear_y + rows);
        if (clear_y >= GB_LINES) {
            forest_stage = FOREST_GROW;
            push_tree();
        }
        return;
    }

    if (forest_stage == FOREST_HOLD) {
        if (hold) hold--;
        else begin_forest();
        return;
    }

    for (n = 0; n < BRANCH_WORK_PER_FRAME; n++) {
        if (branch_top == 0) {
            if (++forest_tree < 3) push_tree();
            else {
                forest_stage = FOREST_HOLD;
                hold = HOLD;
                break;
            }
        }
        branch_work();
    }
}

static void ss_paint(void)
{
    begin_forest();
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
    forest_tick();
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0; hold = 0; forest_stage = FOREST_CLEAR;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x464Fu);
    if (!rng) rng = 0x464Fu;
#ifdef GB_MSX2
    mode7 = (MSX_SCRMOD == 7);
#endif

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
