/* filemgr - the GEOBENCH file manager, in C.
 *
 * Launched by the desktop when the Disk icon is double-clicked. Runs co-resident
 * in its own bank page, lists the active drive's directory in a window - a type
 * icon + name per entry - and SCROLLS when the list is taller than the window
 * (a footer pager: click the left half to scroll up, the right half down). A
 * click selects a row (red frame); a double-click launches the entry's app
 * (the kernel's type->app table). The close gadget or ESC quits.
 *
 * (Window-dragging from the old asm version is dropped for now: with scrolling
 * the fixed window reaches every file, and dragging needs the save-under buffer
 * + rubber-band. Easy to re-add later.) */
#include "gb.h"

#define WIN_X    4
#define WIN_Y    26
#define WIN_W    56
#define WIN_H    130
#define TITLE_H  14
#define ROW_OFF  18           /* first row, below the title bar */
#define ROW_H    18
#define VIS      5            /* visible rows (the rest scroll)  */
#define ICON_X   (WIN_X + 2)
#define NAME_X   (WIN_X + 11)
#define FOOT_Y   (WIN_Y + WIN_H - 12)   /* footer pager strip */
#define DCLICK   40           /* double-click window, frames */

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
    char *name;

    gb_curhide();
    gb_window(WIN_X, WIN_Y, WIN_W, WIN_H, "DISK A");

    /* footer pager: show the arrows that apply (ASCII only - the font is 32..127) */
    if (top > 0)             gb_text(WIN_X + 5, FOOT_Y, "^ up");
    if (top + VIS < total)   gb_text(WIN_X + WIN_W - 16, FOOT_Y, "dn v");

    name = gb_dir1();
    for (i = 0; i < top && name; i++) name = gb_dirn();   /* skip to 'top' */
    for (i = 0; i < VIS && name; i++) {
        y = WIN_Y + ROW_OFF + i * ROW_H;
        gb_blite(ICON_X, y);            /* the current entry's type icon */
        gb_text(NAME_X, y + 5, name);
        name = gb_dirn();
    }

    if (nsel) {                          /* red frame on the selected row */
        unsigned char s = nsel - 1;
        if (s >= top && s < top + VIS)
            gb_frame(WIN_X + 1, WIN_Y + ROW_OFF - 1 + (s - top) * ROW_H,
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
    nsel = 0;
    draw_list();
}

void main(void)
{
    unsigned char flags, mx, my, vis, idx;

    total = count_files();
    top = 0; nsel = 0; dc_timer = 0;
    draw_list();

    for (;;) {
        flags = gb_poll();
        if (dc_timer) dc_timer--;
        if (flags & GB_QUIT) return;
        if (!(flags & GB_CLICK)) continue;

        mx = gb_mx();
        my = gb_my();

        /* close gadget (top-left of the title bar) */
        if (my >= WIN_Y && my < WIN_Y + TITLE_H && mx >= WIN_X && mx < WIN_X + 4)
            return;

        /* footer pager: left half scrolls up, right half down */
        if (my >= FOOT_Y && my < FOOT_Y + 10) {
            if (mx < WIN_X + WIN_W / 2) {
                if (top > 0) { top--; draw_list(); }
            } else {
                if (top + VIS < total) { top++; draw_list(); }
            }
            continue;
        }

        /* a list row? */
        if (my >= WIN_Y + ROW_OFF && my < WIN_Y + ROW_OFF + VIS * ROW_H
            && mx >= WIN_X && mx < WIN_X + WIN_W) {
            vis = (my - (WIN_Y + ROW_OFF)) / ROW_H;
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
