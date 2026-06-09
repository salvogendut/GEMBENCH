/* iconed - the GEOBENCH icon / cursor editor (C), pointer-driven (#70).
 *
 * A split-window pixel editor: the left pane is the current icon/cursor magnified
 * 4x (one bitmap pixel = a 1-byte x 4-px screen cell); the right pane is a palette
 * of the 4 Mode-1 pens (cursors swap pen 0 for a "transparent" brush) plus Prev/
 * Next to cycle the icons in a set. Pick a colour, click a cell to paint it (pen 0
 * erases). The kernel-drawn "File" menu does Load / Save.
 *
 * Two file types, told apart by content (no filename needed):
 *   .IST icon set  - "GBIS" header, a directory, then each icon's bitmap. Edited in
 *                    place (never resized); Prev/Next walk the set.
 *   .SPR cursor    - 256 bytes = d0,m0,d2,m2 (a 16x16 masked sprite in two pre-
 *                    shifted phases). We edit phase 0 and regenerate phase 2 (the
 *                    +2px shift the kernel uses for sub-byte positioning) on Save.
 * The Mode-1 bit packing / mask / shift math matches tools/packicons.py +
 * tools/png2spr.py and is round-trip-checked by tools/test_iconed_codec.py.
 *
 * Issue #45: a co-resident window like Notepad - main() loads the file, registers
 * via gb_wm_add and returns; the kernel WM loop drives on_frame / ie_repaint. The
 * File menu and its Load popup poll themselves (modal). */
#include "gb.h"

#define DEF_X     2
#define DEF_Y     14
#define WIN_W     46           /* bytes (4px) */
#define WIN_H     160          /* px */
#define TITLE_H   14
#define CELL_H    4            /* screen px per bitmap row (4x zoom; 1 byte wide)   */

/* live (draggable) window-relative geometry */
#define CANVAS_X  (win_x + 1)
#define CANVAS_Y0 (win_y + 16)
#define PANEL_X   (win_x + 34)

#define SW_W      4            /* palette swatch: 4 bytes x 10 px, 13 px pitch */
#define SW_H      10
#define SW_STEP   13
#define SW_Y      (CANVAS_Y0 + 8)
#define NAV_Y     (SW_Y + 4 * SW_STEP + 4)
#define PREV_X    PANEL_X            /* left-triangle button  */
#define NEXT_X    (PANEL_X + 4)      /* right-triangle button */
#define NAV_BW    3                  /* button width (bytes); height = NAV_BH */
#define NAV_BH    9
#define UNDO_X    PANEL_X            /* UNDO button */
#define UNDO_Y    (NAV_Y + NAV_BH + 12)
#define UNDO_W    7
#define UNDO_H    9

#define MENU_COL  10           /* "File" title column in the top bar (matches notepad) */
#define MENU_END  16

/* BUFSZ holds the whole file. gb_fs_load copies in WHOLE 512-byte sectors and is
   ALSO passed as fs_load_max, so a file bigger than BUFSZ is refused (the load is
   not partial) - so this must cover the largest icon set (#110). The icon-set
   ceiling is DATA_MODTOP-DATA_ICONS-#200 = 6656 -> 13 sectors; 7168 = 14 sectors
   covers any DEFAULT.IST. (Was 4096, which the now-5216-byte DEFAULT.IST exceeds.) */
#define BUFSZ     7168
#define CUR_W     4            /* cursor: 4 bytes/row x 16 rows, phase = 64 bytes */
#define CUR_H     16
#define PHASE     64

#define M_ICON    0
#define M_CURSOR  1
#define M_NONE    0xFF

static unsigned char win_x = DEF_X, win_y = DEF_Y;
static unsigned char buf[BUFSZ];
static unsigned int  filelen;
static unsigned char mode;                 /* M_ICON / M_CURSOR / M_NONE          */
static unsigned char grid[32][32];         /* [row][col] pen 0..3 (cursor 0=clear) */
static unsigned char gw, gh;               /* current item size in pixels          */
static unsigned char count, idx;           /* icon-set count + current index       */
static unsigned char selpen;               /* selected palette pen 0..3            */
static unsigned char want_menu;            /* File title clicked -> run the menu     */
static unsigned char status;               /* 0 none, 1 saved, 2 failed            */
static char fbase[14];                     /* "NAME.EXT" of the open file (title)   */
static unsigned char u_valid, u_cx, u_cy, u_pen;  /* single-level undo of last paint */

static const unsigned char file_menu[] = { 1, MENU_COL, 'F','i','l','e',0,0,0,0 };

/* ---- Mode-1 pixel packing (pixel i: bit0 @ 7-i, bit1 @ 3-i) ------------------ */

static unsigned char dec_pixel(unsigned char b, unsigned char i)
{
    return (unsigned char)(((b >> (7 - i)) & 1) | (((b >> (3 - i)) & 1) << 1));
}

static unsigned char set_pixel(unsigned char b, unsigned char i, unsigned char pen)
{
    if (pen & 1) b |= (unsigned char)(1 << (7 - i));
    if (pen & 2) b |= (unsigned char)(1 << (3 - i));
    return b;
}

/* ---- .IST icon set ---------------------------------------------------------- */

static unsigned int  icon_off;
static unsigned char icon_wb, icon_h;

static void icon_dir(unsigned char k)      /* read directory entry k -> off/wb/h */
{
    unsigned int p = 16 + (unsigned int)k * 4;
    icon_off = (unsigned int)buf[p] | ((unsigned int)buf[p + 1] << 8);
    icon_wb  = buf[p + 2];
    icon_h   = buf[p + 3];
}

static void decode_icon(unsigned char k)
{
    unsigned char y, bx, i, b;
    u_valid = 0;                            /* a fresh icon -> nothing to undo */
    icon_dir(k);
    gw = (unsigned char)(icon_wb * 4);
    gh = icon_h;
    for (y = 0; y < icon_h; y++)
        for (bx = 0; bx < icon_wb; bx++) {
            b = buf[icon_off + (unsigned int)y * icon_wb + bx];
            for (i = 0; i < 4; i++) grid[y][bx * 4 + i] = dec_pixel(b, i);
        }
}

static void encode_icon(unsigned char k)   /* current grid -> buf at icon k */
{
    unsigned char y, bx, i, b;
    icon_dir(k);
    for (y = 0; y < icon_h; y++)
        for (bx = 0; bx < icon_wb; bx++) {
            b = 0;
            for (i = 0; i < 4; i++) b = set_pixel(b, i, grid[y][bx * 4 + i]);
            buf[icon_off + (unsigned int)y * icon_wb + bx] = b;
        }
}

/* ---- .SPR cursor (16x16, masked, two pre-shifted phases) -------------------- */

static void decode_cursor(void)            /* phase 0 (d0 @0, m0 @PHASE) -> grid */
{
    unsigned char y, bx, i, d, m;
    u_valid = 0;
    gw = 16; gh = 16;
    for (y = 0; y < CUR_H; y++)
        for (bx = 0; bx < CUR_W; bx++) {
            d = buf[(unsigned int)y * CUR_W + bx];
            m = buf[PHASE + (unsigned int)y * CUR_W + bx];
            for (i = 0; i < 4; i++)
                grid[y][bx * 4 + i] = ((m >> (7 - i)) & 1) ? 0 : dec_pixel(d, i);
        }
}

static void enc_cursor_phase(unsigned char shift, unsigned int db, unsigned int mb)
{
    unsigned char y, bx, i, d, m, pen;
    int x;
    for (y = 0; y < CUR_H; y++)
        for (bx = 0; bx < CUR_W; bx++) {
            d = 0; m = 0;
            for (i = 0; i < 4; i++) {
                x = bx * 4 + i - shift;            /* source pixel for this column */
                pen = (x >= 0 && x < 16) ? grid[y][x] : 0;
                if (pen == 0) m = set_pixel(m, i, 3);   /* transparent: mask both bits */
                else          d = set_pixel(d, i, pen);
            }
            buf[db + (unsigned int)y * CUR_W + bx] = d;
            buf[mb + (unsigned int)y * CUR_W + bx] = m;
        }
}

static void encode_cursor(void)
{
    enc_cursor_phase(0, 0,         PHASE);          /* d0, m0 */
    enc_cursor_phase(2, 2 * PHASE, 3 * PHASE);      /* d2, m2 (the +2px phase) */
}

/* sniff: classify the loaded buffer and decode the first item. */
static void sniff(void)
{
    if (filelen >= 16 && buf[0] == 'G' && buf[1] == 'B' && buf[2] == 'I' &&
        buf[3] == 'S' && buf[4] == 2) {
        mode = M_ICON; count = buf[5]; idx = 0;
        if (count == 0) { mode = M_NONE; return; }
        decode_icon(0);
    } else if (filelen == 256) {
        mode = M_CURSOR; count = 1; idx = 0;
        decode_cursor();
    } else {
        mode = M_NONE;
    }
}

/* ---- drawing ---------------------------------------------------------------- */

static char numbuf[8];
static void fmt_idx(void)                  /* "idx+1/count" */
{
    unsigned char a = idx + 1, b = count, p = 0;
    if (a >= 10) numbuf[p++] = '0' + a / 10;
    numbuf[p++] = '0' + a % 10;
    numbuf[p++] = '/';
    if (b >= 10) numbuf[p++] = '0' + b / 10;
    numbuf[p++] = '0' + b % 10;
    numbuf[p] = 0;
}

static void draw_canvas(void)
{
    unsigned char x, y;
    if (mode == M_NONE) { gb_text(CANVAS_X, CANVAS_Y0, "Empty - File>Load"); return; }
    for (y = 0; y < gh; y++)
        for (x = 0; x < gw; x++)
            gb_fill(CANVAS_X + x, CANVAS_Y0 + y * CELL_H, 1, CELL_H, grid[y][x]);
    gb_frame(CANVAS_X, CANVAS_Y0, gw, gh * CELL_H, 2);
}

static void draw_palette(void)
{
    unsigned char k, y;
    if (mode == M_NONE) return;
    for (k = 0; k < 4; k++) {
        y = SW_Y + k * SW_STEP;
        gb_fill(PANEL_X, y, SW_W, SW_H, k);      /* pen k (k 0 = bg/erase) */
        if (mode == M_CURSOR && k == 0)          /* mark the transparent brush */
            gb_text(PANEL_X + 1, y + 1, "T");
        gb_frame(PANEL_X, y, SW_W, SW_H, 2);     /* black outline (so pen 0 shows) */
        gb_frame(PANEL_X - 1, y - 1, SW_W + 2, SW_H + 2, (k == selpen) ? 3 : 0);
    }
}

static void draw_nav(void)
{
    if (mode != M_ICON || count <= 1) return;
    gb_textk(PREV_X, NAV_Y, GLYPH_TRI_LEFT);    /* crisp black triangles (font glyphs) */
    gb_textk(NEXT_X, NAV_Y, GLYPH_TRI_RIGHT);
    fmt_idx();
    gb_text(PREV_X, NAV_Y + NAV_BH + 2, numbuf);
}

static void draw_undo(void)
{
    if (mode == M_NONE) return;
    gb_frame(UNDO_X, UNDO_Y, UNDO_W, UNDO_H, 1);
    gb_text(UNDO_X, UNDO_Y + 1, "UNDO");
}

static void status_line(void)
{
    gb_text(win_x + 1, win_y + WIN_H - 11,
            status == 1 ? "saved" :
            status == 2 ? "SAVE FAILED" :
                          "Pick a pen, click to paint");
}

static void draw(void)
{
    gb_window(win_x, win_y, WIN_W, WIN_H, fbase[0] ? fbase : "ICONED");
    draw_canvas();
    draw_palette();
    draw_nav();
    draw_undo();
    status_line();
}

/* ---- file menu (kernel-drawn top bar; popup pattern from notepad) ------------ */

static void on_menu(void)
{
    if (gb_msg.type != GB_MSG_MENU || gb_modal()) return;   /* ignore clicks while modal */
    if (gb_msg.p0 < MENU_COL || gb_msg.p0 >= MENU_END) return;
    want_menu = 1;
}

/* 8.3 helpers + extension test, like notepad's to_83. */
static char name83[11];
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

/* fmt83: 11-byte space-padded 8.3 name -> "NAME.EXT" display string (window title). */
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

/* is_editable: name (NAME.EXT) ends in .IST or .SPR (case as stored). */
static unsigned char is_editable(const char *s)
{
    unsigned char i = 0;
    while (s[i] && s[i] != '.') i++;
    if (!s[i]) return 0;
    i++;
    return (unsigned char)((s[i] == 'I' && s[i+1] == 'S' && s[i+2] == 'T') ||
                           (s[i] == 'S' && s[i+1] == 'P' && s[i+2] == 'R'));
}

static void do_load(void)
{
    const char *names[12];
    static char store[12][14];
    char *p;
    unsigned char n = 0, i, sel;

    p = gb_dir1();
    while (p && n < 12) {
        if (is_editable(p)) {
            for (i = 0; i < 13 && p[i]; i++) store[n][i] = p[i];
            store[n][i] = 0;
            names[n] = store[n];
            n++;
        }
        p = gb_dirn();
    }
    if (!n) return;
    sel = gb_popup(win_x + 6, win_y + 16, names, n);
    if (sel == 0xFF) return;
    to_83(store[sel]);
    gb_set_name(name83);
    fmt83(fbase, name83);                /* title -> the opened file's name */
    filelen = gb_fs_load(buf, BUFSZ);
    sniff();
    selpen = (mode == M_CURSOR) ? 1 : 1;
    status = 0;
}

static void do_save(void)
{
    if (mode == M_ICON)        { encode_icon(idx); status = gb_fs_save(buf, filelen) ? 1 : 2; }
    else if (mode == M_CURSOR) { encode_cursor();  status = gb_fs_save(buf, 256)     ? 1 : 2; }
    else                       { status = 2; }
}

static const char *const file_items[] = { "Load", "Save" };

static void run_menu(void)
{
    unsigned char sel = gb_popup(MENU_COL, 8, file_items, 2);
    if (sel == 0) do_load();
    else if (sel == 1) do_save();
}

/* ---- WM callbacks ----------------------------------------------------------- */

static void ie_repaint(void)
{
    gb_curhide();
    draw();
    gb_curshow();
}

static void cell_redraw(unsigned char cx, unsigned char cy)
{
    gb_curhide();
    gb_fill(CANVAS_X + cx, CANVAS_Y0 + cy * CELL_H, 1, CELL_H, grid[cy][cx]);
    gb_curshow();
}

static void paint_cell(unsigned char cx, unsigned char cy)
{
    u_cx = cx; u_cy = cy;                 /* remember for UNDO */
    u_pen = grid[cy][cx];
    u_valid = 1;
    grid[cy][cx] = selpen;
    cell_redraw(cx, cy);
}

/* do_undo: restore the last painted cell's previous pen. Swaps, so pressing UNDO
   again redoes the change (single-level undo/redo of the last paint). */
static void do_undo(void)
{
    unsigned char t;
    if (!u_valid) return;
    t = grid[u_cy][u_cx];
    grid[u_cy][u_cx] = u_pen;
    u_pen = t;
    cell_redraw(u_cx, u_cy);
}

static void switch_icon(unsigned char next)
{
    encode_icon(idx);                       /* keep edits to the icon we're leaving */
    if (next) idx = (idx + 1 == count) ? 0 : idx + 1;
    else      idx = (idx == 0) ? count - 1 : idx - 1;
    decode_icon(idx);
    gb_curhide();
    gb_fill(CANVAS_X, CANVAS_Y0, 32, 128, 0);   /* repaint ONLY the icon area + the */
    draw_canvas();                              /* index counter, not the whole window */
    gb_fill(PREV_X, NAV_Y + NAV_BH + 2, 8, 8, 0);
    fmt_idx();
    gb_text(PREV_X, NAV_Y + NAV_BH + 2, numbuf);
    gb_curshow();
}

static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my, k, y;

    if (flags & GB_QUIT) { gb_wm_close(); return; }
    if (want_menu) { want_menu = 0; run_menu(); gb_curhide(); draw(); gb_curshow(); return; }
    if (!(flags & GB_CLICK)) return;

    mx = gb_mx(); my = gb_my();

    if (my >= win_y && my < win_y + TITLE_H) {        /* title bar */
        if (mx >= win_x && mx < win_x + 5) { gb_wm_close(); return; }   /* close */
        if (mx >= win_x + 5 && mx < win_x + WIN_W) {                    /* drag  */
            if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
                gb_wm_setpos(win_x, win_y);
                gb_restore_parent();
            }
        }
        return;
    }

    if (mode != M_NONE &&                              /* canvas paint */
        mx >= CANVAS_X && mx < CANVAS_X + gw &&
        my >= CANVAS_Y0 && my < CANVAS_Y0 + gh * CELL_H) {
        paint_cell((unsigned char)(mx - CANVAS_X),
                   (unsigned char)((my - CANVAS_Y0) / CELL_H));
        return;
    }

    if (mode != M_NONE && mx >= PANEL_X && mx < PANEL_X + SW_W) {       /* palette */
        for (k = 0; k < 4; k++) {
            y = SW_Y + k * SW_STEP;
            if (my >= y && my < y + SW_H) {
                selpen = k;
                gb_curhide(); draw_palette(); gb_curshow();
                return;
            }
        }
    }

    if (mode == M_ICON && count > 1 &&                 /* Prev / Next buttons */
        my >= NAV_Y && my < NAV_Y + NAV_BH) {
        if (mx >= PREV_X && mx < PREV_X + NAV_BW)      switch_icon(0);
        else if (mx >= NEXT_X && mx < NEXT_X + NAV_BW) switch_icon(1);
        return;
    }

    if (mode != M_NONE &&                              /* UNDO button */
        my >= UNDO_Y && my < UNDO_Y + UNDO_H &&
        mx >= UNDO_X && mx < UNDO_X + UNDO_W) {
        do_undo();
    }
}

static const gb_win_t iewin = {
    DEF_X, DEF_Y, WIN_W, WIN_H, on_frame, ie_repaint, on_menu, file_menu
};

void main(void)
{
    unsigned char n;

    char raw[11];
    win_x = DEF_X; win_y = DEF_Y;
    gb_wm_add(&iewin);                       /* register first: captures our file arg */
    gb_get_name(raw);                        /* the file we were launched with -> title */
    fmt83(fbase, raw);
    filelen = gb_fs_load(buf, BUFSZ);
    selpen = 1; want_menu = 0; status = 0;
    sniff();
    for (n = 64; n; n--) if (!gb_getkey()) break;

    draw();
    gb_curshow();
}
