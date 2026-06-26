/* xroach - a cockroach screensaver for GEOBENCH (#219 family).
 *
 * Ported from the SymbOS symsav-xroach (itself inspired by J.T. Anderson's 1991 Unix
 * xroach): a pack of 16x16 cockroaches scuttle around the screen, bounce off the edges,
 * change heading at random, and scatter from a lone "odd roach" that wanders among them.
 *
 * The visual core carries over verbatim - the sprites are 16x16 Mode-1 bitmaps built
 * from ASCII art and blitted straight to the #C000 screen (always mapped), exactly the
 * technique mountain/starfield use. All the motion is bounded integer math (coords stay
 * in 0..320 / 0..200), so there is none of fractalic's 16-bit-overflow risk. The SymbOS
 * config dialog and screensaver message protocol are dropped: like every GEOBENCH saver
 * the settings (6 roaches, normal speed, flee) are baked in. Card-only (the floppy pack
 * is at its 64K ceiling). */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_PAPER  (*(volatile unsigned char *)0x122C) /* pen-0 (background) hardware ink (INKS= 1st) */
#define KCFG_BORDER (*(volatile unsigned char *)0x1230) /* desktop's configured border ink (INKS= 5th) */

#define MAX_ROACHES   6
#define ROACH_W       16
#define ROACH_H       16
#define SCREEN_W      320
#define SCREEN_H      200

#define SCATTER_SPEED 6
#define SCATTER_TICKS 25
#define FLEE_DIST     64
#define SPEED         3        /* normal cruising speed (px/tick) */
#define FRAME_SKIP    2        /* run anim_tick every Nth frame */
#define RESET_FRAMES  6000u    /* re-scatter everyone every ~2 min */

#define BG            0        /* blue background (pen 0) -> byte 0x00 */
#define ROACH_INK     2        /* black roach body (pen 2) */
#define ODD_INK       3        /* red "odd" roach (pen 3) */

/* GEOBENCH Mode-1 pens: 0=blue 1=white 2=black 3=red. Sprite buffers: 16 rows x 4
   bytes = 64 bytes each, four headings: 0=E 1=S 2=W 3=N. */
static unsigned char m1_spr[4][64];
static unsigned char m1_spr_odd[4][64];

static unsigned char lmx, lmy, armed;
static unsigned int  rng;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* SCR SET BORDER (&BC38): drive the CPC border to the hardware ink in brd_ink. On start
   we match the blue background; on exit we restore the desktop's configured border. */
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

/* ---- Sprite ASCII art ('.' = background, '3' = roach body) -------------------- */

static const char *const roach_E_art[16] = {
    ".....3....3.....", "3....3....3.....", "33...3...33.....", ".33..33.33......",
    "..3.33333.....33", "..3333.33.3..33.", ".333...3333333..", "333..33333333...",
    "3333333333333...", ".3333333333333..", "..3333333.3..33.", "..3.33333.....33",
    ".33..33.33......", "33...3...33.....", "3....3....3.....", ".....3....3.....",
};
static const char *const roach_W_art[16] = {
    ".....3....3.....", ".....3....3....3", ".....33...3...33", "......33.33..33.",
    "33.....33333.3..", ".33..3.3333333..", "..3333333333333.", "...3333333333333",
    "...33333333..333", "..3333333...333.", ".33..3.33.3333..", "33.....33333.3..",
    "......33.33..33.", ".....33...3...33", ".....3....3....3", ".....3....3.....",
};
static const char *const roach_N_art[16] = {
    "....3......3....", "....33....33....", ".....33..33.....", "......3333......",
    "......3333......", "333..333333..333", "..33..3333..33..", "...3333333333...",
    "....33333333....", "...33..333333...", "333333.333333333", "....33..3333....",
    ".....33.333.....", "...3333333333...", "..33..3333..33..", ".33....33....33.",
};
static const char *const roach_S_art[16] = {
    ".33....33....33.", "..33..3333..33..", "...3333333333...", ".....333.33.....",
    "....3333..33....", "333333333.333333", "...333333..33...", "....33333333....",
    "...3333333333...", "..33..3333..33..", "333..333333..333", "......3333......",
    "......3333......", ".....33..33.....", "....33....33....", "....3......3....",
};

/* Direction tables: 0=E 1=SE 2=S 3=SW 4=W 5=NW 6=N 7=NE (x snaps to 4px boundaries). */
static const signed char dir_dx[8] = {  3,  2,  0, -2, -3, -2,  0,  2 };
static const signed char dir_dy[8] = {  0,  2,  3,  2,  0, -2, -3, -2 };
static const unsigned char dir_spr[8] = { 0, 0, 1, 2, 2, 2, 3, 0 };  /* dir -> sprite idx */

/* Encode one heading's ASCII art into a 64-byte Mode-1 buffer in the given pen. The
   blue (pen 0) background leaves a byte clear; a body pixel sets the lo plane (pen&1)
   and/or hi plane (pen&2), matching #C000 plane layout (lo=0x80>>p, hi=0x08>>p). */
static void build_sprite(unsigned char *dst, const char *const *art, unsigned char ink)
{
    unsigned char row, col, p, b;
    for (row = 0; row < 16; row++) {
        for (col = 0; col < 4; col++) {
            b = 0;                              /* pen 0 background */
            for (p = 0; p < 4; p++) {
                if (art[row][(col << 2) + p] == '3') {
                    if (ink & 1) b |= (unsigned char)(0x80u >> p);
                    if (ink & 2) b |= (unsigned char)(0x08u >> p);
                }
            }
            dst[row * 4 + col] = b;
        }
    }
}

/* ---- Direct #C000 blit (x must be a multiple of 4; coords stay fully on-screen) -- */

static unsigned char *scr_addr(int x, int y)
{
    return (unsigned char *)(0xC000u + (unsigned int)(y >> 3) * 80u
        + (unsigned int)(y & 7) * 0x800u + (unsigned int)(x >> 2));
}

static void xr_blit(int x, int y, const unsigned char *spr)
{
    unsigned char row, c, *p;
    for (row = 0; row < 16; row++) {
        p = scr_addr(x, y + row);
        for (c = 0; c < 4; c++) p[c] = spr[row * 4 + c];
    }
}

static void xr_erase(int x, int y)
{
    unsigned char row, c, *p;
    for (row = 0; row < 16; row++) {
        p = scr_addr(x, y + row);
        for (c = 0; c < 4; c++) p[c] = 0;       /* pen 0 background */
    }
}

/* ---- Roach state + AI -------------------------------------------------------- */

typedef struct {
    int x, y, ox, oy;
    unsigned char dir, steps, scatter;
} Roach;

static Roach roaches[MAX_ROACHES];
static Roach odd_roach;

/* Direction index most aligned with (dx, dy) (steers flee/chase). */
static unsigned char best_dir(int dx, int dy)
{
    unsigned char best, i;
    int best_dot, dot;
    best = 0; best_dot = -32000;
    for (i = 0; i < 8; i++) {
        dot = (int)dir_dx[i] * dx + (int)dir_dy[i] * dy;
        if (dot > best_dot) { best_dot = dot; best = i; }
    }
    return best;
}

static void place(Roach *r)
{
    r->x  = (int)(20 + rnd() % (SCREEN_W - ROACH_W - 40)) & ~3;
    r->y  =  (int)(20 + rnd() % (SCREEN_H - ROACH_H - 40));
    r->ox = r->x; r->oy = r->y;
    r->dir = (unsigned char)(rnd() & 7);
    r->steps = (unsigned char)(rnd() & 31);
}

static void reset_roaches(void)
{
    unsigned char i;
    for (i = 0; i < MAX_ROACHES; i++) { place(&roaches[i]); roaches[i].scatter = SCATTER_TICKS; }
    place(&odd_roach); odd_roach.scatter = 0;
}

static void anim_tick(void)
{
    unsigned char i, spd, spr_idx, tries, nd;
    Roach *r, *w;
    int nx, ny, sx, tnx, tny, wdx, wdy, wdist;

    /* --- the odd roach wanders, ignoring the others --- */
    w = &odd_roach;
    nx = w->x + (int)dir_dx[w->dir] * SCATTER_SPEED;
    ny = w->y + (int)dir_dy[w->dir] * SCATTER_SPEED;
    if (nx < 0 || nx + ROACH_W > SCREEN_W || ny < 0 || ny + ROACH_H > SCREEN_H) {
        w->dir = (w->dir + 4) & 7; w->steps = 3 + (unsigned char)(rnd() & 7);
        nx = w->x; ny = w->y;
    }
    if (w->steps == 0) { w->dir = (w->dir + 1 + (unsigned char)(rnd() & 5)) & 7;
                         w->steps = 10 + (unsigned char)(rnd() & 31); }
    else w->steps--;
    xr_erase(w->ox & ~3, w->oy);
    w->x = nx; w->y = ny; w->ox = nx; w->oy = ny;
    spr_idx = dir_spr[w->dir];
    xr_blit(nx & ~3, ny, m1_spr_odd[spr_idx]);

    /* --- the pack --- */
    for (i = 0; i < MAX_ROACHES; i++) {
        r = &roaches[i];

        /* flee the odd roach when it gets close (validate the heading clears a wall) */
        wdx = r->x - odd_roach.x; wdy = r->y - odd_roach.y;
        wdist = (wdx < 0 ? -wdx : wdx) + (wdy < 0 ? -wdy : wdy);
        if (wdist < FLEE_DIST) {
            nd = best_dir(wdx, wdy);
            tnx = r->x + (int)dir_dx[nd] * SCATTER_SPEED;
            tny = r->y + (int)dir_dy[nd] * SCATTER_SPEED;
            if (tnx >= 0 && tnx + ROACH_W <= SCREEN_W && tny >= 0 && tny + ROACH_H <= SCREEN_H) {
                r->dir = nd; r->scatter = SCATTER_TICKS; r->steps = 8;
            }
        }

        spd = r->scatter ? SCATTER_SPEED : SPEED;
        if (r->scatter) r->scatter--;

        nx = r->x + (int)dir_dx[r->dir] * (int)spd;
        ny = r->y + (int)dir_dy[r->dir] * (int)spd;
        if (nx < 0 || nx + ROACH_W > SCREEN_W || ny < 0 || ny + ROACH_H > SCREEN_H) {
            for (tries = 0; tries < 8; tries++) {       /* rotate to a heading that clears */
                r->dir = (r->dir + 1) & 7;
                nx = r->x + (int)dir_dx[r->dir] * (int)spd;
                ny = r->y + (int)dir_dy[r->dir] * (int)spd;
                if (nx >= 0 && nx + ROACH_W <= SCREEN_W && ny >= 0 && ny + ROACH_H <= SCREEN_H) break;
            }
            if (tries >= 8) { nx = r->x; ny = r->y; }
            r->steps = 10 + (unsigned char)(rnd() & 31);
        }

        if (r->steps == 0) { r->dir = (r->dir + 1 + (unsigned char)(rnd() & 5)) & 7;
                             r->steps = 10 + (unsigned char)(rnd() & 31); }
        else r->steps--;

        sx = r->ox & ~3;
        xr_erase(sx, r->oy);
        r->x = nx; r->y = ny; r->ox = nx; r->oy = ny;
        spr_idx = dir_spr[r->dir];
        xr_blit(nx & ~3, ny, m1_spr[spr_idx]);
    }
}

/* ---- Screensaver shell (mirrors apps/starfield/main.c) ----------------------- */

static unsigned char tick;
static unsigned int  reset_ctr;

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
    if (++tick >= FRAME_SKIP) {
        tick = 0;
        anim_tick();
        if (++reset_ctr >= RESET_FRAMES) { reset_ctr = 0; ss_paint(); reset_roaches(); }
    }
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0; tick = 0; reset_ctr = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x52A3u);
    if (!rng) rng = 0x52A3u;

    build_sprite(m1_spr[0], roach_E_art, ROACH_INK);
    build_sprite(m1_spr[1], roach_S_art, ROACH_INK);
    build_sprite(m1_spr[2], roach_W_art, ROACH_INK);
    build_sprite(m1_spr[3], roach_N_art, ROACH_INK);
    build_sprite(m1_spr_odd[0], roach_E_art, ODD_INK);
    build_sprite(m1_spr_odd[1], roach_S_art, ODD_INK);
    build_sprite(m1_spr_odd[2], roach_W_art, ODD_INK);
    build_sprite(m1_spr_odd[3], roach_N_art, ODD_INK);
    reset_roaches();

    WM_FS = 1;
    brd_ink = KCFG_PAPER;        /* border = pen-0 ink -> continuous with the blue field */
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
