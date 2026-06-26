/* xmatrix - a "Matrix" digital-rain screensaver for GEOBENCH (#219 family).
 *
 * Ported from the SymbOS symsav-xmatrix screensaver: a grid of cells, one
 * "feeder" per column dropping random glyphs with a glow countdown, so each
 * column shows a bright leading character with a fading trail behind it. The
 * SymbOS scaffolding (config dialog, message protocol) is dropped - this is just
 * a fullscreen window that animates and closes on input, like CIRCLE.SAV.
 *
 * The CPC original ran in Mode 1, an 8x8 grid (40x25). We keep that grid. There
 * is no green in GEOBENCH's 4-colour palette and no per-pen text primitive, so
 * we build each glyph as a small Mode-1 bitmap in two pens - WHITE (the bright
 * head) and RED (the trail) - and blit it with gb_restorerect. */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)

#define GW    40        /* grid: 40 cols (320/8) x 25 rows (200/8) */
#define GH    25
#define TOTAL (GW * GH)
#define CW    2         /* a cell is 2 byte columns (8px) x 8 lines */
#define GLOW_MAX   6
#define GLOW_WHITE 3    /* glow > this = white head, else red trail */
#define NGLYPHS    2
#define DENSITY    2    /* new feeders started per tick */
#define BG         0    /* background pen: 0 = blue */

/* glyph art: 8x8, one byte per row (bit 7 = leftmost pixel). Binary rain: 0 / 1. */
static const unsigned char glyph_bits[NGLYPHS][8] = {
    { 0x18,0x38,0x18,0x18,0x18,0x18,0x3C,0x00 },  /* 1 */
    { 0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00 },  /* 0 */
};

/* built glyph bitmaps: NGLYPHS * (8 rows * 2 Mode-1 bytes) per pen, on the blue bg. */
static unsigned char font_w[NGLYPHS * 16];   /* white (head) */
static unsigned char font_r[NGLYPHS * 16];   /* red   (trail) */

static unsigned char cg[TOTAL];    /* glyph: 0 = empty, else 1+index */
static unsigned char cgl[TOTAL];   /* glow countdown */
static unsigned char cd[TOTAL];    /* dirty: needs redraw */
static signed char   fy[GW];       /* feeder row (-1 = inactive) */
static unsigned char frem[GW];     /* glyphs left to drop */
static unsigned char fthr[GW];     /* throttle ticks */

static unsigned char lmx, lmy, armed, phase;
static unsigned int  rng;

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* set Mode-1 pixel k (0..3) within byte *b to pen p (0..3). */
static unsigned char put1(unsigned char b, unsigned char k, unsigned char p)
{
    if (p & 1) b |= (unsigned char)(1u << (7 - k));
    if (p & 2) b |= (unsigned char)(1u << (3 - k));
    return b;
}

/* build_font: expand glyph_bits into Mode-1 bitmaps for the white + red pens
   (foreground = the pen, background = pen 2 black), so a blit also clears the cell. */
static void build_font(void)
{
    unsigned char g, r, i, bits, p, *dst;
    for (g = 0; g < NGLYPHS; g++) {
        for (r = 0; r < 8; r++) {
            bits = glyph_bits[g][r];
            for (p = 1; p <= 2; p++) {              /* pass 1 = white, pass 2 = red */
                unsigned char pen = (p == 1) ? 1 : 3;
                unsigned char b0 = 0, b1 = 0;
                for (i = 0; i < 4; i++)
                    if (bits & (1u << (7 - i))) b0 = put1(b0, i, pen);
                for (i = 4; i < 8; i++)
                    if (bits & (1u << (7 - i))) b1 = put1(b1, i - 4, pen);
                dst = (p == 1) ? font_w : font_r;
                dst[g * 16 + r * 2]     = b0;
                dst[g * 16 + r * 2 + 1] = b1;
            }
        }
    }
}

static void draw_cell(unsigned char cx, unsigned char cy, unsigned char g, unsigned char head)
{
    gb_restorerect((unsigned char)(cx * CW), (unsigned char)(cy * 8), CW, 8,
                   (head ? font_w : font_r) + (unsigned int)g * 16);
}

static void anim_tick(void)
{
    unsigned int idx;
    unsigned char x, y, nf;

    for (x = 0; x < GW; x++) {                   /* advance feeders */
        if (fy[x] < 0) continue;
        if (fthr[x]) { fthr[x]--; continue; }
        if ((unsigned char)fy[x] < GH) {
            idx = (unsigned int)(unsigned char)fy[x] * GW + x;
            if (frem[x]) {
                cg[idx] = (unsigned char)(1 + rnd() % NGLYPHS);
                cgl[idx] = GLOW_MAX; cd[idx] = 1; frem[x]--;
            } else if (cg[idx]) {
                cg[idx] = 0; cgl[idx] = 0; cd[idx] = 1;
            }
        }
        fy[x]++;
        if (fy[x] >= GH) { fy[x] = -1; frem[x] = 0; }
    }

    for (idx = 0; idx < TOTAL; idx++)            /* glow decay */
        if (cg[idx] && cgl[idx]) {
            cgl[idx]--;
            if (cgl[idx] == GLOW_WHITE || cgl[idx] == 0) cd[idx] = 1;
        }

    nf = DENSITY;                                /* start new feeders */
    while (nf--) {
        x = (unsigned char)(rnd() % GW);
        if (fy[x] >= 0) continue;
        fy[x]   = (signed char)(rnd() % (GH / 3));
        frem[x] = (unsigned char)(5 + rnd() % (GH - 5));
        fthr[x] = (unsigned char)(rnd() % 4);
    }

    idx = 0;                                     /* render dirty cells */
    for (y = 0; y < GH; y++)
        for (x = 0; x < GW; x++, idx++) {
            if (!cd[idx]) continue;
            cd[idx] = 0;
            if (!cg[idx]) gb_fill((unsigned char)(x * CW), (unsigned char)(y * 8), CW, 8, BG);
            else draw_cell(x, y, (unsigned char)(cg[idx] - 1), cgl[idx] > GLOW_WHITE);
        }
}

static void ss_paint(void)
{
    gb_fill(0, 0, 80, 200, BG);                  /* blue screen */
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
    if (phase ^= 1) anim_tick();                 /* ~25 fps - every other frame */
}

static const gb_win_t sswin = { 0, 0, 80, 200, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0; phase = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x4A1Du);
    if (!rng) rng = 0x4A1Du;
    for (n = 0; n < GW; n++) fy[n] = -1;
    build_font();
    WM_FS = 1;
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
