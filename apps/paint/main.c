/*
 * PAINT.APP - a Mode-1 paint/drawing app (#114).
 *
 * The canvas is a Mode-1 bitmap BUFFER held here (the source of truth); tools do
 * pixel ops into it, and it's rendered to the screen with gb_restorerect (which
 * rides the kernel's blit_bitmap). Saving never reads the screen; on_repaint
 * re-blits the buffer so the drawing survives a window restack.
 *
 * Phase 1: window + canvas + freehand pencil.
 * Phase 3 (here): the toolchest. The 5 tools (pencil/square/circle/fill/undo) are
 *   loaded at runtime from PAINT.IST - a normal ICONED-editable .IST set (24x24) -
 *   and blitted 2-per-row beside the canvas with the same gb_restorerect. A 4-ink
 *   palette and a pencil-width +/- sit below. Tool/ink/width selection is by click;
 *   only the pencil draws yet (shapes/fill/undo land in Phase 4). New/Load/Save +
 *   the .PIC format come in Phase 2.
 *
 * Pixel addressing: Mode-1 packs 4 px per byte; pixel i has bit0 @ 7-i, bit1 @ 3-i
 * (same as ICONED). gb_my is pixel-accurate (rows); gb_mxp gives the pixel x (#114,
 * gb_mx only resolves to the byte column). Co-resident window (gb_wm_add + the WM
 * loop drives on_frame / on_repaint), like apps/iconed/main.c.
 */
#include "gb.h"

#define DEF_X     4
#define DEF_Y     14
#define TITLE_H   14

#define CANVAS_WB 25                    /* canvas width in bytes (100 px / 4)    */
#define CANVAS_H  100                   /* canvas height in rows (px)            */
#define CANVAS_W  (CANVAS_WB * 4)       /* 100 px                                */
#define WIN_W     (CANVAS_WB + 15)      /* canvas + toolchest, in bytes          */
#define WIN_H     (TITLE_H + CANVAS_H + 4)

#define WHITE_BYTE 0xF0                 /* 4 px of pen 1 (white) - the blank canvas */

/* ---- tools (PAINT.IST icon order: pencil,square,circle,fill,undo) ----------- */
#define TOOL_PENCIL 0
#define TOOL_SQUARE 1
#define TOOL_CIRCLE 2
#define TOOL_FILL   3
#define TOOL_UNDO   4
#define N_TOOLS     5
#define TOOL_WB     6                   /* tool icon width in bytes (24 px)      */
#define TOOL_H      24                  /* tool icon height in rows              */
#define TOOL_SY     27                  /* tool row stride (24 + 3 gap)          */

static unsigned char win_x = DEF_X, win_y = DEF_Y;
/* live (draggable) window-relative geometry */
#define CVX  (unsigned char)(win_x + 1)            /* canvas left, byte column */
#define CVY  (unsigned char)(win_y + TITLE_H + 1)  /* canvas top, screen row   */
/* toolchest column: just right of the canvas */
#define TCX  (unsigned char)(CVX + CANVAS_WB + 1)  /* tools left, byte column  */
#define TCY  CVY                                    /* tools top = canvas top   */
#define PAL_Y (unsigned char)(TCY + 3 * TOOL_SY)    /* ink swatches below tools */
#define PAL_H 10
#define SW_WB 3                                      /* swatch width in bytes    */
#define WID_Y (unsigned char)(PAL_Y + PAL_H + 2)     /* pencil-width control row */

static unsigned char canvas[CANVAS_WB * CANVAS_H];
static unsigned char pen = 2;          /* current ink: 0 blue 1 white 2 black 3 red */
static unsigned char tool = TOOL_PENCIL;
static unsigned char pen_w = 1;        /* pencil width 1..4                     */

/* PAINT.IST loaded whole at startup; tools blit straight out of it. 2 sectors. */
#define IST_MAX 1024
static unsigned char ist[IST_MAX];
static unsigned char ist_ok = 0;       /* a valid GBIS set with >=N_TOOLS icons? */

/* ---- Mode-1 pixel packing (pixel i: bit0 @ 7-i, bit1 @ 3-i) ------------------ */
/* Replace pixel i's pen: clear its two bits first, else drawing over a non-zero
   pen blends (e.g. pen 2 over white pen 1 -> pen 3 red). */
static unsigned char set_pixel(unsigned char b, unsigned char i, unsigned char p)
{
    b &= (unsigned char)~((1 << (7 - i)) | (1 << (3 - i)));
    if (p & 1) b |= (unsigned char)(1 << (7 - i));
    if (p & 2) b |= (unsigned char)(1 << (3 - i));
    return b;
}

static void canvas_clear(void)         /* New: blank to white (pen 1) */
{
    unsigned int n;
    for (n = 0; n < (unsigned int)CANVAS_WB * CANVAS_H; n++) canvas[n] = WHITE_BYTE;
}

/* ---- PAINT.IST directory (16-byte header, then 4-byte entries: off,wb,h) ----- */
static unsigned int tool_off(unsigned char k)
{
    unsigned int p = 16 + (unsigned int)k * 4;
    return (unsigned int)ist[p] | ((unsigned int)ist[p + 1] << 8);
}
static unsigned char tool_wb(unsigned char k) { return ist[16 + (unsigned int)k * 4 + 2]; }
static unsigned char tool_h(unsigned char k)  { return ist[16 + (unsigned int)k * 4 + 3]; }

static void load_tools(void)
{
    unsigned int n;
    gb_set_name("PAINT   IST");
    n = gb_fs_load((char *)ist, IST_MAX);
    ist_ok = (n >= 16 && ist[0] == 'G' && ist[1] == 'B' && ist[2] == 'I' &&
              ist[3] == 'S' && ist[4] == 2 && ist[5] >= N_TOOLS);
}

/* tool k's top-left in byte col / row (2 per row) */
static unsigned char tool_x(unsigned char k) { return (unsigned char)(TCX + (k & 1) * TOOL_WB); }
static unsigned char tool_y(unsigned char k) { return (unsigned char)(TCY + (k >> 1) * TOOL_SY); }

/* ---- rendering -------------------------------------------------------------- */
/* render one canvas row (full width) to the screen */
static void blit_row(unsigned char row)
{
    gb_curhide();
    gb_restorerect(CVX, (unsigned char)(CVY + row), CANVAS_WB, 1,
                   canvas + (unsigned int)row * CANVAS_WB);
    gb_curshow();
}

/* render the whole canvas */
static void blit_canvas(void)
{
    gb_curhide();
    gb_restorerect(CVX, CVY, CANVAS_WB, CANVAS_H, canvas);
    gb_curshow();
}

static void draw_toolchest(void)
{
    unsigned char k;
    char wbuf[2];
    gb_curhide();
    if (ist_ok)
        for (k = 0; k < N_TOOLS; k++)
            gb_restorerect(tool_x(k), tool_y(k), tool_wb(k), tool_h(k),
                           ist + tool_off(k));
    gb_frame(tool_x(tool), tool_y(tool), TOOL_WB, TOOL_H, 3);   /* selected: red */

    for (k = 0; k < 4; k++)
        gb_fill((unsigned char)(TCX + k * SW_WB), PAL_Y, SW_WB, PAL_H, k);
    gb_frame((unsigned char)(TCX + pen * SW_WB), PAL_Y, SW_WB, PAL_H, 2); /* sel: black */

    gb_fill(TCX, WID_Y, TOOL_WB * 2, 8, 1);          /* white strip for the width row */
    gb_textbw(TCX, WID_Y, "-");
    wbuf[0] = (char)('0' + pen_w); wbuf[1] = 0;
    gb_textbw((unsigned char)(TCX + 5), WID_Y, wbuf);
    gb_textbw((unsigned char)(TCX + TOOL_WB + 3), WID_Y, "+");
    gb_curshow();
}

/* plot the brush (pen_w x pen_w) at canvas pixel (cx,cy) with the current pen */
static void plot(unsigned char cx, unsigned char cy)
{
    unsigned char dx, dy, x, y;
    unsigned int off;
    for (dy = 0; dy < pen_w; dy++) {
        y = (unsigned char)(cy + dy);
        if (y >= CANVAS_H) break;
        for (dx = 0; dx < pen_w; dx++) {
            x = (unsigned char)(cx + dx);
            if (x >= CANVAS_W) break;
            off = (unsigned int)y * CANVAS_WB + (x >> 2);
            canvas[off] = set_pixel(canvas[off], (unsigned char)(x & 3), pen);
        }
        blit_row(y);
    }
}

/* full window redraw (frame + canvas + toolchest) */
static void draw(void)
{
    gb_curhide();
    gb_window(win_x, win_y, WIN_W, WIN_H, "PAINT");   /* Phase 2: show the filename */
    gb_curshow();
    blit_canvas();
    draw_toolchest();
}

static void on_repaint(void) { draw(); }

/* a discrete click in the toolchest -> select tool / ink / width. Returns 1 if
   it hit something (so the canvas-draw path is skipped). */
static unsigned char hit_toolchest(unsigned char mx, unsigned char my)
{
    unsigned char rx, ry, k;
    if (mx < TCX || mx >= (unsigned char)(TCX + TOOL_WB * 2)) return 0;
    rx = (unsigned char)(mx - TCX);

    if (my >= TCY && my < (unsigned char)(TCY + 3 * TOOL_SY)) {     /* tools */
        ry = (unsigned char)(my - TCY);
        if (ry % TOOL_SY < TOOL_H) {
            k = (unsigned char)((ry / TOOL_SY) * 2 + (rx >= TOOL_WB ? 1 : 0));
            if (k < N_TOOLS) { tool = k; draw_toolchest(); }
        }
        return 1;
    }
    if (my >= PAL_Y && my < (unsigned char)(PAL_Y + PAL_H)) {       /* palette */
        k = (unsigned char)(rx / SW_WB);
        if (k < 4) { pen = k; draw_toolchest(); }
        return 1;
    }
    if (my >= WID_Y && my < (unsigned char)(WID_Y + 8)) {           /* width -/+ */
        if (rx < TOOL_WB) { if (pen_w > 1) pen_w--; }
        else              { if (pen_w < 4) pen_w++; }
        draw_toolchest();
        return 1;
    }
    return 0;
}

static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my, cy;
    unsigned int px, cxl;

    if (flags & GB_QUIT) { gb_wm_close(); return; }

    if (flags & GB_CLICK) {                            /* discrete: title + toolchest */
        mx = gb_mx(); my = gb_my();
        if (my >= win_y && my < (unsigned char)(win_y + TITLE_H)) {
            if (mx >= win_x && mx < (unsigned char)(win_x + 5)) { gb_wm_close(); return; }
            if (mx >= (unsigned char)(win_x + 5) && mx < (unsigned char)(win_x + WIN_W)) {
                if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
                    gb_wm_setpos(win_x, win_y);
                    gb_restore_parent();
                    draw();
                }
            }
            return;
        }
        if (hit_toolchest(mx, my)) return;
    }

    if (!(flags & GB_FIRE)) return;                    /* continuous: canvas draw */
    if (tool != TOOL_PENCIL) return;                   /* shapes/fill/undo: Phase 4 */
    my = gb_my();
    if (my < CVY) return;
    cy = (unsigned char)(my - CVY);
    if (cy >= CANVAS_H) return;
    px = gb_mxp();
    cxl = (unsigned int)CVX * 4;                       /* canvas left, in pixels */
    if (px < cxl) return;
    px -= cxl;
    if (px < CANVAS_W) plot((unsigned char)px, cy);
}

static gb_win_t pwin = { DEF_X, DEF_Y, WIN_W, WIN_H, on_frame, on_repaint, 0, 0 };

void main(void)
{
    win_x = DEF_X;
    win_y = DEF_Y;
    pen = 2;
    tool = TOOL_PENCIL;
    pen_w = 1;
    canvas_clear();
    load_tools();
    gb_wm_add(&pwin);
    draw();
}
