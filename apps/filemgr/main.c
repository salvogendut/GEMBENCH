/* filemgr - the GEOBENCH file manager, in C.
 *
 * Launched by the desktop when the Disk icon is double-clicked. Runs co-resident
 * in its own bank page, lists the active drive's directory in a window - a type
 * icon + name per entry - and SCROLLS when the list is taller than the window
 * (a footer pager: click the left half to scroll up, the right half down). A
 * click selects a row (red frame); a double-click launches the entry's app
 * (the kernel's type->app table). The close gadget or ESC quits.
 *
 * The window is draggable (issue #43): grab the title bar (right of the close
 * gadget) and move it. Dragging lifts the window to an outline, then redraws at
 * the dropped position - no save-under; the backdrop pen fills the vacated area. */
#include "gb.h"

#define DEF_X    4            /* initial window position */
#define DEF_Y    26
#define WIN_W    56
#define WIN_H    130
#define TITLE_H  14
#define ROW_OFF  18           /* first row, below the title bar */
#define ROW_H    18
#define VIS      5            /* visible rows (the rest scroll)  */
#define DCLICK   40           /* double-click window, frames */

static unsigned char win_x = DEF_X;   /* live window position (draggable) */
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

/* launch: open the file at absolute index idx (position the dir cursor there,
   then ask the kernel to launch the entry), and redraw on return. */
static void launch(unsigned char idx)
{
    unsigned char i;
    char *p = gb_dir1();
    for (i = 0; i < idx && p; i++) p = gb_dirn();
    gb_launch();
    gb_fill(0, 8, 80, 192, 0);   /* clear the launched app's window (no save-under) */
    nsel = 0;
    draw_list();
}

void main(void)
{
    unsigned char flags, mx, my, vis, idx;
    unsigned char foot_y;

    total = count_files();
    top = 0; nsel = 0; dc_timer = 0;
    draw_list();
    gb_on_repaint(draw_list);    /* repaint behind a child's (or our) moved window */

    for (;;) {
        flags = gb_poll();
        if (dc_timer) dc_timer--;
        if (flags & GB_QUIT) return;
        if (!(flags & GB_CLICK)) continue;

        mx = gb_mx();
        my = gb_my();
        foot_y = win_y + WIN_H - 12;

        /* close gadget (top-left of the title bar) */
        if (my >= win_y && my < win_y + TITLE_H && mx >= win_x && mx < win_x + 4)
            return;

        /* title bar (right of the close gadget) -> drag the window */
        if (my >= win_y && my < win_y + TITLE_H
            && mx >= win_x + 4 && mx < win_x + WIN_W) {
            if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
                gb_restore_parent();                  /* repaint what was behind us */
                draw_list();                          /* our window on top */
            }
            continue;
        }

        /* footer pager: left half scrolls up, right half down */
        if (my >= foot_y && my < foot_y + 10) {
            if (mx < win_x + WIN_W / 2) {
                if (top > 0) { top--; draw_list(); }
            } else {
                if (top + VIS < total) { top++; draw_list(); }
            }
            continue;
        }

        /* a list row? */
        if (my >= win_y + ROW_OFF && my < win_y + ROW_OFF + VIS * ROW_H
            && mx >= win_x && mx < win_x + WIN_W) {
            vis = (my - (win_y + ROW_OFF)) / ROW_H;
            idx = top + vis;
            if (idx >= total) continue;
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
}
