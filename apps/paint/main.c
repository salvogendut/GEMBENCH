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
static unsigned char dirty;            /* unsaved edits -> " *" in the title    */

/* File menu (top bar). The kernel draws the "File" title while we are focused; a
   click delivers GB_MSG_MENU to on_menu, which arms want_menu for the main loop. */
#define FILE_COL 10
#define FILE_END 16
static unsigned char want_menu;        /* File title clicked -> run the menu */
static char fbase[14];                 /* "NAME.PIC" - the title base           */
static char wtitle[18];                /* fbase + " *" when dirty               */
static char name83[11];                /* current 8.3 file name (fs target)     */
static const unsigned char top_menu[] = {
    1, FILE_COL, 'F','i','l','e',0,0,0,0
};

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
    dirty = 1;
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
    dirty = 1;
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
    dirty = 1;
}

/* win_title: the window title = the file name, " *" appended when unsaved. */
static const char *win_title(void)
{
    unsigned char i = 0, j = 0;
    while (fbase[i]) wtitle[j++] = fbase[i++];
    if (dirty) { wtitle[j++] = ' '; wtitle[j++] = '*'; }
    wtitle[j] = 0;
    return wtitle;
}

/* full window redraw (frame + canvas + toolchest) */
static void draw(void)
{
    gb_curhide();
    gb_window(win_x, win_y, WIN_W, WIN_H, win_title());
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

/* to_83: "NAME.EXT" -> the 11-byte space-padded name83 (the fs target). */
static void to_83(const char *s)
{
    unsigned char i = 0, j;
    for (j = 0; j < 11; j++) name83[j] = ' ';
    while (s[i] && s[i] != '.' && i < 8) { name83[i] = s[i]; i++; }
    while (s[i] && s[i] != '.') i++;
    if (s[i] == '.') {
        i++;
        for (j = 0; j < 3 && s[i]; j++, i++) name83[8 + j] = s[i];
    }
}

/* ext_is_pic: does "NAME.EXT" end in .PIC ? */
static unsigned char ext_is_pic(const char *name)
{
    const char *e = name;
    while (*e && *e != '.') e++;
    return (unsigned char)(e[0] == '.' && e[1] == 'P' && e[2] == 'I' && e[3] == 'C');
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

/* ---- File menu actions ------------------------------------------------------ */
static char namebuf[16];               /* gb_prompt target for New / Save As */
/* ensure_pic_ext: a typed name with no '.' gets a ".PIC" default. */
static void ensure_pic_ext(void)
{
    unsigned char i = 0, has = 0;
    while (namebuf[i]) { if (namebuf[i] == '.') has = 1; i++; }
    if (!has && i && i <= 8) {
        namebuf[i++] = '.'; namebuf[i++] = 'P'; namebuf[i++] = 'I'; namebuf[i++] = 'C';
        namebuf[i] = 0;
    }
}

static void set_file(void)             /* namebuf -> current file name + title */
{
    ensure_pic_ext();
    to_83(namebuf);
    gb_set_name(name83);
    fmt83(fbase, name83);
}

static void do_save(void)
{
    picbuf[0] = 'G'; picbuf[1] = 'B'; picbuf[2] = 'P'; picbuf[3] = 'C';
    picbuf[4] = 2;                       /* version */
    picbuf[5] = 1;                       /* mode 1 (4 colours) */
    picbuf[6] = CANVAS_W; picbuf[7] = 0; /* width_px  = 100 */
    picbuf[8] = CANVAS_H; picbuf[9] = 0; /* height_px = 100 */
    picbuf[10] = pic_inks[0]; picbuf[11] = pic_inks[1];
    picbuf[12] = pic_inks[2]; picbuf[13] = pic_inks[3];
    if (gb_fs_save((char *)picbuf, PIC_LEN)) dirty = 0;
}

static void do_saveas(void)
{
    if (!gb_prompt("Save as:", namebuf, 12)) return;
    set_file();
    do_save();
}

static void do_new(void)
{
    canvas_clear();
    gb_set_name("UNTITLEDPIC");
    fmt83(fbase, "UNTITLEDPIC");
    dirty = 0;
}

/* do_load: list the .PIC files in a popup; load the one clicked. */
static void do_load(void)
{
    const char *names[24];
    static char store[24][14];
    char *p;
    unsigned char nn = 0, i, sel;
    unsigned int got;

    p = gb_dir1();
    while (p && nn < 24) {
        if (ext_is_pic(p)) {
            for (i = 0; i < 13 && p[i]; i++) store[nn][i] = p[i];
            store[nn][i] = 0;
            names[nn] = store[nn];
            nn++;
        }
        p = gb_dirn();
    }
    if (!nn) return;
    sel = gb_popup((unsigned char)(win_x + 2), CVY, names, nn);
    if (sel == 0xFF) return;
    to_83(store[sel]);
    gb_set_name(name83);
    fmt83(fbase, name83);
    got = gb_fs_load((char *)picbuf, PIC_MAX);   /* loads straight into the canvas body */
    if (!pic_valid(got)) canvas_clear();         /* not our format -> blank */
    dirty = 0;
}

static const char *const file_items[] = { "New", "Load", "Save", "Save As" };

static void run_menu(void)
{
    unsigned char sel = gb_popup(FILE_COL, 8, file_items, 4);
    if (sel == 0) do_new();
    else if (sel == 1) do_load();
    else if (sel == 2) do_save();
    else if (sel == 3) do_saveas();
}

/* on_menu: kernel callback on a top-bar click; arm the File menu for on_frame.
   Ignored while a dialog is up (gb_modal) so re-clicking File just closes it. */
static void on_menu(void)
{
    if (gb_msg.type != GB_MSG_MENU || gb_modal()) return;
    if (gb_msg.p0 >= FILE_COL && gb_msg.p0 < FILE_END) want_menu = 1;
}

static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my, cy;
    unsigned int px, cxl;

    if (flags & GB_QUIT) { gb_wm_close(); return; }

    if (want_menu) { want_menu = 0; run_menu(); draw(); return; }  /* File menu */

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

static gb_win_t pwin = { DEF_X, DEF_Y, WIN_W, WIN_H, on_frame, on_repaint, on_menu, top_menu };

void main(void)
{
    unsigned char i;
    char raw[11];

    win_x = DEF_X;
    win_y = DEF_Y;
    pen = 2;
    tool = TOOL_PENCIL;
    pen_w = 1;
    dirty = 0;
    want_menu = 0;
    undo_valid = 0;
    fire_prev = 0;
    canvas_clear();
    load_tools();                                /* PAINT.IST -> ist[] (sets fs name) */
    gb_wm_add(&pwin);                            /* register FIRST: captures our file arg */
    gb_get_name(raw);                            /* the .PIC we were launched with (or none) */
    fmt83(fbase, raw);
    if (!fbase[0]) {                             /* opened blank -> Untitled */
        fmt83(fbase, "UNTITLEDPIC");
        gb_set_name("UNTITLEDPIC");
    } else {                                     /* opened a .PIC -> load it into the canvas */
        gb_set_name(raw);
        if (!pic_valid(gb_fs_load((char *)picbuf, PIC_MAX))) canvas_clear();
    }
    for (i = 64; i; i--) if (!gb_getkey()) break;   /* drop buffered keys */
    draw();
}
