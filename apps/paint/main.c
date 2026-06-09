/*
 * PAINT.APP - a Mode-1 paint/drawing app (#114).
 *
 * The canvas is a Mode-1 bitmap BUFFER held here (the source of truth); tools do
 * pixel ops into it, and it's rendered to the screen with gb_restorerect (which
 * rides the kernel's blit_bitmap). Saving never reads the screen; on_repaint
 * re-blits the buffer so the drawing survives a window restack. Phase 1: window +
 * canvas + freehand pencil (width 1). Toolchest / palette / New-Load-Save / shapes
 * come in later phases.
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
#define WIN_W     (CANVAS_WB + 13)      /* canvas + (future) toolchest, in bytes */
#define WIN_H     (TITLE_H + CANVAS_H + 4)

#define WHITE_BYTE 0xF0                 /* 4 px of pen 1 (white) - the blank canvas */

static unsigned char win_x = DEF_X, win_y = DEF_Y;
/* live (draggable) window-relative geometry */
#define CVX  (unsigned char)(win_x + 1)            /* canvas left, byte column */
#define CVY  (unsigned char)(win_y + TITLE_H + 1)  /* canvas top, screen row   */

static unsigned char canvas[CANVAS_WB * CANVAS_H];
static unsigned char pen = 2;          /* current ink: black (#114 Phase 3 = palette) */

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

/* plot one canvas pixel (cx,cy) with the current pen, then re-blit its row */
static void plot(unsigned char cx, unsigned char cy)
{
    unsigned int off = (unsigned int)cy * CANVAS_WB + (cx >> 2);
    canvas[off] = set_pixel(canvas[off], (unsigned char)(cx & 3), pen);
    blit_row(cy);
}

/* full window redraw (frame + canvas) */
static void draw(void)
{
    gb_curhide();
    gb_window(win_x, win_y, WIN_W, WIN_H, "PAINT");   /* Phase 2: show the filename */
    gb_curshow();
    blit_canvas();
}

static void on_repaint(void) { draw(); }

static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my, cy;
    unsigned int px, cxl;

    if (flags & GB_QUIT) { gb_wm_close(); return; }

    if (flags & GB_CLICK) {                            /* discrete: title bar */
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
    }

    if (!(flags & GB_FIRE)) return;                    /* continuous: canvas draw */
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
    canvas_clear();
    gb_wm_add(&pwin);
    draw();
}
