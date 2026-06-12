/*
 * PAINT.APP - a Mode-1 paint/drawing app (#114).
 *
 * The canvas is a Mode-1 bitmap BUFFER held here (the source of truth); tools do
 * pixel ops into it, and it's rendered to the screen with gb_restorerect (which
 * rides the kernel's blit_bitmap). Saving never reads the screen; on_repaint
 * re-blits the buffer so the drawing survives a window restack.
 *
 * Phase 1: window + canvas + freehand pencil.
 * Phase 3: the toolchest. The 5 tools (pencil/square/circle/fill/undo) are loaded
 *   at runtime from PAINT.IST - a normal ICONED-editable .IST set (24x24) - and
 *   blitted 2-per-row beside the canvas with the same gb_restorerect. A 4-ink
 *   palette and a pencil-width +/- sit below. Tool/ink/width selection is by click;
 *   only the pencil draws yet (shapes/fill/undo land in Phase 4).
 * Phase 2 (here): files. A top-bar "File" menu (New / Load / Save / Save As) and
 *   the .PIC format - a versioned header ("GBPC", v2: mode, width/height in px, a
 *   4-ink palette) then the raw Mode-1 canvas in one buffer, so Save
 *   and Load are a single gb_fs_save/gb_fs_load. The window title shows the file
 *   name (" *" when unsaved); the File Manager routes .PIC here.
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
static unsigned char winw = WIN_W, winh = WIN_H;   /* live window size (Fullscreen, #142) */
/* content origin (ox,oy): the window top-left normally, but CENTERED when the window is
   bigger than the content (Fullscreen). recalc_origin() refreshes it after any geometry
   change; drawing/hit-testing read the variables (cheap, vs a macro division everywhere). */
static unsigned char ox = DEF_X, oy = DEF_Y;
static void recalc_origin(void);                   /* defined below */
#define CVX  (unsigned char)(ox + 1)               /* canvas left, byte column */
#define CVY  (unsigned char)(oy + TITLE_H + 1)     /* canvas top, screen row   */
/* toolchest column: just right of the canvas */
#define TCX  (unsigned char)(CVX + CANVAS_WB + 1)  /* tools left, byte column  */
#define TCY  CVY                                    /* tools top = canvas top   */
#define PAL_Y (unsigned char)(TCY + 3 * TOOL_SY)    /* ink swatches below tools */
#define PAL_H 10
#define SW_WB 3                                      /* swatch width in bytes    */
#define WID_Y (unsigned char)(PAL_Y + PAL_H + 2)     /* pencil-width control row */

/* .PIC v2 = a 14-byte header then the Mode-1 canvas, all in one buffer so Save/Load
   are a single fs call (#114):
     0  "GBPC" magic     4  version = 2     5  mode = 1 (Mode-1, 4 colours)
     6  width_px (2, LE) 8  height_px (2, LE)
     10 inks[4]          pen 0..3 -> CPC hardware ink (the picture's palette)
     14 canvas bytes (width_px/4 stride * height rows)
   PIC_MAX rounds PIC_LEN up to a 512-byte sector for gb_fs_load. */
#define PIC_HDR  14
#define PIC_LEN  (PIC_HDR + CANVAS_WB * CANVAS_H)    /* 2514 */
#define PIC_MAX  2560                                 /* PIC_LEN -> whole sectors */
static unsigned char picbuf[PIC_MAX];
#define canvas (picbuf + PIC_HDR)                     /* the canvas body */
/* the GEOBENCH 4-pen palette (kernel set_palette): pen0..3 CPC hardware inks */
static const unsigned char pic_inks[4] = { 1, 26, 0, 6 };  /* blue, white, black, red */

static unsigned char pen = 2;          /* current ink: 0 blue 1 white 2 black 3 red */
static unsigned char tool = TOOL_PENCIL;
static unsigned char pen_w = 1;        /* pencil width 1..4                     */

/* window-title scratch: the file name (from gb_doc) + " *" when unsaved. */
static char fbase[14];                 /* "NAME.PIC" formatted from gb_doc_name() */
static char wtitle[18];                /* fbase + " *" when modified            */
static void fmt83(char *dst, const char *n11);   /* defined below; used by win_title */

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
    gb_doc_dirty();
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

/* ---- Phase 4: undo, flood fill, shapes (#114) ------------------------------- */
#define CANVAS_SZ (CANVAS_WB * CANVAS_H)
static unsigned char undo[CANVAS_SZ];   /* one-level snapshot (also the shape base) */
static unsigned char undo_valid;
static unsigned char fire_prev;         /* edge-detect the fire press                */

static void save_undo(void)             /* snapshot the canvas before an operation */
{
    unsigned int n;
    for (n = 0; n < CANVAS_SZ; n++) undo[n] = canvas[n];
    undo_valid = 1;
}
static void do_undo(void)               /* swap canvas <-> snapshot (so Undo redoes) */
{
    unsigned int n; unsigned char t;
    if (!undo_valid) return;
    for (n = 0; n < CANVAS_SZ; n++) { t = canvas[n]; canvas[n] = undo[n]; undo[n] = t; }
    blit_canvas();
}

/* read / write a canvas pixel's pen */
static unsigned char get_pen(unsigned char x, unsigned char y)
{
    unsigned char b = canvas[(unsigned int)y * CANVAS_WB + (x >> 2)], i = (unsigned char)(x & 3);
    return (unsigned char)(((b >> (7 - i)) & 1) | (((b >> (3 - i)) & 1) << 1));
}
static void cpix(unsigned char x, unsigned char y)            /* in-bounds set (fill) */
{
    unsigned int off = (unsigned int)y * CANVAS_WB + (x >> 2);
    canvas[off] = set_pixel(canvas[off], (unsigned char)(x & 3), pen);
}
static void cpset(int x, int y)                               /* bounds-checked (shapes) */
{
    if (x >= 0 && x < CANVAS_W && y >= 0 && y < CANVAS_H) {
        unsigned int off = (unsigned int)y * CANVAS_WB + ((unsigned int)x >> 2);
        canvas[off] = set_pixel(canvas[off], (unsigned char)(x & 3), pen);
    }
}

/* 4-connected scanline flood fill from (x,y). A bounded seed stack (drops seeds when
   full -> at worst a partial fill, never a crash). */
#define FILL_STK 256
static unsigned int fstk[FILL_STK];
static unsigned int fsp;
static void fpush(unsigned char x, unsigned char y)          /* pack as (y<<8)|x */
{
    if (fsp < FILL_STK) fstk[fsp++] = (unsigned int)((unsigned int)y << 8) | x;
}
static void flood_fill(unsigned char x, unsigned char y)
{
    unsigned char target = get_pen(x, y), xl, xr, xx, inside, fx, fy;
    unsigned int v;
    if (target == pen) return;
    fsp = 0; fpush(x, y);
    while (fsp) {
        v = fstk[--fsp]; fx = (unsigned char)(v & 0xFF); fy = (unsigned char)(v >> 8);
        if (get_pen(fx, fy) != target) continue;          /* already filled (dup seed) */
        xl = fx; while (xl > 0 && get_pen((unsigned char)(xl - 1), fy) == target) xl--;
        xr = fx; while (xr < CANVAS_W - 1 && get_pen((unsigned char)(xr + 1), fy) == target) xr++;
        for (xx = xl; xx <= xr; xx++) cpix(xx, fy);
        if (fy > 0) { inside = 0; for (xx = xl; xx <= xr; xx++)
            if (get_pen(xx, (unsigned char)(fy - 1)) == target) { if (!inside) { fpush(xx, (unsigned char)(fy - 1)); inside = 1; } } else inside = 0; }
        if (fy < CANVAS_H - 1) { inside = 0; for (xx = xl; xx <= xr; xx++)
            if (get_pen(xx, (unsigned char)(fy + 1)) == target) { if (!inside) { fpush(xx, (unsigned char)(fy + 1)); inside = 1; } } else inside = 0; }
    }
    gb_doc_dirty();
}

/* ---- shapes (outline, into the canvas buffer) ------------------------------- */
static int isqrt(unsigned int v) { unsigned int r = 0; while ((unsigned int)(r + 1) * (r + 1) <= v) r++; return (int)r; }

static void draw_rect(int x0, int y0, int x1, int y1)         /* rectangle outline */
{
    int x, y, t;
    if (x0 > x1) { t = x0; x0 = x1; x1 = t; }
    if (y0 > y1) { t = y0; y0 = y1; y1 = t; }
    for (x = x0; x <= x1; x++) { cpset(x, y0); cpset(x, y1); }
    for (y = y0; y <= y1; y++) { cpset(x0, y); cpset(x1, y); }
}
static void draw_circle(int cx, int cy, int r)               /* midpoint circle outline */
{
    int x = r, y = 0, err = 1 - r;
    if (r <= 0) { cpset(cx, cy); return; }
    while (x >= y) {
        cpset(cx + x, cy + y); cpset(cx - x, cy + y); cpset(cx + x, cy - y); cpset(cx - x, cy - y);
        cpset(cx + y, cy + x); cpset(cx - y, cy + x); cpset(cx + y, cy - x); cpset(cx - y, cy - x);
        y++; if (err < 0) err += 2 * y + 1; else { x--; err += 2 * (y - x) + 1; }
    }
}

/* rubber_band: drag a square/circle from (sx,sy); the outline previews against the
   pre-shape snapshot until release commits it. */
static void rubber_band(unsigned char sx, unsigned char sy)
{
    unsigned char cx = sx, cy = sy, ncx, ncy, my, first = 1, fl;
    unsigned int px, n, cxl = (unsigned int)CVX * 4;
    save_undo();                                          /* base = pre-shape + undo */
    for (;;) {
        fl = gb_poll();
        if (!(fl & GB_FIRE)) break;                       /* release -> commit */
        my = gb_my();
        ncy = (my < CVY) ? 0 : (unsigned char)(my - CVY); if (ncy >= CANVAS_H) ncy = CANVAS_H - 1;
        px = gb_mxp();
        if (px < cxl) ncx = 0; else { px -= cxl; ncx = (px >= CANVAS_W) ? CANVAS_W - 1 : (unsigned char)px; }
        if (first || ncx != cx || ncy != cy) {
            first = 0; cx = ncx; cy = ncy;
            for (n = 0; n < CANVAS_SZ; n++) canvas[n] = undo[n];   /* restore base */
            if (tool == TOOL_SQUARE) draw_rect(sx, sy, cx, cy);
            else { int dx = (int)cx - sx, dy = (int)cy - sy;
                   draw_circle(sx, sy, isqrt((unsigned int)(dx * dx + dy * dy))); }
            blit_canvas();
        }
    }
    gb_doc_dirty();
}

/* win_title: the window title = the file name, " *" appended when unsaved. */
static const char *win_title(void)
{
    /* name from the framework (gb_doc); single-index copy - the two-index form is
       miscompiled by SDCC under --fomit-frame-pointer (#142). */
    unsigned char j = 0;
    char c;
    fmt83(fbase, gb_doc_name());
    while ((c = fbase[j]) != 0) { wtitle[j] = c; j++; }
    if (gb_doc_modified()) { wtitle[j++] = ' '; wtitle[j++] = '*'; }
    wtitle[j] = 0;
    return wtitle;
}

/* full window redraw (frame + canvas + toolchest) */
static void draw(void)
{
    recalc_origin();
    gb_curhide();
    gb_window(win_x, win_y, winw, winh, win_title());
    gb_curshow();
    blit_canvas();
    draw_toolchest();
}

/* recalc_origin: refresh the centered content origin from the live geometry. */
static void recalc_origin(void)
{
    ox = (unsigned char)(win_x + (winw - WIN_W) / 2);
    oy = (unsigned char)(win_y + (winh - WIN_H) / 2);
}

/* p_fullscreen: View > Fullscreen - cover the screen (canvas + tools recenter) and back;
 * restoring repaints the desktop we vacated. */
static void p_fullscreen(unsigned char on)
{
    if (on) { win_x = 0; win_y = 8; winw = 80; winh = 192; }
    else    { win_x = DEF_X; win_y = DEF_Y; winw = WIN_W; winh = WIN_H; }
    recalc_origin();
    gb_wm_setpos(win_x, win_y);
    gb_wm_setsize(winw, winh);
    if (!on) gb_restore_parent();
    draw();
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
            if (k == TOOL_UNDO) do_undo();          /* undo is an action, not a mode */
            else if (k < N_TOOLS) { tool = k; draw_toolchest(); }
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

/* ---- file name helpers ------------------------------------------------------ */
/* fmt83: 11-byte space-padded 8.3 name -> "NAME.EXT" display string. */
static void fmt83(char *dst, const char *n11)
{
    unsigned char i, j = 0;
    for (i = 0; i < 8 && n11[i] != ' '; i++) dst[j++] = n11[i];
    if (n11[8] != ' ') {
        dst[j++] = '.';
        for (i = 8; i < 11 && n11[i] != ' '; i++) dst[j++] = n11[i];
    }
    dst[j] = 0;
}

/* pic_valid: does picbuf hold a v2 "GBPC" header for our 100x100 canvas? */
static unsigned char pic_valid(unsigned int got)
{
    return (unsigned char)(got >= PIC_LEN &&
        picbuf[0] == 'G' && picbuf[1] == 'B' && picbuf[2] == 'P' && picbuf[3] == 'C' &&
        picbuf[4] == 2 &&                              /* version 2 */
        picbuf[6] == CANVAS_W && picbuf[7] == 0 &&     /* width_px  = 100 */
        picbuf[8] == CANVAS_H && picbuf[9] == 0);      /* height_px = 100 */
}

/* ---- the document, via the gb_doc framework (#142) -------------------------- *
 * The document IS picbuf (the .PIC buffer). The framework owns the File menu and the
 * navigable Open/Save dialog; we provide three hooks. */
static const char *const paint_exts[] = { "PIC", 0 };

/* p_new: New -> blank canvas (the framework sets the name to UNTITLED + clears dirty). */
static void p_new(void) { canvas_clear(); }

/* p_open: a .PIC was just loaded into picbuf. Paint edits 100x100 only; a picture that
 * is the wrong size or too big to load (gb_fs_load refuses files > picbuf) alerts the
 * user instead of silently blanking. */
static const char *const toobig_msg[] = { "Picture must be 100x100" };
static void p_open(unsigned int got)
{
    if (pic_valid(got)) return;
    canvas_clear();
    gb_popup(10, 40, toobig_msg, 1);   /* one-line alert; click/Esc to dismiss */
}

/* p_save: stamp the .PIC header into picbuf and return the byte count to write. */
static unsigned int p_save(void)
{
    picbuf[0] = 'G'; picbuf[1] = 'B'; picbuf[2] = 'P'; picbuf[3] = 'C';
    picbuf[4] = 2;                       /* version */
    picbuf[5] = 1;                       /* mode 1 (4 colours) */
    picbuf[6] = CANVAS_W; picbuf[7] = 0; /* width_px  = 100 */
    picbuf[8] = CANVAS_H; picbuf[9] = 0; /* height_px = 100 */
    picbuf[10] = pic_inks[0]; picbuf[11] = pic_inks[1];
    picbuf[12] = pic_inks[2]; picbuf[13] = pic_inks[3];
    return PIC_LEN;
}

static const gb_doc_t pdoc = {
    (char *)picbuf, PIC_MAX, p_new, p_open, p_save, 0, 0, 0, 0, paint_exts,
    0, 0, p_fullscreen, 0, 0
};

/* on_menu: a top-bar title was clicked -> hand it to the framework. */
static void on_menu(void) { gb_doc_event(); }

static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my, cy;
    unsigned int px, cxl;

    if (flags & GB_QUIT) { gb_wm_close(); return; }

    if (gb_doc_frame()) { draw(); return; }            /* a File menu ran (#142) */

    if (flags & GB_CLICK) {                            /* discrete: title + toolchest */
        mx = gb_mx(); my = gb_my();
        if (my >= win_y && my < (unsigned char)(win_y + TITLE_H)) {
            if (mx >= win_x && mx < (unsigned char)(win_x + 5)) { if (gb_doc_close()) gb_wm_close(); return; }
            if (mx >= (unsigned char)(win_x + 5) && mx < (unsigned char)(win_x + winw)) {
                if (gb_drag_window(&win_x, &win_y, winw, winh)) {
                    gb_wm_setpos(win_x, win_y);
                    gb_restore_parent();
                    draw();
                }
            }
            return;
        }
        if (hit_toolchest(mx, my)) return;
    }

    if (!(flags & GB_FIRE)) { fire_prev = 0; return; }   /* canvas drawing */
    my = gb_my();
    if (my < CVY) { fire_prev = 1; return; }
    cy = (unsigned char)(my - CVY);
    if (cy >= CANVAS_H) { fire_prev = 1; return; }
    px = gb_mxp();
    cxl = (unsigned int)CVX * 4;                       /* canvas left, in pixels */
    if (px < cxl) { fire_prev = 1; return; }
    px -= cxl;
    if (px >= CANVAS_W) { fire_prev = 1; return; }
    if (tool == TOOL_PENCIL) {                         /* continuous freehand */
        if (!fire_prev) save_undo();                   /* once, at the stroke start */
        plot((unsigned char)px, cy);
    } else if (!fire_prev) {                           /* fill / shapes: once per press */
        if (tool == TOOL_FILL) { save_undo(); flood_fill((unsigned char)px, cy); blit_canvas(); }
        else if (tool == TOOL_SQUARE || tool == TOOL_CIRCLE) rubber_band((unsigned char)px, cy);
    }
    fire_prev = 1;
}

static gb_win_t pwin = { DEF_X, DEF_Y, WIN_W, WIN_H, on_frame, on_repaint, on_menu, 0 };

void main(void)
{
    unsigned char i;

    win_x = DEF_X;
    win_y = DEF_Y;
    pen = 2;
    tool = TOOL_PENCIL;
    pen_w = 1;
    undo_valid = 0;
    fire_prev = 0;
    canvas_clear();
    load_tools();                                /* PAINT.IST -> ist[] (sets fs name) */
    gb_wm_add(&pwin);                            /* register FIRST: captures our file arg */
    gb_doc(&pdoc);                               /* standard File menu; adopts the launch name */
    /* load the launch .PIC (gb_fs_load returns 0 if launched blank -> invalid -> clear) */
    if (!pic_valid(gb_fs_load((char *)picbuf, PIC_MAX))) canvas_clear();
    for (i = 64; i; i--) if (!gb_getkey()) break;   /* drop buffered keys */
    draw();
}
