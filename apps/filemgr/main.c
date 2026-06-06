/* filemgr - the GEOBENCH file manager, in C.
 *
 * Launched by the desktop when the Disk icon is double-clicked. Runs co-resident
 * in its own bank page, lists the active drive's directory in a window - a type
 * icon + name per entry - and SCROLLS when the list is taller than the window
 * (a footer pager: click the left half to scroll up, the right half down). A
 * click selects a row (red frame); a double-click launches the entry's app
 * (the kernel's type->app table). The close gadget or ESC closes the window.
 *
 * Issue #45: a co-resident window managed by the kernel. main() registers it with
 * gb_wm_add and returns; the kernel's WM loop calls on_frame when we are focused
 * and draw_list (on_repaint) to restack us. Click our window to focus it; click
 * the desktop (or another window) to focus that. */
#include "gb.h"

#define DEF_X    4            /* window position */
#define DEF_Y    26
#define WIN_W    56
#define WIN_H    130
#define TITLE_H  14
#define ROW_OFF  18           /* first row, below the title bar */
#define ROW_H    18
#define VIS      5            /* visible rows (the rest scroll)  */
#define DCLICK   40           /* double-click window, frames */

static unsigned char win_x = DEF_X;   /* window position */
static unsigned char win_y = DEF_Y;
static unsigned char total;   /* number of files on the disk            */
static unsigned char top;     /* index of the first visible row (scroll) */
static unsigned char nsel;    /* 0 = none, else selected index + 1       */
static unsigned char dc_row;  /* row index of the last click             */
static unsigned char dc_timer;

static unsigned char count_files(void)
{
    unsigned char n = 0;
    char *p = gb_dir1();
    while (p) { n++; p = gb_dirn(); }
    return n;
}

/* draw_list: window, scroll pager, the visible rows, and the selection. */
static void draw_list(void)
{
    unsigned char i, y;
    unsigned char foot_y = win_y + WIN_H - 12;
    char *name;

    gb_curhide();
    gb_window(win_x, win_y, WIN_W, WIN_H, "DISK A");

    /* footer pager: show the arrows that apply (ASCII only - the font is 32..127) */
    if (top > 0)             gb_text(win_x + 5, foot_y, "^ up");
    if (top + VIS < total)   gb_text(win_x + WIN_W - 16, foot_y, "dn v");

    name = gb_dir1();
    for (i = 0; i < top && name; i++) name = gb_dirn();   /* skip to 'top' */
    for (i = 0; i < VIS && name; i++) {
        y = win_y + ROW_OFF + i * ROW_H;
        gb_blite(win_x + 2, y);            /* the current entry's type icon */
        gb_text(win_x + 11, y + 5, name);
        name = gb_dirn();
    }

    if (nsel) {                          /* red frame on the selected row */
        unsigned char s = nsel - 1;
        if (s >= top && s < top + VIS)
            gb_frame(win_x + 1, win_y + ROW_OFF - 1 + (s - top) * ROW_H,
                     WIN_W - 2, 17, 3);
    }
    gb_curshow();
}

/* launch: open the file at absolute index idx as a co-resident window (#45) - it
   opens on top and takes focus; we stay live underneath. Click between windows to
   switch focus. (gb_wm_launch picks the app by type and passes the file as the arg,
   the non-blocking gb_launch.) */
static void launch(unsigned char idx)
{
    unsigned char i;
    char *p = gb_dir1();
    for (i = 0; i < idx && p; i++) p = gb_dirn();
    nsel = 0;
    gb_wm_launch();
}

/* on_frame: one frame when this window is focused (kernel WM loop, issue #45).
   Read input with gb_flags/mx/my; each old loop 'continue' is now a 'return'. */
static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my, vis, idx, foot_y;

    if (dc_timer) dc_timer--;
    if (flags & GB_QUIT) { gb_wm_close(); return; }    /* ESC closes this window */
    if (!(flags & GB_CLICK)) return;

    mx = gb_mx();
    my = gb_my();
    foot_y = win_y + WIN_H - 12;

    /* close gadget (top-left of the title bar) */
    if (my >= win_y && my < win_y + TITLE_H && mx >= win_x && mx < win_x + 4) {
        gb_wm_close();
        return;
    }

    /* title bar (right of the close gadget) -> drag the window */
    if (my >= win_y && my < win_y + TITLE_H
        && mx >= win_x + 4 && mx < win_x + WIN_W) {
        if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
            gb_wm_setpos(win_x, win_y);   /* move our hit rect to follow */
            gb_restore_parent();          /* repaint the stack at the new spot */
        }
        return;
    }

    /* footer pager: left half scrolls up, right half down */
    if (my >= foot_y && my < foot_y + 10) {
        if (mx < win_x + WIN_W / 2) {
            if (top > 0) { top--; draw_list(); }
        } else {
            if (top + VIS < total) { top++; draw_list(); }
        }
        return;
    }

    /* a list row? */
    if (my >= win_y + ROW_OFF && my < win_y + ROW_OFF + VIS * ROW_H
        && mx >= win_x && mx < win_x + WIN_W) {
        vis = (my - (win_y + ROW_OFF)) / ROW_H;
        idx = top + vis;
        if (idx >= total) return;
        if (dc_timer && dc_row == idx) {     /* double-click -> open */
            launch(idx);
            dc_timer = 0;
        } else {                              /* single click -> select */
            nsel = idx + 1;
            dc_row = idx;
            dc_timer = DCLICK;
            draw_list();
        }
    }
}

/* a co-resident window: click it to focus, drag the title bar to move it (the hit
   rect follows via gb_wm_setpos), the close gadget or ESC to close. on_repaint =
   draw_list, which the kernel calls to restack us. */
static const gb_win_t fmwin = { DEF_X, DEF_Y, WIN_W, WIN_H, on_frame, draw_list, 0, 0 };

void main(void)
{
    win_x = DEF_X;
    win_y = DEF_Y;
    total = count_files();
    top = 0; nsel = 0; dc_timer = 0;
    draw_list();
    gb_wm_add(&fmwin);           /* register; the kernel WM drives us (#45) */
}
