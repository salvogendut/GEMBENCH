/* deco - an Art-Deco screensaver for GEOBENCH (#219 family).
 *
 * Ported from the SymbOS symsav-deco screensaver (the recursive rectangle-
 * subdivision idea): split the screen into panels, each a solid colour with a
 * gap between them, hold a moment, then regenerate. The SymbOS scaffolding
 * (config dialog, message protocol) is dropped - a GEOBENCH saver is just a
 * fullscreen window that animates and closes on input, like CIRCLE.SAV.
 *
 * The original already ran in CPC Mode 1 with 4px-aligned splits, which line up
 * exactly with GEOBENCH byte columns - so the fills map straight onto gb_fill. */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)   /* app-side full-screen flag */

/* The screen, in GEOBENCH units: byte columns (x/w, 4px each) and lines (y/h).
   Derived from the platform geometry so the layout fills the MSX2 512x212 screen
   as well as the CPC 320x200 one (#287). */
#define SCR_W   GB_COLS
#define SCR_H   GB_LINES
#define BX      1        /* panel border, byte columns (4px) */
#define BY      4        /* panel border, lines */
#define MIN_W   5        /* stop splitting below this (byte cols) */
#define MIN_H   20       /* ... and this (lines) */
#define MAX_DEPTH 7      /* deeper -> more, smaller panels */
#define HOLD    140      /* frames a finished layout is held before a new one */

#define STACK_MAX 32
#define MAX_LEAVES 48

/* the four desktop pens as panel colours (0=blue,1=white,2=black,3=red); black
   (pen 2) is the background/border between panels. */
static const unsigned char inks[3] = { 1, 3, 0 };   /* white, red, blue */

#ifdef GB_MSX2
#define MSX_SCRMOD (*(volatile unsigned char *)0xFCAF)
#define GLINE_X0  (*(volatile unsigned int  *)0xC030)
#define GLINE_Y0  (*(volatile unsigned int  *)0xC032)
#define GLINE_X1  (*(volatile unsigned int  *)0xC034)
#define GLINE_Y1  (*(volatile unsigned int  *)0xC036)
#define GLINE_PEN (*(volatile unsigned char *)0xC038)

/* Screen 7 keeps these fixed extended palette entries in addition to the
   theme-controlled desktop pens. Pen 2 remains the black panel border. */
static const unsigned char inks16[15] = {
    1, 3, 0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
};
static unsigned char mode7;

static void deco_fw_line(void) __naked
{
__asm
    call 0x8009
    ret
__endasm;
}
#endif

static unsigned char lmx, lmy, armed;
static unsigned int  rng;
static unsigned int  hold;

static signed char sx[STACK_MAX], sy[STACK_MAX];
static unsigned char sw[STACK_MAX], sh_[STACK_MAX], sd[STACK_MAX];

static unsigned int rnd(void)
{
    rng ^= (unsigned int)(rng << 7);
    rng ^= (unsigned int)(rng >> 9);
    rng ^= (unsigned int)(rng << 8);
    return rng;
}

/* clamp helper for a signed split value into [lo, hi]. */
static int clampi(int v, int lo, int hi)
{
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    return v;
}

/* gb_fill is deliberately a four-pen primitive on every target. Screen 7
   rectangles that use its extended palette are therefore emitted as V9938
   horizontal lines; all other targets and pens retain the original fast fill. */
static void panel_fill(unsigned char x, unsigned char y,
                       unsigned char w, unsigned char h, unsigned char ink)
{
#ifdef GB_MSX2
    if (mode7 && ink > 3) {
        unsigned int py;
        GLINE_X0 = (unsigned int)x * 4u;
        GLINE_X1 = GLINE_X0 + (unsigned int)w * 4u - 1u;
        GLINE_PEN = ink;
        for (py = y; py < (unsigned int)y + h; py++) {
            GLINE_Y0 = py;
            GLINE_Y1 = py;
            deco_fw_line();
        }
        return;
    }
#endif
    gb_fill(x, y, w, h, ink);
}

static unsigned char panel_ink(void)
{
#ifdef GB_MSX2
    if (mode7) return inks16[rnd() % 15];
#endif
    return inks[rnd() % 3];
}

/* deco_frame: subdivide the whole screen and fill the leaf panels. Iterative
   work stack (no recursion); splits the longer side at a 38/62 ratio for the
   art-deco proportions. Mirrors symsav-deco's deco_plan + deco_render. */
static void deco_frame(void)
{
    unsigned char top = 1, x, y, w, h, depth;
    unsigned char nleaf = 0;

    gb_fill(0, 0, SCR_W, SCR_H, 2);             /* black canvas */
    sx[0] = 0; sy[0] = 0; sw[0] = SCR_W; sh_[0] = SCR_H; sd[0] = 0;

    while (top > 0) {
        top--;
        x = (unsigned char)sx[top]; y = (unsigned char)sy[top];
        w = sw[top]; h = sh_[top]; depth = sd[top];

        if (w < MIN_W || h < MIN_H || (int)(rnd() % MAX_DEPTH) < (int)depth) {
            if (nleaf < MAX_LEAVES && w > 2 * BX && h > 2 * BY) {
                panel_fill((unsigned char)(x + BX), (unsigned char)(y + BY),
                           (unsigned char)(w - 2 * BX), (unsigned char)(h - 2 * BY),
                           panel_ink());
                nleaf++;
            }
            continue;
        }

        if ((w > h ? 1 : 0)) {                  /* split the wider side, left|right */
            int wn = (rnd() & 1) ? (w * 38 / 100) : (w * 62 / 100);
            wn = clampi(wn, BX + 1, w - BX - 1);
            if (top + 2 <= STACK_MAX) {
                sx[top] = (signed char)x;            sy[top] = (signed char)y;
                sw[top] = (unsigned char)wn;         sh_[top] = h; sd[top] = depth + 1; top++;
                sx[top] = (signed char)(x + wn);     sy[top] = (signed char)y;
                sw[top] = (unsigned char)(w - wn);   sh_[top] = h; sd[top] = depth + 1; top++;
            }
        } else {                                /* split the taller side, top|bottom */
            int hn = (rnd() & 1) ? (h * 38 / 100) : (h * 62 / 100);
            hn = clampi(hn, BY + 1, h - BY - 1);
            if (top + 2 <= STACK_MAX) {
                sx[top] = (signed char)x; sy[top] = (signed char)y;
                sw[top] = w; sh_[top] = (unsigned char)hn; sd[top] = depth + 1; top++;
                sx[top] = (signed char)x; sy[top] = (signed char)(y + hn);
                sw[top] = w; sh_[top] = (unsigned char)(h - hn); sd[top] = depth + 1; top++;
            }
        }
    }
}

static void ss_paint(void)
{
    deco_frame();
    hold = HOLD;
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
    if (hold) { hold--; return; }               /* hold the layout, then regenerate */
    deco_frame();
    hold = HOLD;
}

static const gb_win_t sswin = { 0, 0, SCR_W, SCR_H, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
#ifdef GB_MSX2
    mode7 = (MSX_SCRMOD == 7);
#endif
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0xD3C0u);
    if (!rng) rng = 0xD3C0u;
    WM_FS = 1;
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    ss_paint();
    gb_wm_add(&sswin);
}
