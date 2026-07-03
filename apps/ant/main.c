/* ant - Langton's-ant screensaver for GEOBENCH (#219 family).
 *
 * Inspired by the xscreensaver ant hack (Turk's generalised ants). A virtual ant walks
 * an 80x50 grid of 4x4-pixel cells; on each step it reads the cell's state, turns left
 * or right by the rule string, advances the cell to the next state (recolouring it), and
 * steps forward - emergent highways and symmetric growth appear from a trivial integer
 * rule. The 4-state rule "LLRR" cycles all four pens. Cells drawn with gb_fill (4px-
 * aligned, exactly one cell). Card-only (the floppy pack is full). */
#include "gb.h"

#define WM_FS (*(volatile unsigned char *)0x130A)
#define KCFG_BORDER (*(volatile unsigned char *)0x1230)
#define KCFG_INK(p) (((volatile unsigned char *)0x122C)[(p)])

#define BG    0          /* blue background = cell state 0 */
#ifdef GB_MSX2
#define COLS  128        /* 128 byte-cols x 53 rows of 4-line cells = 512x212 */
#define ROWS  53
#else
#define COLS  80         /* 80 byte-cols x 50 rows of 4-line cells = 320x200 */
#define ROWS  50
#endif
#define STEPS 40         /* ant steps per frame */
#define RESET 24000u     /* steps before a fresh grid */

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
static void set_border(void) { (void)brd_ink; }   /* MSX: border unchanged during ANT */
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

/* flat grid + 16-bit index: a [ROWS][COLS] array indexed by a uchar would wrap the
   *COLS offset at 8 bits (the SDCC 2D-array gotcha) - keep it flat. */
static unsigned char grid[COLS * ROWS];
static unsigned char acx, acy, adir;     /* ant column, row, direction (0=N 1=E 2=S 3=W) */
static unsigned int  steps;

static const unsigned char turn_r[4] = { 0, 0, 1, 1 };  /* rule "LLRR": 0=left 1=right */
static const unsigned char state_pen[4] = { 0, 1, 3, 2 }; /* blue, white, red, black */

static void clear_grid(void)
{
    unsigned int i;
    for (i = 0; i < COLS * ROWS; i++) grid[i] = 0;
    gb_fill(0, 0, GB_COLS, GB_LINES, BG);
    acx = COLS / 2; acy = ROWS / 2; adir = 0;
    steps = 0;
}

static void ant_step(void)
{
    unsigned int idx = (unsigned int)acy * COLS + acx;
    unsigned char s = grid[idx];
    unsigned char ns = (unsigned char)((s + 1) & 3);
    grid[idx] = ns;
    gb_fill(acx, (unsigned char)(acy << 2), 1, 4, state_pen[ns]);   /* 4x4 cell */
    if (turn_r[s]) adir = (unsigned char)((adir + 1) & 3);          /* right */
    else           adir = (unsigned char)((adir + 3) & 3);          /* left  */
    switch (adir) {                                                 /* advance + wrap */
        case 0: acy = acy ? (unsigned char)(acy - 1) : ROWS - 1; break;
        case 1: acx = (unsigned char)((acx + 1) % COLS); break;
        case 2: acy = (unsigned char)((acy + 1) % ROWS); break;
        default: acx = acx ? (unsigned char)(acx - 1) : COLS - 1; break;
    }
}

static void ss_paint(void)
{
    gb_fill(0, 0, GB_COLS, GB_LINES, BG);
}

static void ss_frame(void)
{
    unsigned char i, f = gb_flags();
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
    for (i = 0; i < STEPS; i++) ant_step();
    if ((steps += STEPS) >= RESET) clear_grid();
}

static const gb_win_t sswin = { 0, 0, GB_COLS, GB_LINES, ss_frame, ss_paint, 0, 0 };

void main(void)
{
    unsigned char n;
    lmx = gb_mx(); lmy = gb_my();
    armed = 0;
    gb_time();
    rng = (unsigned int)((gb_sec << 8) ^ (gb_min << 3) ^ gb_hour ^ 0x414Eu);
    if (!rng) rng = 0x414Eu;

    WM_FS = 1;
    brd_ink = KCFG_INK(BG);
    set_border();
    gb_curhide();
    for (n = 64; n; n--) if (!gb_getkey()) break;
    clear_grid();
    gb_wm_add(&sswin);
}
