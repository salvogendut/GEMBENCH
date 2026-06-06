/* notepad - the GEOBENCH text editor (C), pointer-driven (#34).
 *
 * The top bar shows a "File" menu (New / Load / Save) drawn by the kernel; click
 * it to drop the menu down. Click in the text to place the insertion point, then
 * type to insert there (Backspace deletes before it). On the CPC the pointer is
 * the arrow keys, so positioning the caret is by clicking, not by cursor keys.
 *
 *   File > New     empty buffer, name UNTITLED.TXT
 *   File > Load     pick a file from a list and open it
 *   File > Save     write the buffer (creates / grows the file via the new
 *                   AMSDOS write layer)
 *   Ctrl-Q          quit back to the file manager
 *
 * Input is GB_POLL (pointer + click + the menu callback) plus GB_GETKEY for
 * typing. The view scrolls to keep the caret visible. */
#include "gb.h"

#define NP_MAX    1024
#define WIN_X     2
#define WIN_Y     14
#define WIN_W     76
#define WIN_H     180
#define TX_COL    4
#define TX_Y0     28
#define LINE_H    10
#define MAX_LINES 14
#define WRAP      44

#define K_ENTER   0x0D
#define K_BS      0x08
#define K_DEL     0x7F
#define K_QUIT    0x11           /* Ctrl-Q */

#define MENU_COL  10             /* "File" title column in the top bar */
#define MENU_END  16

static char buf[NP_MAX];
static char line[WRAP + 2];
static unsigned int len, cur;            /* text length, insertion index */
static unsigned char view_first;         /* first visible display row */
static unsigned char dirty, status;      /* 0 none, 1 saved, 2 failed */
static unsigned char want_menu, modal;   /* File clicked; in a modal loop */

/* the kernel-drawn top-bar menu: one title "File" at MENU_COL */
static const unsigned char file_menu[] = { 1, MENU_COL, 'F','i','l','e',0,0,0,0 };

/* pos_of: display (row,col) of buffer index idx (wrap + newlines). */
static void pos_of(unsigned int idx, unsigned char *prow, unsigned char *pcol)
{
    unsigned int i;
    unsigned char col = 0, row = 0, ch;
    for (i = 0; i < idx; i++) {
        ch = buf[i];
        if (ch == '\n') { row++; col = 0; }
        else if (ch >= 32) { if (++col == WRAP) { row++; col = 0; } }
    }
    *prow = row; *pcol = col;
}

/* idx_of: buffer index nearest the display position (trow,tcol). */
static unsigned int idx_of(unsigned char trow, unsigned char tcol)
{
    unsigned int i;
    unsigned char col = 0, row = 0, ch;
    for (i = 0; i < len; i++) {
        if (row == trow && col >= tcol) return i;
        ch = buf[i];
        if (ch == '\n') { if (row == trow) return i; row++; col = 0; }
        else if (ch >= 32) { if (++col == WRAP) { row++; col = 0; } }
        if (row > trow) return i;
    }
    return len;
}

static void cursor_at(unsigned char col, unsigned char row)
{
    gb_fill(TX_COL + (col * 3) / 2, TX_Y0 + row * LINE_H + 7, 2, 2, 3);
}

static void status_line(void)
{
    gb_text(TX_COL, WIN_Y + WIN_H - 11,
            status == 1 ? "saved" :
            status == 2 ? "SAVE FAILED" :
                          "Click text to place caret. Ctrl-Q=quit");
}

/* draw: full repaint - window, the visible rows (scrolled to keep the caret in
   view), status line, and the caret. */
static void draw(void)
{
    unsigned int i;
    unsigned char col = 0, row = 0, scr, currow, curcol;

    pos_of(cur, &currow, &curcol);               /* scroll to show the caret */
    if (currow < view_first) view_first = currow;
    else if (currow >= view_first + MAX_LINES) view_first = currow - MAX_LINES + 1;

    gb_window(WIN_X, WIN_Y, WIN_W, WIN_H, dirty ? "NOTEPAD *" : "NOTEPAD");
    status_line();

    for (i = 0; i <= len; i++) {                  /* <= len: flush the last line */
        if (i == len || buf[i] == '\n' ||
            (buf[i] >= 32 && col == WRAP)) {
            if (row >= view_first && row - view_first < MAX_LINES) {
                line[col] = 0;
                gb_text(TX_COL, TX_Y0 + (row - view_first) * LINE_H, line);
            }
            if (i == len) break;
            if (buf[i] == '\n') { row++; col = 0; continue; }
            row++; col = 0;                        /* wrap: fall through to place buf[i] */
        }
        if (buf[i] >= 32) {
            if (row >= view_first && col < WRAP) line[col] = buf[i];
            col++;
        }
    }
    scr = currow - view_first;
    cursor_at(curcol, scr);
}

/* insert one char at the caret; grow the buffer right. */
static void ins(char c)
{
    unsigned int i;
    if (len >= NP_MAX) return;
    for (i = len; i > cur; i--) buf[i] = buf[i - 1];
    buf[cur] = c;
    len++; cur++;
    dirty = 1; status = 0;
}

static void del_back(void)
{
    unsigned int i;
    if (cur == 0) return;
    for (i = cur; i < len; i++) buf[i - 1] = buf[i];
    len--; cur--;
    dirty = 1; status = 0;
}

/* 8.3 helpers: turn a "NAME.EXT" string (from gb_dir*) into an 11-byte name. */
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

/* on_menu: kernel callback on a top-bar click. If it hit the File title, ask the
   main loop to drop the menu (not while another modal popup is up). */
static void on_menu(void)
{
    if (modal) return;
    if (gb_msg.type == GB_MSG_MENU &&
        gb_msg.p0 >= MENU_COL && gb_msg.p0 < MENU_END)
        want_menu = 1;
}

/* popup: draw a framed list at (x,y), n items from labels[], and run a pointer
   loop until the user clicks one (-> its index) or clicks away (-> 0xFF). */
static unsigned char popup(unsigned char x, unsigned char y,
                           const char *const *labels, unsigned char n)
{
    unsigned char i, flags, row, sel = 0xFF;
    modal = 1;
    gb_curhide();
    gb_fill(x, y, 18, n * LINE_H + 4, 1);         /* white box + black frame */
    gb_frame(x, y, 18, n * LINE_H + 4, 2);
    for (i = 0; i < n; i++)
        gb_text(x + 1, y + 2 + i * LINE_H, labels[i]);
    gb_curshow();
    for (;;) {
        flags = gb_poll();
        if (!(flags & GB_CLICK)) continue;
        if (gb_my() >= y + 2 && gb_my() < y + 2 + n * LINE_H &&
            gb_mx() >= x && gb_mx() < x + 18) {
            row = (gb_my() - (y + 2)) / LINE_H;
            if (row < n) { sel = row; break; }
        }
        break;                                     /* clicked outside -> cancel */
    }
    modal = 0;
    return sel;
}

static const char *const file_items[] = { "New", "Load", "Save" };

static void do_save(void)
{
    status = gb_fs_save(buf, len) ? 1 : 2;
    if (status == 1) dirty = 0;
}

static void do_new(void)
{
    len = 0; cur = 0; view_first = 0; dirty = 0; status = 0;
    gb_set_name("UNTITLEDTXT");
}

/* do_load: list directory entries in a popup; open the one clicked. */
static void do_load(void)
{
    const char *names[MAX_LINES];
    static char store[MAX_LINES][14];
    char *p;
    unsigned char n = 0, i, sel;

    p = gb_dir1();
    while (p && n < MAX_LINES) {
        for (i = 0; i < 13 && p[i]; i++) store[n][i] = p[i];
        store[n][i] = 0;
        names[n] = store[n];
        n++;
        p = gb_dirn();
    }
    if (!n) return;
    sel = popup(WIN_X + 6, TX_Y0, names, n);
    if (sel == 0xFF) return;
    to_83(store[sel]);
    gb_set_name(name83);
    len = gb_fs_load(buf, NP_MAX);
    cur = 0; view_first = 0; dirty = 0; status = 0;
}

/* run_menu: drop the File menu and dispatch the chosen item. */
static void run_menu(void)
{
    unsigned char sel = popup(MENU_COL, 8, file_items, 3);
    if (sel == 0) do_new();
    else if (sel == 1) do_load();
    else if (sel == 2) do_save();
}

void main(void)
{
    unsigned char flags, c, n;

    len = gb_fs_load(buf, NP_MAX);
    cur = len; view_first = 0; dirty = 0; status = 0;
    want_menu = 0; modal = 0;
    for (n = 64; n; n--) if (!gb_getkey()) break;   /* drop buffered keys */

    gb_on_event(on_menu);
    gb_menu(file_menu);
    draw();
    gb_curshow();

    for (;;) {
        flags = gb_poll();

        if (want_menu) {                            /* File title was clicked */
            want_menu = 0;
            run_menu();
            draw();
            gb_curshow();
            continue;
        }

        if (flags & GB_CLICK) {                     /* click in text -> caret */
            unsigned char my = gb_my(), mx = gb_mx();
            if (my >= TX_Y0 && my < TX_Y0 + MAX_LINES * LINE_H && mx >= TX_COL) {
                unsigned char row = view_first + (my - TX_Y0) / LINE_H;
                unsigned char col = ((mx - TX_COL) * 2) / 3;
                gb_curhide();
                cur = idx_of(row, col);
                draw();
                gb_curshow();
            }
        }

        n = 8;                                       /* drain typed keys */
        while (n--) {
            c = gb_getkey();
            if (!c) break;
            if (c == K_QUIT) return;
            gb_curhide();
            if (c == K_BS || c == K_DEL) del_back();
            else if (c == K_ENTER) ins('\n');
            else if (c >= 32 && c < 127) ins((char)c);
            draw();
            gb_curshow();
        }
    }
}
