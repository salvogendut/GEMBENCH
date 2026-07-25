/* iconed - the GEOBENCH icon / cursor editor (C), pointer-driven (#70).
 *
 * A split-window pixel editor: the left pane is the current icon/cursor magnified
 * 4x (one bitmap pixel = a 1-byte x 4-px screen cell); the right pane is a palette
 * of the 4 Mode-1 pens (cursors swap pen 0 for a "transparent" brush) plus Prev/
 * Next to cycle the icons in a set. Pick a colour, click a cell to paint it (pen 0
 * erases). The kernel-drawn "File" menu does Load / Save.
 *
 * Three file types, told apart by content (no filename needed):
 *   .IST icon set  - "GBIS" header, a directory, then each icon's bitmap. Edited in
 *                    place (never resized); Prev/Next walk the set.
 *   .APP application - optional "GBAP" v1 executable preamble containing one
 *                    canonical 32x32 icon. The executable tail is preserved.
 *   .SPR cursor    - on CPC/PCW, a 256-byte sprite: two pre-shifted phases
 *                    (shift 0, shift 2) with mask,data INTERLEAVED per column.
 *                    Shipped files may append the low-RAM helper through byte 512;
 *                    we edit the sprite and preserve that tail. On MSX2, a strict
 *                    66-byte V9938 hardware sprite (hotspot + outline + fill
 *                    planes). Both match png2spr.py.
 * The bit packing / mask / shift math matches tools/packicons.py + tools/png2spr.py
 * and is round-trip-checked by tools/test_iconed_codec.py.
 *
 * #146: a kernel-MANAGED window like Notepad - the WM owns the frame/title/close/drag;
 * main() registers (gb_wm_managed), loads the file, paints once via gb_restore_parent. The
 * kernel calls ie_draw / ie_frame / ie_click / ie_drag / ie_close. The File menu and its
 * Load popup poll themselves (modal). */
#include "gb.h"

#define DEF_X     2
#define DEF_Y     14
#define WIN_W     46           /* bytes (4px) */
#define WIN_H     160          /* px */
#define TITLE_H   14
#define CELL_H    4            /* screen px per bitmap row (4x zoom; 1 byte wide)   */

/* live (draggable) window-relative geometry */
#define CANVAS_X  (ox + 1)
#define CANVAS_Y0 (oy + 16)
#define PANEL_X   (ox + 34)

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

/* BUFSZ holds the whole file. gb_fs_load copies in WHOLE 512-byte sectors and is
   ALSO passed as fs_load_max, so a file bigger than BUFSZ is refused (the load is
   not partial) - so this must cover the largest icon set (#110). The icon-set
   ceiling is DATA_MODTOP-DATA_ICONS-#200 = 6656 -> 13 sectors; 7168 = 14 sectors
   covers any DEFAULT.IST. (Was 4096, which the now-5216-byte DEFAULT.IST exceeds.) */
#define BUFSZ     6656         /* 13 sectors - covers DEFAULT.IST (6256 -> 6656 loaded) and most sets. Restored
                                  from 6144 once the grid was packed 4px/byte (freed 768 B), so
                                  loading the default set and Fullscreen both fit again (#142). */
#define CUR_W     4            /* cursor: 4 bytes/row x 16 rows, phase = 64 bytes */
#define CUR_H     16
#define PHASE     64
#ifdef GB_MSX2
#define CURSOR_LEN 66          /* MSX2: V9938 hardware sprite (hotspot + 2 planes) */
#define CURSOR_FILE_MAX CURSOR_LEN
#else
#define CURSOR_LEN 256         /* CPC: 2 interleaved, pre-shifted masked phases */
#define CURSOR_FILE_MAX 512    /* shipped CPC/PCW files append PICEDITL at +256 */
#endif

#define M_ICON    0
#define M_CURSOR  1
#define M_APP     2
#define M_NONE    0xFF
#define APPICON_OFF 16
#define APPICON_WB  8
#define APPICON_H   32
#define APPICON_LEN (APPICON_WB * APPICON_H)
#define BTN_NONE  0
#define BTN_PREV  1
#define BTN_NEXT  2
#define BTN_UNDO  3
#define UI_MODAL_K (*(volatile unsigned char *)0x1705)

static unsigned char win_x = DEF_X, win_y = DEF_Y;
static unsigned char winw = WIN_W, winh = WIN_H;   /* live window size (Fullscreen, #142) */
static unsigned char ox = DEF_X, oy = DEF_Y;       /* content origin (centered when bigger) */
static void recalc_origin(void);                   /* defined below */
static unsigned char buf[BUFSZ];
static unsigned int  filelen;
static unsigned char mode;                 /* M_ICON / M_CURSOR / M_NONE          */
/* The edit grid: up to 32x32 pixels, pen 0..3 each. Packed 4 pixels/byte (2 bits
   each) so a 32x32 icon is 256 B not 1024 - that headroom is what lets BUFSZ cover
   DEFAULT.IST (6656) AND keep Fullscreen (#142). Use gget/gset, never index direct. */
static unsigned char grid[32][8];          /* [row][col>>2]; 2 bits per pixel */
static unsigned char gw, gh;               /* current item size in pixels          */
static unsigned char count, idx;           /* icon-set count + current index       */
static unsigned char selpen;               /* selected palette pen 0..3            */
static char fbase[14];                     /* "NAME.EXT" from gb_doc_name() (title) */
static char wtitle[18];                    /* fbase + " *" when modified           */
static unsigned char u_valid, u_cx, u_cy, u_pen;  /* single-level undo of last paint */
static unsigned char pressed_btn;          /* one-frame shared-button feedback     */
static void fmt83(char *dst, const char *n11);   /* both defined below; used by draw() */
static const char *win_title(void);

/* ---- pixel packing for the portable .IST byte format ------------------------
 * Every target stores CPC Mode-1 bytes: pixel i has bit0 @ 7-i and bit1 @ 3-i.
 * The non-CPC kernels transcode the desktop set after loading it, while ICONED
 * reads and writes the canonical on-disk representation on every platform.
 * set_pixel assumes the target bits are clear, as its callers start with zero. */

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

/* gget/gset: read/write a single pen in the packed grid (4 pixels/byte). */
static unsigned char gget(unsigned char y, unsigned char x)
{
    return (unsigned char)((grid[y][x >> 2] >> ((x & 3) << 1)) & 3);
}
static void gset(unsigned char y, unsigned char x, unsigned char pen)
{
    unsigned char sh = (unsigned char)((x & 3) << 1);
    grid[y][x >> 2] = (unsigned char)((grid[y][x >> 2] & ~(unsigned char)(3 << sh))
                                      | (unsigned char)((pen & 3) << sh));
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
            for (i = 0; i < 4; i++) gset(y, (unsigned char)(bx * 4 + i), dec_pixel(b, i));
        }
}

static void encode_icon(unsigned char k)   /* current grid -> buf at icon k */
{
    unsigned char y, bx, i, b;
    icon_dir(k);
    for (y = 0; y < icon_h; y++)
        for (bx = 0; bx < icon_wb; bx++) {
            b = 0;
            for (i = 0; i < 4; i++) b = set_pixel(b, i, gget(y, (unsigned char)(bx * 4 + i)));
            buf[icon_off + (unsigned int)y * icon_wb + bx] = b;
        }
}

static void decode_app_icon(void)
{
    unsigned char y, bx, i, b;
    u_valid = 0;
    gw = APPICON_WB * 4;
    gh = APPICON_H;
    for (y = 0; y < APPICON_H; y++)
        for (bx = 0; bx < APPICON_WB; bx++) {
            b = buf[APPICON_OFF + (unsigned int)y * APPICON_WB + bx];
            for (i = 0; i < 4; i++)
                gset(y, (unsigned char)(bx * 4 + i), dec_pixel(b, i));
        }
}

static void encode_app_icon(void)
{
    unsigned char y, bx, i, b;
    for (y = 0; y < APPICON_H; y++)
        for (bx = 0; bx < APPICON_WB; bx++) {
            b = 0;
            for (i = 0; i < 4; i++)
                b = set_pixel(b, i, gget(y, (unsigned char)(bx * 4 + i)));
            buf[APPICON_OFF + (unsigned int)y * APPICON_WB + bx] = b;
        }
}

/* ---- .SPR cursor ----------------------------------------------------------- */
#ifdef GB_MSX2
/* MSX2: a 66-byte V9938 hardware-sprite cursor - +0/+1 hotspot, +2..33 outline
 * plane, +34..65 fill plane. Each plane is a 16x16 pattern: 16 bytes for the left
 * 8-px column (rows 0..15, bit7 = leftmost), then 16 for the right. Grid convention
 * matches iconedit.py --platform msx2 / lib/msx/cursor.asm: pen 1 (white) = outline,
 * pen 3 (red) = fill, pen 0 = transparent. */
static unsigned char cur_hx, cur_hy;       /* hotspot, preserved across an edit */

static void decode_cursor(void)
{
    unsigned char y, x, idx, bit;
    u_valid = 0;
    gw = 16; gh = 16;
    cur_hx = buf[0]; cur_hy = buf[1];
    for (y = 0; y < 16; y++)
        for (x = 0; x < 16; x++) {
            idx = (unsigned char)((x < 8 ? 0 : 16) + y);
            bit = (unsigned char)(0x80 >> (x & 7));
            gset(y, x, (buf[2 + idx] & bit) ? 1 :          /* outline -> pen 1 */
                       (buf[34 + idx] & bit) ? 3 : 0);     /* fill -> pen 3     */
        }
}

static void encode_cursor(void)
{
    unsigned char y, x, idx, bit, pen;
    unsigned int i;
    for (i = 0; i < CURSOR_LEN; i++) buf[i] = 0;
    buf[0] = cur_hx; buf[1] = cur_hy;
    for (y = 0; y < 16; y++)
        for (x = 0; x < 16; x++) {
            pen = gget(y, x);
            idx = (unsigned char)((x < 8 ? 0 : 16) + y);
            bit = (unsigned char)(0x80 >> (x & 7));
            if (pen == 1)      buf[2 + idx]  |= bit;       /* outline plane */
            else if (pen == 3) buf[34 + idx] |= bit;       /* fill plane    */
        }
}
#else
/* CPC/PCW: 256 bytes = two pre-shifted phases (shift 0, shift 2) back to back,
 * each CUR_H rows of CUR_W byte-columns with mask,data INTERLEAVED per column.
 * PCW stores 2-bit fields in CGA2 hardware-pen order; CPC stores Mode-1 bits. */
static void decode_cursor(void)
{
    unsigned char y, bx, i, d, m, pen;
#ifdef GB_PCW
    unsigned char sh;
#endif
    unsigned int off;
    u_valid = 0;
    gw = 16; gh = 16;
    for (y = 0; y < CUR_H; y++)
        for (bx = 0; bx < CUR_W; bx++) {
            off = (unsigned int)y * (CUR_W * 2) + bx * 2;  /* phase 0: mask, data */
            m = buf[off];
            d = buf[off + 1];
            for (i = 0; i < 4; i++) {
#ifdef GB_PCW
                sh = (unsigned char)(6 - 2 * i);
                if ((m >> sh) & 3) pen = 0;
                else {
                    pen = (unsigned char)((d >> sh) & 3);
                    pen = (pen == 3) ? 1 : (pen == 0) ? 2 : 3;
                }
#else
                pen = ((m >> (7 - i)) & 1) ? 0 : dec_pixel(d, i);
#endif
                gset(y, (unsigned char)(bx * 4 + i), pen);
            }
        }
}

static void enc_cursor_phase(unsigned char shift, unsigned int base)
{
    unsigned char y, bx, i, d, m, pen;
#ifdef GB_PCW
    unsigned char sh;
#endif
    int x;
    unsigned int off;
    for (y = 0; y < CUR_H; y++)
        for (bx = 0; bx < CUR_W; bx++) {
            d = 0; m = 0;
            for (i = 0; i < 4; i++) {
                x = bx * 4 + i - shift;            /* source pixel for this column */
                pen = (x >= 0 && x < 16) ? gget(y, (unsigned char)x) : 0;
#ifdef GB_PCW
                sh = (unsigned char)(6 - 2 * i);
                if (pen == 0) m |= (unsigned char)(3 << sh);
                else {
                    pen = (pen == 1) ? 3 : (pen == 2) ? 0 : 2;
                    d |= (unsigned char)(pen << sh);
                }
#else
                if (pen == 0) m = set_pixel(m, i, 3);   /* transparent: mask both bits */
                else          d = set_pixel(d, i, pen);
#endif
            }
            off = base + (unsigned int)y * (CUR_W * 2) + bx * 2;
            buf[off]     = m;                     /* interleaved: mask, then data */
            buf[off + 1] = d;
        }
}

static void encode_cursor(void)
{
    enc_cursor_phase(0, 0);                         /* phase 0 (shift 0)          */
    enc_cursor_phase(2, 2 * PHASE);                 /* phase 1 (shift 2) @ +128   */
}
#endif

/* sniff: classify the loaded buffer and decode the first item. */
static void sniff(void)
{
    if (filelen >= 16 && buf[0] == 'G' && buf[1] == 'B' && buf[2] == 'I' &&
        buf[3] == 'S' && buf[4] == 2) {
        mode = M_ICON; count = buf[5]; idx = 0;
        if (count == 0) { mode = M_NONE; return; }
        decode_icon(0);
    } else if (filelen >= APPICON_OFF + APPICON_LEN && buf[0] == 0xC3
               && buf[3] == 'G' && buf[4] == 'B' && buf[5] == 'A' && buf[6] == 'P'
               && buf[7] == 1 && buf[8] == 1 && buf[9] == APPICON_WB
               && buf[10] == APPICON_H && buf[11] == 0 && buf[12] == 1
               && buf[13] == APPICON_OFF && buf[14] == 0) {
        mode = M_APP; count = 1; idx = 0;
        decode_app_icon();
    } else if (filelen >= CURSOR_LEN && filelen <= CURSOR_FILE_MAX) {
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
    unsigned char y, bx, i, b, row, h = gh, wb = (unsigned char)(gw >> 2);
    if (mode == M_NONE) { gb_text(CANVAS_X, CANVAS_Y0, "Empty - File>Load"); return; }
    /* Read the packed grid a BYTE at a time (4 pixels) rather than calling gget per
       pixel: fewer accesses in this 1024-cell loop, and no per-cell call frame - the
       per-pixel call made the long redraw drop rows on Prev/Next cycling (#144). */
    for (y = 0; y < h; y++) {
        row = (unsigned char)(CANVAS_Y0 + y * CELL_H);
        for (bx = 0; bx < wb; bx++) {
            b = grid[y][bx];
            for (i = 0; i < 4; i++)
                gb_fill((unsigned char)(CANVAS_X + (bx << 2) + i), row, 1, CELL_H,
                        (unsigned char)((b >> (i << 1)) & 3));
        }
    }
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
    unsigned char flags = (mode == M_ICON && count > 1) ? 0 : GB_WIDGET_DISABLED;
    gb_button(PREV_X, NAV_Y, NAV_BW, NAV_BH, GLYPH_TRI_LEFT,
              (unsigned char)(flags | (pressed_btn == BTN_PREV ? GB_WIDGET_PRESSED : 0)));
    gb_button(NEXT_X, NAV_Y, NAV_BW, NAV_BH, GLYPH_TRI_RIGHT,
              (unsigned char)(flags | (pressed_btn == BTN_NEXT ? GB_WIDGET_PRESSED : 0)));
    gb_fill(PREV_X, NAV_Y + NAV_BH + 2, 8, 8, 0);
    if (!(flags & GB_WIDGET_DISABLED)) {
        fmt_idx();
        gb_text(PREV_X, NAV_Y + NAV_BH + 2, numbuf);
    }
}

static void draw_undo(void)
{
    unsigned char flags = u_valid ? 0 : GB_WIDGET_DISABLED;
    if (pressed_btn == BTN_UNDO) flags |= GB_WIDGET_PRESSED;
    gb_button(UNDO_X, UNDO_Y, UNDO_W, UNDO_H, "UNDO", flags);
}

static void status_line(void)
{
    /* save feedback is now the title's " *" dirty marker (gb_doc_modified). */
    gb_text(win_x + 1, win_y + winh - 11, "Pick a pen, click to paint");
}

static void draw(void)            /* content only; the WM drew the frame/title (#146) */
{
    recalc_origin();
    draw_canvas();
    draw_palette();
    draw_nav();
    draw_undo();
    status_line();
}
/* sync_rect: pull the live WM-owned geometry before we use it (#146). */
static void sync_rect(void)
{
    win_x = gb_wm_x(); win_y = gb_wm_y(); winw = gb_wm_w(); winh = gb_wm_h();
}

/* ---- file menu (kernel-drawn top bar; popup pattern from notepad) ------------ */

/* on_menu: a top-bar title was clicked -> hand it to the framework. */
static void on_menu(void) { gb_doc_event(); }

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

/* win_title: the file name (from gb_doc) + " *" when unsaved. Single-index copy (the
   two-index form is miscompiled by SDCC under --fomit-frame-pointer, #142). */
static const char *win_title(void)
{
    unsigned char j = 0;
    char c;
    fmt83(fbase, gb_doc_name());
    while ((c = fbase[j]) != 0) { wtitle[j] = c; j++; }
    if (gb_doc_modified()) { wtitle[j++] = ' '; wtitle[j++] = '*'; }
    wtitle[j] = 0;
    return wtitle;
}

/* ---- the document, via the gb_doc framework (#142) -------------------------- *
 * The document is buf (a .IST set, icon-bearing .APP, or .SPR cursor). The framework owns the File
 * menu (New / Load / Save / Save As) + the navigable dialog; we provide the hooks. */
static const char *const ie_exts[] = { "IST", "SPR", "APP", 0 };

/* ie_new: a blank single 24x24 icon set (GBIS v2) so New gives something to draw. */
static void ie_new(void)
{
    unsigned int i;
    for (i = 0; i < 20 + 6 * 24; i++) buf[i] = 0;
    buf[0] = 'G'; buf[1] = 'B'; buf[2] = 'I'; buf[3] = 'S';
    buf[4] = 2; buf[5] = 1;                       /* version 2, count 1 */
    buf[16] = 20; buf[18] = 6; buf[19] = 24;      /* dir[0]: off=20, wb=6, h=24 */
    filelen = 20 + 6 * 24;
    sniff();
}

/* ie_open: a .IST/.SPR was just loaded into buf - classify + decode the first item. */
static void ie_open(unsigned int len) { filelen = len; sniff(); }

/* ie_save: fold the current edit back into buf and return the byte count to write. */
static unsigned int ie_save(void)
{
    if (mode == M_ICON)   { encode_icon(idx); return filelen; }
    if (mode == M_APP)    { encode_app_icon(); return filelen; }
    if (mode == M_CURSOR) { encode_cursor();  return filelen; }
    return 0;
}

/* recalc_origin: refresh the centered content origin from the live geometry. */
static void recalc_origin(void)
{
    ox = (unsigned char)(win_x + (winw - WIN_W) / 2);
    oy = (unsigned char)(win_y + (winh - WIN_H) / 2);
}

/* ie_fullscreen: View > Fullscreen - cover the screen (grid + panel recenter) and back. */
static void ie_fullscreen(unsigned char on)
{
    if (on) { gb_wm_setpos(0, 8); gb_wm_setsize(GB_COLS, GB_LINES - 8); }
    else    { gb_wm_setpos(DEF_X, DEF_Y); gb_wm_setsize(WIN_W, WIN_H); }
    gb_wm_damage(0, 8, GB_COLS, GB_LINES - 8); /* repaint ONCE in on_frame, clipped to the toggle area;
                                     repainting here too double-paints (the flicker, #153) */
}

static const gb_doc_t iedoc = {
    buf, BUFSZ, ie_new, ie_open, ie_save, 0, 0, 0, 0, ie_exts,
    0, 0, ie_fullscreen, 0, 0
};

/* ---- WM callbacks ----------------------------------------------------------- */

static void ie_draw(void) { sync_rect(); draw(); }   /* on_draw (#146): WM owns the cursor */

static void cell_redraw(unsigned char cx, unsigned char cy)
{
    gb_curhide();
    gb_fill(CANVAS_X + cx, CANVAS_Y0 + cy * CELL_H, 1, CELL_H, gget(cy, cx));
    gb_curshow();
}

static void paint_cell(unsigned char cx, unsigned char cy)
{
    unsigned char had_undo = u_valid;
    u_cx = cx; u_cy = cy;                 /* remember for UNDO */
    u_pen = gget(cy, cx);
    u_valid = 1;
    gset(cy, cx, selpen);
    gb_doc_dirty();                       /* mark the document unsaved (#142) */
    cell_redraw(cx, cy);
    if (!had_undo) {
        gb_curhide();
        draw_undo();
        gb_curshow();
    }
}

/* do_undo: restore the last painted cell's previous pen. Swaps, so pressing UNDO
   again redoes the change (single-level undo/redo of the last paint). */
static void do_undo(void)
{
    unsigned char t;
    if (!u_valid) return;
    t = gget(u_cy, u_cx);
    gset(u_cy, u_cx, u_pen);
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
    draw_undo();                              /* changing icons clears single-level undo */
    gb_curshow();
}

/* on_frame (#146): the WM handled close/drag; run the menu framework. */
static void ie_frame(void)
{
    sync_rect();
    win_title();                                      /* keep wtitle fresh for the WM title */
    if (pressed_btn != BTN_NONE) {
        pressed_btn = BTN_NONE;
        gb_curhide();
        draw_nav();
        draw_undo();
        gb_curshow();
    }
    if (gb_doc_frame()) { gb_restore_parent(); return; }   /* a File menu ran (#142) */
}

/* on_close (#146): offer to save, then close (or repaint on cancel). */
static void ie_close(void)
{
    if (gb_doc_close()) gb_wm_close();
    else gb_restore_parent();
}

/* on_drag (#146): a title-bar press -> move the window. */
static void ie_drag(void)
{
    sync_rect();
    if (gb_drag_window(&win_x, &win_y, winw, winh)) {
        gb_wm_setpos(win_x, win_y);
        gb_restore_parent();
    }
}

/* on_click (#146): a content press - canvas paint, palette, Prev/Next, or UNDO. */
static void ie_click(void)
{
    unsigned char mx, my, k, y, flags;
    sync_rect();
    recalc_origin();                                  /* origin for the CANVAS_X/PANEL hit-tests */
    mx = gb_mx(); my = gb_my();

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

    flags = (mode == M_ICON && count > 1) ? 0 : GB_WIDGET_DISABLED;
    if (gb_button_hit(PREV_X, NAV_Y, NAV_BW, NAV_BH, mx, my, flags)) {
        pressed_btn = BTN_PREV;
        gb_curhide(); draw_nav(); gb_curshow();
        switch_icon(0);
        return;
    }
    if (gb_button_hit(NEXT_X, NAV_Y, NAV_BW, NAV_BH, mx, my, flags)) {
        pressed_btn = BTN_NEXT;
        gb_curhide(); draw_nav(); gb_curshow();
        switch_icon(1);
        return;
    }

    flags = u_valid ? 0 : GB_WIDGET_DISABLED;
    if (gb_button_hit(UNDO_X, UNDO_Y, UNDO_W, UNDO_H, mx, my, flags)) {
        pressed_btn = BTN_UNDO;
        gb_curhide(); draw_undo(); gb_curshow();
        do_undo();
    }
}

/* the window's single handler (#148). */
static void ie_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  ie_draw();  break;
        case GB_MSG_CLICK: ie_click(); break;
        case GB_MSG_FRAME: ie_frame(); break;
        case GB_MSG_CLOSE: ie_close(); break;
        case GB_MSG_DRAG:  ie_drag();  break;
        case GB_MSG_MENU:
        case GB_MSG_DROP:  on_menu();  break;
    }
}

static const gb_mwin_t iemw = {
    DEF_X, DEF_Y, WIN_W, WIN_H, 0, 0,        /* min_w=0: not grip-resizable */
    ie_proc, wtitle
};

void main(void)
{
    unsigned char n;

    /* CPC storage helpers share the #1700 transfer block with GBUI. A File
       Manager free-space probe can therefore leave the modal latch dirty and
       make the top-bar File title appear inert. */
    UI_MODAL_K = 0;
    gb_wm_managed(&iemw);                    /* register FIRST (no draw): captures our file arg */
    gb_doc(&iedoc);                          /* standard File menu; adopts the launch name */
    filelen = gb_fs_load(buf, BUFSZ);        /* load the launch file (0 if none) */
    sniff();                                 /* classify it (M_ICON / M_CURSOR / M_NONE) */
    selpen = 1;
    win_title();                             /* build wtitle before the first paint */
    for (n = 64; n; n--) if (!gb_getkey()) break;

    gb_restore_parent();                     /* first paint: WM chrome + ie_draw */
}
