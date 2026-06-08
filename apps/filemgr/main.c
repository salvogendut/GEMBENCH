/* filemgr - the GEOBENCH file manager, in C.
 *
 * Lists the active drive's directory in a co-resident window (issue #45). Two
 * views (issue #52), toggled by the top-bar "View" menu:
 *   - LIST  : one entry per row, type icon + name.
 *   - ICONS : the type icons laid out in a grid, names beneath.
 * A scrollbar at the left inner edge scrolls whichever view is active: click the
 * track above/below the thumb to page, or drag the thumb. A click selects an
 * entry (red frame); a double-click opens it (open_entry routes by file extension
 * to a co-resident app - #70). The close gadget or ESC closes the window; drag the
 * title bar to move it.
 *
 * All of this is app-level: the kernel/WM owns the window (focus, z-order, the
 * rect-clipped repaint); the contents - views, grid, scrollbar - are drawn here
 * with gb_dir*, gb_blite, gb_fill/gb_frame/gb_text. No kernel changes. */
#include "gb.h"

#define DEF_X    4            /* window position */
#define DEF_Y    26
#define DEF_W    56            /* default size; the window is resizeable (#81) */
#define DEF_H    130
#define MIN_W    24            /* min size keeps the title + a couple of rows usable */
#define MIN_H    62
#define TITLE_H  14
#define DCLICK   40           /* double-click window, frames */

/* scrollbar at the left inner edge, content to its right */
#define SB_W     3                       /* scrollbar width, byte cols */
#define SB_X     (win_x + 1)             /* just inside the left border */
#define CT_X     (win_x + 1 + SB_W)      /* content left */
#define CT_Y     (win_y + TITLE_H)       /* content top, below the title bar */
#define CT_W     (win_w - 2 - SB_W)      /* content width (runtime, resizeable) */
#define CT_H     (win_h - TITLE_H - 2)   /* content height (runtime) */

/* list view */
#define ROW_H    18
#define LVIS     (CT_H / ROW_H)          /* visible rows (6) */

/* icons view */
#define ICOLS    3
#define CELL_W   (CT_W / ICOLS)          /* cell width (17) */
#define CELL_H   28                      /* icon (16) + name (8) + gap */
#define IVIS     (CT_H / CELL_H)         /* visible grid rows (4) */
#define NAME_MAX (CELL_W * 4 / 6)        /* chars that fit a cell (6px font) */

#define V_LIST   0
#define V_ICONS  1

static unsigned char win_x = DEF_X, win_y = DEF_Y;
static unsigned char win_w = DEF_W, win_h = DEF_H;
static unsigned char total;       /* number of files on the disk          */
static unsigned char top;         /* first visible LINE (row / grid row)  */
static unsigned char nsel;        /* 0 = none, else selected index + 1    */
static unsigned char dc_idx;      /* index of the last click              */
static unsigned char dc_timer;
static unsigned char view = V_ICONS;   /* default = icon view (GEOBENCH.CFG VIEW=) */
static unsigned char my_drive;         /* the drive this window browses (#65) */
static const char *const drive_title[3] = { "Disk C", "Disk A", "Disk B" };

/* GEOBENCH.CFG is loaded once at startup; the View toggle rewrites the VIEW= line
   and saves it, so the choice persists across reboots. NOTE: gb_fs_load copies in
   whole 512-byte sectors, so the buffer must be a full sector even though the file
   is tiny (a smaller buffer overflows into the globals after it). */
static char cfgbuf[512];
static unsigned int cfglen;

/* the top-bar menu: "View" toggles list/icons, "Back" goes up a directory */
static const unsigned char fm_menu[] = {
    2,
    10, 'V','i','e','w',0,0,0,0,
    17, 'B','a','c','k',0,0,0,0
};
#define MENU_BACK_COL 17      /* click column >= this -> Back, else View */

static unsigned char count_files(void)
{
    unsigned char n = 0;
    char *p = gb_dir1();
    while (p) { n++; p = gb_dirn(); }
    return n;
}

/* dir_seek: position the dir cursor at absolute index idx; return its name (0 if
   past the end). The caller continues with gb_dirn() from there. */
static char *dir_seek(unsigned char idx)
{
    unsigned char i;
    char *p = gb_dir1();
    for (i = 0; i < idx && p; i++) p = gb_dirn();
    return p;
}

/* cfg_view_pos: index just past "VIEW=" in cfgbuf, or 0xFFFF if there's no such key. */
static unsigned int cfg_view_pos(void)
{
    unsigned int i;
    for (i = 0; i + 5 <= cfglen; i++)
        if (cfgbuf[i] == 'V' && cfgbuf[i+1] == 'I' && cfgbuf[i+2] == 'E'
            && cfgbuf[i+3] == 'W' && cfgbuf[i+4] == '=')
            return i + 5;
    return 0xFFFF;
}

/* cfg_load_view: load GEOBENCH.CFG and set the initial view from VIEW= (LIST -> list;
   DEFAULT / absent / missing file -> icons). Keeps the buffer for cfg_save_view. */
static void cfg_load_view(void)
{
    unsigned int p;
    gb_set_name("GEOBENCHCFG");
    cfglen = gb_fs_load(cfgbuf, sizeof(cfgbuf));
    view = V_ICONS;
    p = cfg_view_pos();
    if (p != 0xFFFF && p + 4 <= cfglen && cfgbuf[p] == 'L' && cfgbuf[p+1] == 'I'
        && cfgbuf[p+2] == 'S' && cfgbuf[p+3] == 'T')
        view = V_LIST;
}

/* cfg_save_view: write the current view into GEOBENCH.CFG's VIEW= line (LIST or
   DEFAULT), preserving the other keys, and save. Best-effort (no-op if the file
   can't be written - e.g. it doesn't exist). */
static void cfg_save_view(void)
{
    const char *val = (view == V_LIST) ? "LIST" : "DEFAULT";
    unsigned char vlen = (view == V_LIST) ? 4 : 7;
    unsigned int p, end, i;

    if (cfglen == 0) return;                 /* no config loaded -> nothing to update */
    p = cfg_view_pos();
    if (p == 0xFFFF) {                        /* no VIEW= key: append a line */
        if (cfglen + 7 + vlen > sizeof(cfgbuf)) return;
        cfgbuf[cfglen++] = 'V'; cfgbuf[cfglen++] = 'I'; cfgbuf[cfglen++] = 'E';
        cfgbuf[cfglen++] = 'W'; cfgbuf[cfglen++] = '=';
        for (i = 0; i < vlen; i++) cfgbuf[cfglen++] = val[i];
        cfgbuf[cfglen++] = '\r'; cfgbuf[cfglen++] = '\n';
    } else {                                  /* replace the existing value in place */
        end = p;
        while (end < cfglen && cfgbuf[end] != '\r' && cfgbuf[end] != '\n') end++;
        if (vlen > (unsigned char)(end - p)) {           /* grow: shift tail right */
            unsigned int d = vlen - (end - p);
            if (cfglen + d > sizeof(cfgbuf)) return;
            for (i = cfglen; i > end; i--) cfgbuf[i - 1 + d] = cfgbuf[i - 1];
            cfglen += d;
        } else if (vlen < (unsigned char)(end - p)) {    /* shrink: shift tail left */
            unsigned int d = (end - p) - vlen;
            for (i = end; i < cfglen; i++) cfgbuf[i - d] = cfgbuf[i];
            cfglen -= d;
        }
        for (i = 0; i < vlen; i++) cfgbuf[p + i] = val[i];
    }
    gb_set_name("GEOBENCHCFG");
    gb_fs_save(cfgbuf, cfglen);
}

/* scroll model: lines (rows in list, grid rows in icons) and how many are visible */
static unsigned char total_lines(void)
{
    if (view == V_ICONS) return (unsigned char)((total + ICOLS - 1) / ICOLS);
    return total;
}
static unsigned char vis_lines(void)
{
    return (view == V_ICONS) ? IVIS : LVIS;
}
static void clamp_top(void)
{
    unsigned char tl = total_lines(), vl = vis_lines();
    if (tl <= vl) { top = 0; return; }
    if (top > tl - vl) top = tl - vl;
}

/* thumb geometry: th = height, ty = top line (only meaningful when tl > vl). */
static unsigned char thumb_h(void)
{
    unsigned char tl = total_lines(), vl = vis_lines(), th;
    if (tl <= vl) return CT_H;
    th = (unsigned char)(((unsigned)CT_H * vl) / tl);
    return th < 6 ? 6 : th;
}
static unsigned char thumb_y(void)
{
    unsigned char tl = total_lines(), vl = vis_lines();
    if (tl <= vl) return CT_Y;
    return (unsigned char)(CT_Y + ((unsigned)(CT_H - thumb_h()) * top) / (tl - vl));
}

#define ARR_H 8                          /* up/down scroll-button height (px) */

static void draw_scrollbar(void)
{
    gb_fill(SB_X, CT_Y, SB_W, CT_H, 1);                        /* white track */
    gb_fill(SB_X + 1, thumb_y() + 1, 1, thumb_h() - 2, 3);     /* red thumb, inset 1px */
    /* up/down buttons: a white patch (covers the thumb if it parks at an end), then
       the glyph black-on-white, aligned with the thumb (SB_X+1) */
    gb_fill(SB_X, CT_Y, SB_W, ARR_H, 1);
    gb_textbw(SB_X + 1, CT_Y, GLYPH_TRI_UP);
    gb_fill(SB_X, CT_Y + CT_H - ARR_H, SB_W, ARR_H, 1);
    gb_textbw(SB_X + 1, CT_Y + CT_H - ARR_H, GLYPH_TRI_DOWN);
}

/* draw a name truncated to fit a cell (icons view) */
static void draw_name(unsigned char col, unsigned char line, char *name)
{
    static char tmp[14];
    unsigned char i;
    for (i = 0; i < NAME_MAX && i < 13 && name[i]; i++) tmp[i] = name[i];
    tmp[i] = 0;
    gb_text(col, line, tmp);
}

/* name83: format an 11-byte space-padded 8.3 name as "NAME.EXT". */
static char *name83(const char *e)
{
    static char fn[13];
    unsigned char i, j = 0;
    for (i = 0; i < 8 && e[i] != ' '; i++) fn[j++] = e[i];
    if (e[8] != ' ') {                   /* has an extension */
        fn[j++] = '.';
        for (i = 8; i < 11 && e[i] != ' '; i++) fn[j++] = e[i];
    }
    fn[j] = 0;
    return fn;
}

/* fullname: the current entry's 8.3 name as "NAME.EXT" (list view shows the
   extension; gb_dir* return name only). */
static char *fullname(void) { return name83(gb_entname()); }

static void draw_list_view(void)
{
    unsigned char i, y;
    char *name = dir_seek(top);
    for (i = 0; i < LVIS && name; i++) {
        y = CT_Y + i * ROW_H;
        gb_blite(CT_X, y + 1);              /* type icon (8 cols x 16 lines) */
        gb_text(CT_X + 9, y + 6, fullname());   /* NAME.EXT (icon view is name only) */
        name = gb_dirn();
    }
    if (nsel) {                              /* red frame on the selected row */
        unsigned char s = nsel - 1;
        if (s >= top && s < top + LVIS)
            gb_frame(CT_X, CT_Y + (s - top) * ROW_H, CT_W, 17, 3);
    }
}

static void draw_icons_view(void)
{
    unsigned char r, c, cx, cy;
    unsigned int idx = (unsigned int)top * ICOLS;    /* first visible item */
    char *name = dir_seek((unsigned char)idx);
    for (r = 0; r < IVIS; r++) {
        for (c = 0; c < ICOLS; c++) {
            if (!name) return;
            cx = CT_X + c * CELL_W;
            cy = CT_Y + r * CELL_H;
            gb_blite(cx + (CELL_W - 8) / 2, cy + 1);   /* icon centered in the cell */
            draw_name(cx, cy + 18, name);
            if (nsel == (unsigned char)idx + 1)
                gb_frame(cx, cy, CELL_W, CELL_H - 1, 3);
            idx++;
            name = gb_dirn();
        }
    }
}

/* draw: full repaint of the window (on_repaint). */
static void draw(void)
{
    gb_set_drive(my_drive);              /* this window's drive (#65) - on_repaint may
                                            run while another window's drive is active */
    gb_curhide();
    gb_window(win_x, win_y, win_w, win_h, drive_title[my_drive]);
    draw_scrollbar();
    if (view == V_ICONS) draw_icons_view();
    else                 draw_list_view();
    gb_draw_grip(win_x, win_y, win_w, win_h);   /* resize grip, bottom-right (#81) */
    gb_curshow();
}

/* relist: re-read the current directory and redraw from the top (#54). */
static void relist(void)
{
    total = count_files();
    top = 0; nsel = 0;
    clamp_top();
    draw();
}

/* ext_is: does the positioned entry's raw 11-byte 8.3 name end in this extension? */
static unsigned char ext_is(const char *e, char a, char b, char c)
{
    return (unsigned char)(e[8] == a && e[9] == b && e[10] == c);
}

/* open_entry: a directory descends in place (gb_chdir + re-list, same window); a
   file opens a co-resident app chosen here by extension (#70 - the routing that
   used to live in the kernel's app_for_ext is now app-level C):
     .APP             a GEOBENCH app -> run it (no file arg)
     .IST / .SPR      the icon/cursor editor (ICONED), with the file
     .TXT / .CFG / .BAS   the text editor (NOTEPAD), with the file
     anything else    the read-only VIEWER, with the file
   (Part 3 will route native .BIN/.BAS to a "run via AMSDOS" confirm instead.) */
static void open_entry(unsigned char idx)
{
    char *e;
    dir_seek(idx);                 /* position at the entry (sets attr + cluster) */
    if (gb_isdir()) { gb_chdir(); relist(); return; }
    nsel = 0;
    e = gb_entname();              /* the positioned entry's 11-byte 8.3 name */
    if (ext_is(e, 'A', 'P', 'P'))
        gb_wm_open(e);                          /* run the app itself, file-less */
    else if (ext_is(e, 'I', 'S', 'T') || ext_is(e, 'S', 'P', 'R'))
        gb_wm_launch_as("ICONED  APP");
    else if (ext_is(e, 'T', 'X', 'T') || ext_is(e, 'C', 'F', 'G') ||
             ext_is(e, 'B', 'A', 'S'))
        gb_wm_launch_as("NOTEPAD APP");
    else
        gb_wm_launch_as("VIEWER  APP");
}

/* sb_drag: while the fire is held, map the pointer's Y to the scroll position
   (self-driven poll loop, like the modal popups - the WM loop pauses meanwhile). */
static void sb_drag(void)
{
    unsigned char tl = total_lines(), vl = vis_lines(), my, nt;
    if (tl <= vl) return;
    for (;;) {
        if (!(gb_poll() & GB_FIRE)) break;
        my = gb_my();
        if (my < CT_Y) my = CT_Y;
        if (my >= CT_Y + CT_H) my = CT_Y + CT_H - 1;
        nt = (unsigned char)(((unsigned)(my - CT_Y) * (tl - vl)) / CT_H);
        if (nt != top) { top = nt; clamp_top(); draw(); }
    }
}

/* sb_click: a click in the scrollbar - page above/below the thumb, or drag it. */
static void sb_click(unsigned char my)
{
    unsigned char ty = thumb_y(), th = thumb_h(), vl = vis_lines();
    if (total_lines() <= vl) return;
    if (my < ty)            { top = (top > vl) ? top - vl : 0; clamp_top(); draw(); }
    else if (my >= ty + th) { top += vl; clamp_top(); draw(); }
    else                    sb_drag();
}

/* on_event: a top-bar menu click. "Back" (right title) goes to the parent
   directory; "View" (left title) toggles list / icons. */
static void on_event(void)
{
    if (gb_msg.type == GB_MSG_DROP) {     /* a file dropped here from another window (#65) */
        unsigned int n;                   /* copy it onto THIS window's drive (#74) */
        gb_set_drive(my_drive);
        gb_copy_begin();                  /* switch to the drag source drive/dir */
        gb_set_name(gb_dragname);
        n = gb_fs_load(gb_copybuf, GB_COPYMAX);
        gb_set_drive(my_drive);           /* back to this window's drive */
        gb_set_name(gb_dragname);
        gb_fs_save(gb_copybuf, n);        /* lands in the root */
        gb_copy_end();                    /* restore this window's drive/dir */
        relist();
        return;
    }
    if (gb_msg.type != GB_MSG_MENU) return;
    if (gb_msg.p0 >= MENU_BACK_COL) {     /* Back */
        gb_back();
        relist();
    } else {                              /* View: toggle + persist to GEOBENCH.CFG */
        view ^= 1;
        cfg_save_view();
        top = 0; nsel = 0;
        clamp_top();
        draw();
    }
}

/* on_frame: one frame when focused (kernel WM loop). Read input via gb_flags/mx/my. */
static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my, idx;

    gb_set_drive(my_drive);              /* re-assert our drive each focused frame (#65) */
    if (dc_timer) dc_timer--;
    if (flags & GB_QUIT) { gb_wm_close(); return; }    /* ESC closes the window */
    if (!(flags & GB_CLICK)) return;

    mx = gb_mx();
    my = gb_my();

    /* close gadget (top-left of the title bar) */
    if (my >= win_y && my < win_y + TITLE_H && mx >= win_x && mx < win_x + 4) {
        gb_wm_close();
        return;
    }

    /* title bar (right of the close gadget) -> drag the window */
    if (my >= win_y && my < win_y + TITLE_H && mx >= win_x + 4 && mx < win_x + win_w) {
        if (gb_drag_window(&win_x, &win_y, win_w, win_h)) {
            gb_wm_setpos(win_x, win_y);
            gb_restore_parent();
        }
        return;
    }

    /* resize grip (bottom-right corner) -> resize the window (#81) */
    if (gb_in_grip(win_x, win_y, win_w, win_h, mx, my)) {
        if (gb_drag_resize(win_x, win_y, &win_w, &win_h, MIN_W, MIN_H)) {
            gb_wm_setsize(win_w, win_h);
            gb_restore_parent();
            draw();
        }
        return;
    }

    /* scrollbar: up/down arrow buttons (one line) at the ends, page/drag between */
    if (mx >= SB_X && mx < SB_X + SB_W && my >= CT_Y && my < CT_Y + CT_H) {
        unsigned char old = top, tl = total_lines(), vl = vis_lines();
        if (my < CT_Y + ARR_H) {                     /* up arrow */
            if (top) top--;
        } else if (my >= CT_Y + CT_H - ARR_H) {      /* down arrow */
            if (tl > vl && top < tl - vl) top++;
        } else {
            sb_click(my);
            return;
        }
        if (top != old) draw();
        return;
    }

    /* content: pick the entry under the pointer (list row or grid cell) */
    if (my >= CT_Y && my < CT_Y + CT_H && mx >= CT_X && mx < win_x + win_w) {
        if (view == V_ICONS) {
            unsigned char c = (mx - CT_X) / CELL_W;
            unsigned char r = (my - CT_Y) / CELL_H;
            if (c >= ICOLS) return;
            idx = (unsigned char)((top + r) * ICOLS + c);
        } else {
            idx = top + (my - CT_Y) / ROW_H;
        }
        if (idx >= total) return;
        /* press on an entry: a drag (press + move) drags it to another window /
           the Trash (#62); a plain click (no move) falls through to select/open */
        dir_seek(idx);                       /* position -> gb_entname is this entry */
        if (gb_drag_start(gb_entname())) {   /* dropped on a target -> it handled it */
            relist();                        /* refresh (a move changes this dir) */
            return;
        }
        if (dc_timer && dc_idx == idx) {     /* double-click -> open (dir or file) */
            open_entry(idx);
            dc_timer = 0;
        } else {                              /* single click -> select */
            nsel = idx + 1;
            dc_idx = idx;
            dc_timer = DCLICK;
            draw();
        }
    }
}

/* a co-resident window: on_repaint = draw, on_event = the View toggle, menu = the
   "View" title (shown in the top bar while we are focused). */
static gb_win_t fmwin = { DEF_X, DEF_Y, DEF_W, DEF_H, on_frame, draw, on_event, fm_menu };

void main(void)
{
    nsel = 0; dc_timer = 0;
    my_drive = gb_get_drive();   /* the drive the desktop opened us on (#65) */
    win_x = DEF_X + my_drive * 8;   /* cascade so two drive windows don't fully overlap */
    win_y = DEF_Y + my_drive * 14;
    fmwin.x = win_x;             /* register the hit rect at the cascaded position */
    fmwin.y = win_y;
    gb_wm_add(&fmwin);           /* register first (focus) so gb_set_name/fs_load
                                   target our window for the config read below */
    gb_set_drive(my_drive);
    cfg_load_view();             /* VIEW= from GEOBENCH.CFG -> view (default icons) */
    total = count_files();
    top = 0;
    clamp_top();
    draw();
}
