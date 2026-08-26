/* xmatrix - Matrix digital rain for GEOBENCH (#404).
 *
 * The glyphs and feeder animation are ported from ../symsav-xmatrix. Binary
 * and Kana styles share the original 8x8 artwork. Glyph buffers are built in
 * each target's native screen representation so CPC, MSX and PCW all render
 * the same shapes.
 *
 * CPC can select any hardware ink for the main trail. MSX Screen 6 keeps the
 * original fixed green palette, while Screen 7 selects a stable 16-colour
 * palette entry. The launch-time palette is restored before the desktop
 * returns. */
#include "gb.h"
#include "gbcfg.h"
#include "gbsaver.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_INKS ((volatile unsigned char *)0x122C)

#define CW    2
#define GW    (GB_COLS / CW)
#define GH    (GB_LINES / 8)
#define TOTAL (GW * GH)

#define NGLYPHS_BINARY 2
#define NGLYPHS_KANA   9
#define NGLYPHS_TOTAL  (NGLYPHS_BINARY + NGLYPHS_KANA)
#define GLOW_MAX       6
#define GLOW_WHITE     3
#define DENSITY        2

#define MATRIX_FEEDERS_PER_FRAME 16
#define MATRIX_CELLS_PER_FRAME   512
#define MATRIX_DRAWS_PER_FRAME    12

#define MATRIX_FEED  0
#define MATRIX_DECAY 1
#define MATRIX_SPAWN 2
#define MATRIX_DRAW  3
#define MATRIX_DELAY 4

#ifdef GB_MSX2
#define GLYPH_SLOT 32
#define MSX_SCRMOD (*(volatile unsigned char *)0xFCAF)
#define FS_SAVE_LEN_K (*(volatile unsigned int *)0x14FD)
#else
#define GLYPH_SLOT 16
#endif

#ifdef GB_PCW
#define BG_PEN     2
#define HEAD_PEN   1
#define BRIGHT_PEN 3
#define DIM_PEN    0
#else
#define BG_PEN     0
#define HEAD_PEN   1
#define BRIGHT_PEN 3
#define DIM_PEN    2
#endif

/* Exact 8x8 artwork from symsav-xmatrix: 0, 1, then nine Katakana. */
static const unsigned char glyph_bits[NGLYPHS_TOTAL][8] = {
    { 0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00 },
    { 0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00 },
    { 0xFF,0x18,0x18,0x18,0x18,0xFF,0x00,0x00 },
    { 0x7E,0x60,0x60,0x60,0x60,0x7E,0x00,0x00 },
    { 0x7E,0x0C,0x18,0x3C,0x66,0xC3,0x00,0x00 },
    { 0x0C,0x0C,0x7F,0x0C,0x0C,0x0C,0x00,0x00 },
    { 0x18,0xFF,0x18,0x66,0xC3,0x00,0x00,0x00 },
    { 0x7E,0x03,0x06,0x0C,0x18,0x30,0x00,0x00 },
    { 0x7E,0x66,0x66,0x66,0x66,0x7E,0x00,0x00 },
    { 0x3C,0x18,0xFF,0x18,0x1F,0x00,0x00,0x00 },
    { 0x6F,0x66,0x36,0x0F,0x0E,0x18,0x00,0x00 }
};

static unsigned char font_head[NGLYPHS_TOTAL * GLYPH_SLOT];
static unsigned char font_bright[NGLYPHS_TOTAL * GLYPH_SLOT];
static unsigned char font_dim[NGLYPHS_TOTAL * GLYPH_SLOT];

static unsigned char cg[TOTAL];
static unsigned char cgl[TOTAL];
static unsigned char cd[TOTAL];
static signed char   fy[GW];
static unsigned char frem[GW];
static unsigned char fthr[GW];

static unsigned char lmx, lmy, armed, frame_skip;
static unsigned char glyph_base, glyph_count, matrix_speed;
static unsigned char matrix_stage, feeder_cursor, frame_delay;
static unsigned int cell_cursor;
#ifndef GB_PCW
static unsigned char matrix_color;
#endif
static unsigned int rng;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

#if !defined(GB_PCW)
static volatile unsigned char pal_pen, pal_ink;
static unsigned char saved_inks[5];

#ifdef GB_MSX2
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
#else
static void pal_set_call(void) __naked
{
__asm
    ld   a,(_pal_ink)
    ld   b,a
    ld   c,a
    ld   a,(_pal_pen)
    call 0xBC32
    ret
__endasm;
}

static void border_set_call(void) __naked
{
__asm
    ld   a,(_pal_ink)
    ld   b,a
    ld   c,a
    call 0xBC38
    ret
__endasm;
}
#endif

static void set_ink(unsigned char pen, unsigned char ink)
{
    pal_pen = pen;
    pal_ink = ink;
    pal_set_call();
}

#ifdef GB_MSX2
/* Dim companions for the fixed Screen-7 colours at palette indices 4..15. */
static const unsigned char mode7_dim_ink[12] = {
    9, 1, 12, 4, 10, 3, 4, 1, 9, 4, 13, 9
};
#else
/* CPC hardware inks form a 3x3x3 RGB cube. Each selected component is stepped
 * down once to make the fading trail retain the same hue. */
static const unsigned char cpc_dim_ink[27] = {
    0,0,1, 0,0,1, 3,3,4,
    0,0,1, 0,0,1, 3,3,4,
    9,9,10, 9,9,10, 12,12,13
};
#endif

static void save_palette(void)
{
    unsigned char i;
    for (i = 0; i < 5; i++) saved_inks[i] = KCFG_INKS[i];
}

static void matrix_palette(void)
{
    unsigned char main_ink = 18;
    unsigned char dim_ink = 9;
#ifdef GB_MSX2
    if (MSX_SCRMOD == 7) {
        dim_ink = mode7_dim_ink[matrix_color - GB_XMATRIX_MSX_COLOR_MIN];
        set_ink(0, 0);
        set_ink(1, 26);
        set_ink(2, dim_ink);
        return;
    }
#else
    main_ink = matrix_color;
    dim_ink = cpc_dim_ink[matrix_color];
#endif
    set_ink(0, 0);
    set_ink(1, 26);
    set_ink(2, dim_ink);
    set_ink(3, main_ink);
#ifndef GB_MSX2
    pal_ink = 0;
    border_set_call();
#endif
}

static void restore_palette(void)
{
    unsigned char i;
    for (i = 0; i < 4; i++) set_ink(i, saved_inks[i]);
#ifndef GB_MSX2
    pal_ink = saved_inks[4];
    border_set_call();
#endif
}
#else
static void save_palette(void) { }
static void matrix_palette(void) { }
static void restore_palette(void) { }
#endif

static unsigned char encode4(unsigned char bits, unsigned char first,
                             unsigned char fg, unsigned char bg)
{
    unsigned char i, pen, out = 0;
    for (i = 0; i < 4; i++) {
        pen = (bits & (unsigned char)(0x80u >> (first + i))) ? fg : bg;
#if defined(GB_MSX2) || defined(GB_PCW)
        out |= (unsigned char)(pen << (6 - 2 * i));
#else
        if (pen & 1) out |= (unsigned char)(0x80u >> i);
        if (pen & 2) out |= (unsigned char)(0x08u >> i);
#endif
    }
#ifdef GB_PCW
    out = (unsigned char)(((out & 0x55) << 1) |
                          (((out ^ 0xFF) & 0xAA) >> 1));
#endif
    return out;
}

static void build_font(void)
{
    unsigned char g, r, bits;
    unsigned int off;
    for (g = 0; g < NGLYPHS_TOTAL; g++) {
        for (r = 0; r < 8; r++) {
            bits = glyph_bits[g][r];
#ifdef GB_MSX2
            if (MSX_SCRMOD == 7) {
                unsigned char b, lp, rp;
                off = (unsigned int)g * GLYPH_SLOT + (unsigned int)r * 4;
                for (b = 0; b < 4; b++) {
                    lp = (bits & (unsigned char)(0x80u >> (b * 2))) ? 1 : 0;
                    rp = (bits & (unsigned char)(0x40u >> (b * 2))) ? 1 : 0;
                    font_head[off + b] =
                        (unsigned char)((lp ? HEAD_PEN : BG_PEN) << 4 |
                                        (rp ? HEAD_PEN : BG_PEN));
                    font_bright[off + b] =
                        (unsigned char)((lp ? matrix_color : BG_PEN) << 4 |
                                        (rp ? matrix_color : BG_PEN));
                    font_dim[off + b] =
                        (unsigned char)((lp ? DIM_PEN : BG_PEN) << 4 |
                                        (rp ? DIM_PEN : BG_PEN));
                }
                continue;
            }
#endif
            off = (unsigned int)g * GLYPH_SLOT + (unsigned int)r * 2;
            font_head[off]       = encode4(bits, 0, HEAD_PEN, BG_PEN);
            font_head[off + 1]   = encode4(bits, 4, HEAD_PEN, BG_PEN);
            font_bright[off]     = encode4(bits, 0, BRIGHT_PEN, BG_PEN);
            font_bright[off + 1] = encode4(bits, 4, BRIGHT_PEN, BG_PEN);
            font_dim[off]        = encode4(bits, 0, DIM_PEN, BG_PEN);
            font_dim[off + 1]    = encode4(bits, 4, DIM_PEN, BG_PEN);
        }
    }
}

#ifdef GB_MSX2
static void native16_blit(unsigned char x, unsigned char y,
                          const unsigned char *source)
{
    gb_pic_edit_buf = (unsigned int)source;
    gb_pic_edit_off = (unsigned int)x | ((unsigned int)y << 8);
    FS_SAVE_LEN_K = CW | ((unsigned int)8 << 8);
    (void)gb_pic_edit(GB_PICEDIT_NATIVE16);
}
#endif

static void draw_cell(unsigned char cx, unsigned char cy,
                      unsigned char g, unsigned char stage)
{
    const unsigned char *font = stage >= 2 ? font_head :
                                stage == 1 ? font_bright : font_dim;
    const unsigned char *source = font + (unsigned int)g * GLYPH_SLOT;
#ifdef GB_MSX2
    if (MSX_SCRMOD == 7) {
        native16_blit((unsigned char)(cx * CW), (unsigned char)(cy * 8), source);
        return;
    }
#endif
    gb_restorerect((unsigned char)(cx * CW), (unsigned char)(cy * 8),
                   CW, 8, source);
}

static void feeder_step(unsigned char x)
{
    unsigned int idx;
    if (fy[x] < 0) return;
    if (fthr[x]) { fthr[x]--; return; }
    if ((unsigned char)fy[x] < GH) {
        idx = (unsigned int)(unsigned char)fy[x] * GW + x;
        if (frem[x]) {
            cg[idx] = (unsigned char)(glyph_base + rnd() % glyph_count + 1);
            cgl[idx] = GLOW_MAX;
            cd[idx] = 1;
            frem[x]--;
        } else if (cg[idx]) {
            cg[idx] = 0;
            cgl[idx] = 0;
            cd[idx] = 1;
        }
    }
    fy[x]++;
    if (fy[x] >= GH) { fy[x] = -1; frem[x] = 0; }
}

static void spawn_feeders(void)
{
    unsigned char x, nf = DENSITY;
    while (nf--) {
        x = (unsigned char)(rnd() % GW);
        if (fy[x] >= 0) continue;
        fy[x] = (signed char)(rnd() % (GH / 3));
        frem[x] = (unsigned char)(5 + rnd() % (GH - 5));
        fthr[x] = matrix_speed >= 3 ? 0 :
                  matrix_speed == 2 ? (unsigned char)(rnd() % 4) :
                                      (unsigned char)(rnd() % 8);
    }
}

static void anim_work(void)
{
    unsigned int idx;
    unsigned int work;
    unsigned char x, y, draws;

    if (matrix_stage == MATRIX_DELAY) {
        if (frame_delay) { frame_delay--; return; }
        feeder_cursor = 0;
        matrix_stage = MATRIX_FEED;
    }

    if (matrix_stage == MATRIX_FEED) {
        x = MATRIX_FEEDERS_PER_FRAME;
        while (x-- && feeder_cursor < GW)
            feeder_step(feeder_cursor++);
        if (feeder_cursor >= GW) {
            cell_cursor = 0;
            matrix_stage = MATRIX_DECAY;
        }
        return;
    }

    if (matrix_stage == MATRIX_DECAY) {
        work = MATRIX_CELLS_PER_FRAME;
        while (work-- && cell_cursor < TOTAL) {
            idx = cell_cursor++;
            if (cg[idx] && cgl[idx]) {
                cgl[idx]--;
                if (cgl[idx] == GLOW_WHITE || cgl[idx] == 0) cd[idx] = 1;
            }
        }
        if (cell_cursor >= TOTAL) matrix_stage = MATRIX_SPAWN;
        return;
    }

    if (matrix_stage == MATRIX_SPAWN) {
        spawn_feeders();
        cell_cursor = 0;
        matrix_stage = MATRIX_DRAW;
        return;
    }

    work = MATRIX_CELLS_PER_FRAME;
    draws = 0;
    while (work-- && cell_cursor < TOTAL) {
        idx = cell_cursor;
        if (cd[idx]) {
            if (draws >= MATRIX_DRAWS_PER_FRAME) break;
            cd[idx] = 0;
            y = (unsigned char)(idx / GW);
            x = (unsigned char)(idx - (unsigned int)y * GW);
            if (!cg[idx])
                gb_fill((unsigned char)(x * CW), (unsigned char)(y * 8),
                        CW, 8, BG_PEN);
            else
                draw_cell(x, y, (unsigned char)(cg[idx] - 1),
                          cgl[idx] > GLOW_WHITE ? 2 : cgl[idx] ? 1 : 0);
            draws++;
        }
        cell_cursor++;
    }
    if (cell_cursor >= TOTAL) {
        frame_delay = (unsigned char)(frame_skip - 1);
        matrix_stage = MATRIX_DELAY;
    }
}

static void ss_paint(void)
{
    gb_fill(0, 0, GB_COLS, GB_LINES, BG_PEN);
}

static void ss_frame(void)
{
    unsigned char f = gb_flags();
    if (!armed) {
        while (gb_getkey()) ;
        if (!(f & (GB_CLICK | GB_FIRE | GB_QUIT))) {
            lmx = gb_mx();
            lmy = gb_my();
            armed = 1;
        }
        return;
    }
    if (gb_getkey() || (f & (GB_CLICK | GB_FIRE | GB_QUIT)) ||
        gb_mx() != lmx || gb_my() != lmy) {
        restore_palette();
        WM_FS = 0;
        gb_wm_close();
        return;
    }
    anim_work();
}

static const gb_win_t sswin = {
    0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0
};

void main(void)
{
    unsigned char n, glyphs;
    lmx = gb_mx();
    lmy = gb_my();
    armed = 0;
    matrix_stage = MATRIX_FEED;
    feeder_cursor = 0;
    cell_cursor = 0;
    frame_delay = 0;

    glyphs = gbcfg_u8(GB_XMATRIX_GLYPHS_KEY, GB_XMATRIX_GLYPHS_DEFAULT,
                      GB_XMATRIX_GLYPHS_MIN, GB_XMATRIX_GLYPHS_MAX);
    matrix_speed = gbcfg_u8(GB_XMATRIX_SPEED_KEY, GB_XMATRIX_SPEED_DEFAULT,
                            GB_XMATRIX_SPEED_MIN, GB_XMATRIX_SPEED_MAX);
    if (glyphs) {
        glyph_base = NGLYPHS_BINARY;
        glyph_count = NGLYPHS_KANA;
    } else {
        glyph_base = 0;
        glyph_count = NGLYPHS_BINARY;
    }
    frame_skip = matrix_speed == 1 ? 6 : matrix_speed == 2 ? 3 : 1;
#ifdef GB_MSX2
    matrix_color = GB_XMATRIX_MSX_COLOR_DEFAULT;
    if (MSX_SCRMOD == 7)
        matrix_color = gbcfg_u8(GB_XMATRIX_COLOR_KEY,
                                GB_XMATRIX_MSX_COLOR_DEFAULT,
                                GB_XMATRIX_MSX_COLOR_MIN,
                                GB_XMATRIX_MSX_COLOR_MAX);
#elif !defined(GB_PCW)
    matrix_color = gbcfg_u8(GB_XMATRIX_COLOR_KEY,
                            GB_XMATRIX_CPC_COLOR_DEFAULT,
                            GB_XMATRIX_CPC_COLOR_MIN,
                            GB_XMATRIX_CPC_COLOR_MAX);
#endif

    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^
                         gb_hour ^ 0x4A1Du);
    if (!rng) rng = 0x4A1Du;
    for (n = 0; n < GW; n++) fy[n] = -1;

    save_palette();
    matrix_palette();
    build_font();
    WM_FS = 1;
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
