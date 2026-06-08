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
 *   Ctrl-Q          close the window (back to the file manager)
 *
 * Issue #45: a co-resident window. main() loads the file, registers via gb_wm_add
 * and returns; the kernel WM loop calls on_frame (read input with gb_flags/mx/my)
 * and np_repaint to restack us. The modal popups (menu, Load, confirm) still poll
 * themselves. Click our window to focus it; the view scrolls to keep the caret
 * visible. */
#include "gb.h"

#define NP_MAX    4096           /* editable text capacity (was 1024); fits the app's
                                    #6000-#7FFF data window with room to spare */
#define NP_BUF    (NP_MAX + 512)  /* +1 sector of slack: gb_fs_load copies whole 512B
                                    sectors, so the buffer outruns the load cap */
#define DEF_X     2            /* initial window position (the window is draggable) */
#define DEF_Y     14
#define DEF_W     66           /* default size; the window is resizeable (#81) */
#define DEF_H     158
#define MIN_W     30
#define MIN_H     72
#define TITLE_H   14
#define LINE_H    10
#define MAX_LINES ((win_h - TITLE_H - 13) / LINE_H)   /* visible text rows (runtime) */
#define WRAP      ((win_w - 4) * 2 / 3)               /* chars per wrapped line (runtime) */
#define MAXWRAP   52           /* line[] cap = max WRAP (80-col window) */
#define MAXVIS    18           /* names[] cap = max MAX_LINES */
/* text origin, relative to the live (draggable) window position */
#define TX_COL    (win_x + 2)
#define TX_Y0     (win_y + TITLE_H)

#define K_ENTER   0x0D
#define K_BS      0x08
#define K_DEL     0x7F
#define K_TAB     0x09
#define K_QUIT    0x11           /* Ctrl-Q */

#define MENU_COL  10             /* "File" title column in the top bar */
#define MENU_END  16

static unsigned char win_x = DEF_X;      /* live window position (draggable) */
static unsigned char win_y = DEF_Y;
static unsigned char win_w = DEF_W, win_h = DEF_H;   /* live size (resizeable, #81) */
static char buf[NP_BUF];
static char line[MAXWRAP];
static unsigned int len, cur;            /* text length, insertion index */
static unsigned char view_first;         /* first visible display row */
static unsigned char dirty, status;      /* 0 none, 1 saved, 2 failed */
static unsigned char want_menu, modal, close_menu; /* File clicked / modal / close it */
static unsigned char keycool;            /* frames to flush keys after a click or fire */
static unsigned char prev_total;         /* display-row count at the last full draw */
static char fbase[14];                    /* "NAME.EXT" of the open file (title base) */
static char wtitle[18];                   /* fbase + " *" when dirty (window title) */
static unsigned char blink_ctr, caret_vis, cur_scr, cur_col;  /* caret blink (#86) */
#define BLINK_FRAMES 16                   /* ~3 Hz caret blink at 50 fps */

/* arrow-key caret nav (#86): the pointer PLACES the caret, the keyboard arrows
   NUDGE it. We read the cursor keys straight off the matrix (KM_TEST_KEY) rather
   than re-arming them globally - re-arming would re-flood every app on pointer
   moves (the very thing disarm_joy_keys prevents). */
#define A_UP      0
#define A_DOWN    1
#define A_LEFT    2
#define A_RIGHT   3
#define REP_DELAY 14                      /* frames held before a key auto-repeats */
#define REP_RATE  3                       /* frames between repeats */
static unsigned char arr_prev, arr_rep, arr_bits;

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

/* The underscore cursor sits in the inter-line gap (row +8, below the 8px glyph)
   so the blink can erase just its cell without ever nicking a character. */
static void cursor_at(unsigned char col, unsigned char row)
{
    gb_fill(TX_COL + (col * 3) / 2, TX_Y0 + row * LINE_H + 8, 2, 2, 3);
}

/* caret_erase: clear just the cursor cell (blink-off) - no line repaint, so the
   text doesn't flash every blink. Glyph-safe because the cursor is in the gap. */
static void caret_erase(void)
{
    gb_fill(TX_COL + (cur_col * 3) / 2, TX_Y0 + cur_scr * LINE_H + 8, 2, 2, 0);
}

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

/* win_title: the window title = the file name, with " *" appended when unsaved. */
static const char *win_title(void)
{
    unsigned char i = 0, j = 0;
    while (fbase[i]) wtitle[j++] = fbase[i++];
    if (dirty) { wtitle[j++] = ' '; wtitle[j++] = '*'; }
    wtitle[j] = 0;
    return wtitle;
}

static void status_line(void)
{
    gb_text(TX_COL, win_y + win_h - 11,
            status == 1 ? "saved" :
            status == 2 ? "SAVE FAILED" :
                          "Click text to place caret. Ctrl-Q=quit");
}

/* count_lines: index of the last display row (newlines + wraps). */
static unsigned char count_lines(void)
{
    unsigned int i;
    unsigned char col = 0, n = 0, ch;
    for (i = 0; i < len; i++) {
        ch = buf[i];
        if (ch == '\n') { n++; col = 0; }
        else if (ch >= 32) { if (++col == WRAP) { n++; col = 0; } }
    }
    return n;
}

/* scroll_to_caret: adjust view_first so the caret's row is on screen. */
static void scroll_to_caret(void)
{
    unsigned char r, c;
    pos_of(cur, &r, &c);
    if (r < view_first) view_first = r;
    else if (r >= view_first + MAX_LINES) view_first = r - MAX_LINES + 1;
}

/* render: paint the text using the current view_first. only==0xFF -> full (frame,
   status, every visible row); otherwise repaint just that screen row (clearing it
   first) - used for a single-line edit so typing doesn't flash the whole window.
   Always (re)draws the caret. */
static void render(unsigned char only)
{
    unsigned int i;
    unsigned char col = 0, row = 0, scr, currow, curcol;

    pos_of(cur, &currow, &curcol);
    if (only == 0xFF) {
        gb_window(win_x, win_y, win_w, win_h, win_title());
        status_line();
        gb_draw_grip(win_x, win_y, win_w, win_h);   /* resize grip (#81) */
    }
    for (i = 0; i <= len; i++) {                  /* <= len: flush the last line */
        if (i == len || buf[i] == '\n' ||
            (buf[i] >= 32 && col == WRAP)) {
            if (row >= view_first && row - view_first < MAX_LINES) {
                scr = row - view_first;
                if (only == 0xFF || scr == only) {
                    line[col] = 0;
                    if (only != 0xFF)             /* clear just this line first */
                        gb_fill(win_x + 1, TX_Y0 + scr * LINE_H, win_w - 2, LINE_H, 0);
                    gb_text(TX_COL, TX_Y0 + scr * LINE_H, line);
                }
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
    cur_scr = scr; cur_col = curcol;     /* remember for the blink redraw (#86) */
    cursor_at(curcol, scr);
}

/* draw: full repaint (scroll to the caret, then render everything). */
static void draw(void)
{
    caret_vis = 1; blink_ctr = 0;        /* caret solid right after any redraw (#86) */
    scroll_to_caret();
    render(0xFF);
    prev_total = count_lines();
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
    if (gb_msg.type != GB_MSG_MENU) return;
    if (gb_msg.p0 < MENU_COL || gb_msg.p0 >= MENU_END) return;
    if (modal) close_menu = 1;   /* clicking File again while open -> close it */
    else       want_menu = 1;
}

/* popup: draw a framed list at (x,y), n items from labels[], and run a pointer
   loop until the user clicks one (-> its index) or clicks away (-> 0xFF). */
static unsigned char popup(unsigned char x, unsigned char y,
                           const char *const *labels, unsigned char n)
{
    unsigned char i, flags, row, sel = 0xFF, esc = 0;
    modal = 1; close_menu = 0;
    gb_curhide();
    gb_fill(x, y, 18, n * LINE_H + 4, 1);         /* white box + black frame */
    gb_frame(x, y, 18, n * LINE_H + 4, 2);
    for (i = 0; i < n; i++)
        gb_text(x + 1, y + 2 + i * LINE_H, labels[i]);
    gb_curshow();
    for (;;) {
        flags = gb_poll();
        if (flags & GB_QUIT) { esc = 1; break; }      /* ESC closes the menu */
        if (close_menu) break;                         /* clicked File again -> close */
        if (!(flags & GB_CLICK)) continue;
        if (gb_my() >= y + 2 && gb_my() < y + 2 + n * LINE_H &&
            gb_mx() >= x && gb_mx() < x + 18) {
            row = (gb_my() - (y + 2)) / LINE_H;
            if (row < n) { sel = row; break; }
        }
        break;                                         /* clicked elsewhere -> cancel */
    }
    modal = 0;
    if (esc) while (gb_poll() & GB_QUIT) ;         /* swallow ESC (gb_poll keeps the
                                                      cursor's save-under consistent) */
    gb_curhide();                                   /* erase the cursor cleanly */
    gb_fill(x, y, 18, n * LINE_H + 4, 0);          /* erase the popup box */
    keycool = 4;                                    /* flush the click's buffered chars */
    return sel;                                     /* returns with the cursor hidden;
                                                      the caller's draw + gb_curshow
                                                      re-shows it exactly once */
}

static const char *const file_items[] = { "New", "Load", "Save", "Save As" };

static void do_save(void)
{
    status = gb_fs_save(buf, len) ? 1 : 2;
    if (status == 1) dirty = 0;
}

/* ensure_ext: a name with no '.' gets a ".TXT" default (8.3, room permitting). */
static char namebuf[16];
static void ensure_ext(void)
{
    unsigned char i = 0, has = 0;
    while (namebuf[i]) { if (namebuf[i] == '.') has = 1; i++; }
    if (!has && i && i <= 8) {
        namebuf[i++] = '.'; namebuf[i++] = 'T'; namebuf[i++] = 'X'; namebuf[i++] = 'T';
        namebuf[i] = 0;
    }
}

/* prompt_name: modal name-entry box. Types an uppercase 8.3 name into namebuf;
   Enter (non-empty) -> 1, ESC/empty -> 0. Black-on-white, like the other dialogs. */
static unsigned char prompt_name(const char *caption)
{
    unsigned char x = 12, y = 64, w = 52, h = 34;
    unsigned char fl = 0, c, n = 0, done = 0, ok = 0, redraw = 1;
    modal = 1;
    namebuf[0] = 0;
    while (gb_getkey()) ;                 /* drop the menu click's keys */
    gb_curhide();
    gb_fill(x, y, w, h, 1);               /* white box + black frame */
    gb_frame(x, y, w, h, 2);
    gb_textbw(x + 2, y + 3, caption);
    gb_curshow();
    while (!done) {
        if (redraw) {
            gb_curhide();
            gb_fill(x + 2, y + 16, w - 4, 8, 1);   /* clear the field (white) */
            gb_textbw(x + 2, y + 16, namebuf);
            gb_curshow();
            redraw = 0;
        }
        fl = gb_poll();
        if (fl & GB_QUIT) { done = 1; break; }      /* ESC -> cancel */
        while ((c = gb_getkey()) != 0) {
            if (c == K_ENTER) { done = 1; ok = (unsigned char)(n > 0); break; }
            else if ((c == K_BS || c == K_DEL) && n) { namebuf[--n] = 0; redraw = 1; }
            else if (c >= 32 && c < 127 && n < 12) {
                if (c >= 'a' && c <= 'z') c = (unsigned char)(c - 32);   /* 8.3 is upper */
                namebuf[n++] = (char)c; namebuf[n] = 0; redraw = 1;
            }
        }
    }
    modal = 0;
    if (fl & GB_QUIT) while (gb_poll() & GB_QUIT) ;
    gb_curhide();
    gb_fill(x, y, w, h, 0);               /* erase the dialog */
    gb_curshow();
    keycool = 4;
    return ok;
}

/* set_file: namebuf "NAME[.EXT]" -> the current file name + title. */
static void set_file(void)
{
    ensure_ext();
    to_83(namebuf);
    gb_set_name(name83);
    fmt83(fbase, name83);
}

static void do_new(void)
{
    if (prompt_name("New file name:")) set_file();
    else { gb_set_name("UNTITLEDTXT"); fmt83(fbase, "UNTITLEDTXT"); }
    len = 0; cur = 0; view_first = 0; dirty = 0; status = 0;
}

static void do_saveas(void)
{
    if (!prompt_name("Save as:")) return;
    set_file();
    do_save();
}

/* is_binary: true if "NAME.EXT" has a known non-text extension (so Load skips it). */
static unsigned char is_binary(const char *name)
{
    static const char bin[9][4] = { "APP","BIN","IST","SPR","FNT","RAW","IMG","SNA","DSK" };
    const char *e = name;
    char ext[4];
    unsigned char i, k;
    while (*e && *e != '.') e++;
    if (*e != '.') return 0;             /* no extension -> treat as text */
    e++;
    for (i = 0; i < 3 && e[i] && e[i] != ' '; i++) ext[i] = e[i];
    ext[i] = 0;
    for (k = 0; k < 9; k++)
        if (bin[k][0] == ext[0] && bin[k][1] == ext[1] && bin[k][2] == ext[2])
            return 1;
    return 0;
}

/* do_load: list the (text) directory entries in a popup; open the one clicked. */
static void do_load(void)
{
    const char *names[MAXVIS];
    static char store[MAXVIS][14];
    char *p;
    unsigned char n = 0, i, sel;

    p = gb_dir1();
    while (p && n < MAX_LINES) {
        if (!is_binary(p)) {             /* skip .APP/.BIN/... - text files only (#86) */
            for (i = 0; i < 13 && p[i]; i++) store[n][i] = p[i];
            store[n][i] = 0;
            names[n] = store[n];
            n++;
        }
        p = gb_dirn();
    }
    if (!n) return;
    sel = popup(win_x + 6, TX_Y0, names, n);
    if (sel == 0xFF) return;
    to_83(store[sel]);
    gb_set_name(name83);
    fmt83(fbase, name83);                /* title -> the opened file's name */
    len = gb_fs_load(buf, NP_MAX);
    cur = 0; view_first = 0; dirty = 0; status = 0;
}

/* run_menu: drop the File menu and dispatch the chosen item. */
static void run_menu(void)
{
    unsigned char sel = popup(MENU_COL, 8, file_items, 4);
    if (sel == 0) do_new();
    else if (sel == 1) do_load();
    else if (sel == 2) do_save();
    else if (sel == 3) do_saveas();
}

/* confirm: "Save changes?" dialog -> 1 = YES, 0 = NO, 0xFF = cancelled (ESC). */
static unsigned char confirm(void)
{
    unsigned char flags, sel = 0xFF;
    unsigned char x = 28, y = 86, w = 26, h = 44;
    modal = 1;
    gb_curhide();
    gb_fill(x, y, w, h, 1);                       /* white box + black frame */
    gb_frame(x, y, w, h, 2);
    gb_text(x + 1, y + 4,  "Save changes?");
    gb_text(x + 3, y + 20, "YES");
    gb_text(x + 3, y + 32, "NO");
    gb_curshow();
    for (;;) {
        flags = gb_poll();
        if (flags & GB_QUIT) break;                       /* ESC -> cancel */
        if (!(flags & GB_CLICK)) continue;
        if (gb_mx() >= x && gb_mx() < x + w) {
            if (gb_my() >= y + 20 && gb_my() < y + 30) { sel = 1; break; }  /* YES */
            if (gb_my() >= y + 32 && gb_my() < y + 42) { sel = 0; break; }  /* NO  */
        }
        /* clicks elsewhere keep the dialog open */
    }
    modal = 0;
    if (sel == 0xFF) while (gb_poll() & GB_QUIT) ;   /* swallow ESC */
    gb_curhide();
    gb_fill(x, y, w, h, 0);                          /* erase the dialog */
    keycool = 4;
    return sel;
}

/* try_close: handle a click on the window close gadget. -> 1 if Notepad should
   quit, 0 to stay open. Prompts to save when there are unsaved edits. */
static unsigned char try_close(void)
{
    unsigned char ans;
    if (!dirty) return 1;                /* nothing changed -> just close */
    ans = confirm();
    if (ans == 0xFF) return 0;           /* cancelled -> stay open */
    if (ans == 0) return 1;              /* NO -> discard and close */
    do_save();                            /* YES -> save; close only if it worked */
    return (unsigned char)(status == 1);
}

/* cursor_over: is the pointer inside our window? (so the blink only lifts the
   pointer when it actually sits over the text - no per-blink pointer flicker.) */
static unsigned char cursor_over(void)
{
    unsigned char mx = gb_mx(), my = gb_my();
    return (unsigned char)(mx >= win_x && mx < win_x + win_w &&
                           my >= win_y && my < win_y + win_h);
}

/* read_arrows: matrix state of the four cursor keys -> arr_bits (bit0 up, 1 down,
   2 left, 3 right). KM_TEST_KEY (&BB1E): A = key number (72..75 = U/D/L/R), returns
   NZ when pressed. We talk to the matrix directly so the keys stay globally disarmed
   (no char-buffer flood) yet still reach us. Only A + arr_bits cross each call, so a
   KM_TEST_KEY register clobber can't corrupt the accumulator. */
static void read_arrows(void) __naked
{
__asm
    xor  a
    ld   (_arr_bits), a
    ld   a, #72            ; cursor up
    call #0xBB1E
    jr   z, 1$
    ld   a, (_arr_bits)
    or   #0x01
    ld   (_arr_bits), a
1$: ld   a, #73            ; cursor down
    call #0xBB1E
    jr   z, 2$
    ld   a, (_arr_bits)
    or   #0x02
    ld   (_arr_bits), a
2$: ld   a, #74            ; cursor left
    call #0xBB1E
    jr   z, 3$
    ld   a, (_arr_bits)
    or   #0x04
    ld   (_arr_bits), a
3$: ld   a, #75            ; cursor right
    call #0xBB1E
    jr   z, 4$
    ld   a, (_arr_bits)
    or   #0x08
    ld   (_arr_bits), a
4$: ret
__endasm;
}

/* move_caret: step the insertion point one cell in a direction. Up/Down keep the
   display column via the wrap-aware pos_of/idx_of; Left/Right walk the buffer. */
static void move_caret(unsigned char dir)
{
    unsigned char r, c;
    if (dir == A_LEFT)  { if (cur) cur--; }
    else if (dir == A_RIGHT) { if (cur < len) cur++; }
    else {
        pos_of(cur, &r, &c);
        if (dir == A_UP) { if (r) cur = idx_of((unsigned char)(r - 1), c); }
        else             cur = idx_of((unsigned char)(r + 1), c);   /* A_DOWN (clamps) */
    }
}

/* move_redraw: move the caret, then repaint just the old + new caret lines (or the
   whole window if the view scrolled), keeping the cursor solid + the blink reset. */
static void move_redraw(unsigned char dir)
{
    unsigned char oldscr = cur_scr, oldvf = view_first;
    move_caret(dir);
    caret_vis = 1; blink_ctr = 0;
    gb_curhide();
    scroll_to_caret();
    /* render() always (re)draws the caret at its current position, so repainting the
       OLD caret line both erases the old underscore and paints the new one (which sits
       on whatever line the caret moved to). A scroll needs the whole window. */
    if (view_first != oldvf) render(0xFF);
    else                     render(oldscr);
    gb_curshow();
}

/* handle_arrows: edge-detect + auto-repeat the cursor keys. Returns 1 if an arrow
   is engaged (caret moved or key held), so the caller skips typing/blink this frame. */
static unsigned char handle_arrows(void)
{
    unsigned char now, fresh, act = 0, dir;
    read_arrows();
    now = arr_bits;
    fresh = (unsigned char)(now & ~arr_prev);
    if (fresh) { arr_rep = REP_DELAY; act = fresh; }      /* new press -> move now */
    else if (now && now == arr_prev) {                    /* held -> maybe repeat */
        if (--arr_rep == 0) { arr_rep = REP_RATE; act = now; }
    }
    arr_prev = now;
    if (!act) return (unsigned char)(now ? 1 : 0);        /* held, not yet repeating */
    if (act & 1) dir = A_UP;
    else if (act & 2) dir = A_DOWN;
    else if (act & 4) dir = A_LEFT;
    else dir = A_RIGHT;
    move_redraw(dir);
    return 1;
}

/* np_repaint: kernel on_repaint - redraw the whole window (no input) when the WM
   restacks us behind/above another window. */
static void np_repaint(void)
{
    caret_vis = 1; blink_ctr = 0;        /* show the cursor solid after a restack */
    gb_curhide();
    render(0xFF);
    gb_curshow();
}

/* on_frame: one frame when Notepad is focused (kernel WM loop, issue #45). Reads
   input with gb_flags/mx/my; the modal popups (run_menu/confirm) still poll
   themselves. Each old loop 'continue' is a 'return'; quitting is gb_wm_close. */
static void on_frame(void)
{
    unsigned char flags = gb_flags(), c, n, edited;

    if (flags & GB_QUIT) { gb_wm_close(); return; }   /* ESC closes the window */

    if (want_menu) {                            /* File title was clicked */
        want_menu = 0;
        run_menu();
        draw();
        gb_curshow();
        return;
    }

    if (flags & GB_FIRE) keycool = 4;           /* fire held -> flush its 'Z'/'X' */
    if (flags & GB_CLICK) {
        unsigned char my = gb_my(), mx = gb_mx();
        /* text area bottom, precomputed flat: TX_Y0 + MAX_LINES*LINE_H is the summed
           (win_y+TITLE_H)+(win_h-...) form SDCC miscompiles - cf. the FM CT_BOT fix
           (#81). vis is a single win_h macro; TX_Y0 + a runtime value is safe. */
        unsigned char vis = MAX_LINES;
        unsigned char txbot = (unsigned char)(TX_Y0 + vis * LINE_H);
        keycool = 4;
        if (my >= win_y && my < win_y + TITLE_H &&  /* close gadget (title-bar left) */
            mx >= win_x && mx < win_x + 5) {
            if (try_close()) { gb_wm_close(); return; }  /* close the window */
            draw(); gb_curshow();                /* cancelled -> repaint */
            return;
        }
        if (gb_in_grip(win_x, win_y, win_w, win_h, mx, my)) {  /* resize grip (#81) */
            if (gb_drag_resize(win_x, win_y, &win_w, &win_h, MIN_W, MIN_H)) {
                gb_wm_setsize(win_w, win_h);     /* commit size + damage clip */
                gb_restore_parent();             /* repaint the stack */
                draw(); gb_curshow();
            }
            return;
        }
        if (my >= win_y && my < win_y + TITLE_H &&  /* title bar -> drag the window */
            mx >= win_x + 5 && mx < win_x + win_w) {
            if (gb_drag_window(&win_x, &win_y, win_w, win_h)) {
                gb_wm_setpos(win_x, win_y);      /* move our hit rect to follow */
                gb_restore_parent();             /* repaint the stack (incl. our window) */
            }
            return;
        }
        if (my >= TX_Y0 && my < txbot && mx >= TX_COL) {
            unsigned int nc = idx_of(view_first + (my - TX_Y0) / LINE_H,
                                     ((mx - TX_COL) * 2) / 3);
            if (nc != cur) {                     /* redraw only if the caret moved */
                cur = nc;
                gb_curhide(); draw(); gb_curshow();
            }
        }
        return;
    }

    if (keycool) {                               /* after a click/fire: drop the */
        keycool--;                                /* buffered fire/direction chars */
        while (gb_getkey()) ;
        return;
    }

    if (handle_arrows()) return;                 /* arrow nudged the caret (#86 item 6) */

    edited = 0;                                  /* drain typed keys */
    n = 8;
    while (n--) {
        c = gb_getkey();
        if (!c) break;
        if (c == K_QUIT) { gb_wm_close(); return; }
        if (c == K_BS || c == K_DEL) { del_back(); edited = 1; }
        else if (c == K_ENTER) { ins('\n'); edited = 1; }
        else if (c == K_TAB) { ins(' '); ins(' '); ins(' '); ins(' '); edited = 1; }
        else if (c >= 32 && c < 127) { ins((char)c); edited = 1; }
        /* other keys (arrows etc.) are ignored - no redraw */
    }
    if (edited) {
        unsigned char t = count_lines(), oldvf = view_first, cr, cc;
        caret_vis = 1; blink_ctr = 0;            /* caret solid while typing (#86) */
        gb_curhide();
        scroll_to_caret();
        pos_of(cur, &cr, &cc);
        if (t != prev_total || view_first != oldvf) {
            render(0xFF);                        /* line count or scroll changed */
            prev_total = t;
        } else {
            render(cr - view_first);             /* just the caret's line */
        }
        gb_curshow();
    } else if (++blink_ctr >= BLINK_FRAMES) {    /* idle -> blink the caret (#86) */
        unsigned char co = cursor_over();
        blink_ctr = 0;
        caret_vis ^= 1;
        if (co) gb_curhide();
        if (caret_vis) cursor_at(cur_col, cur_scr);
        else caret_erase();                      /* erase just the cell - no line flash */
        if (co) gb_curshow();
    }
}

/* a co-resident window (issue #45): on_repaint redraws it, on_event = the top-bar
   File click, menu = the File title the kernel shows while we are focused. */
static const gb_win_t npwin = {
    DEF_X, DEF_Y, DEF_W, DEF_H, on_frame, np_repaint, on_menu, file_menu
};

void main(void)
{
    unsigned char n;
    char raw[11];

    win_x = DEF_X; win_y = DEF_Y; win_w = DEF_W; win_h = DEF_H;
    caret_vis = 1; blink_ctr = 0; arr_prev = 0; arr_rep = 0;
    gb_wm_add(&npwin);                           /* register FIRST: captures our file arg
                                                   (per-window) + takes focus, so the load
                                                   below targets OUR file, not a sibling's */
    gb_get_name(raw);                            /* the file name we were launched with */
    len = gb_fs_load(buf, NP_MAX);              /* ...and its contents (0 if none) */
    fmt83(fbase, raw);                           /* show it in the title bar (#86) */
    if (!fbase[0]) {                             /* opened blank -> Untitled */
        fmt83(fbase, "UNTITLEDTXT");
        gb_set_name("UNTITLEDTXT");
    }
    cur = len; view_first = 0; dirty = 0; status = 0;
    want_menu = 0; modal = 0;
    for (n = 64; n; n--) if (!gb_getkey()) break;   /* drop buffered keys */

    draw();
    gb_curshow();
}
