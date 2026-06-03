/* notepad - the GEOBENCH text editor (C), and the first app that writes to disk.
 *
 * Launched by the file manager when a .TXT is double-clicked. Loads the file
 * (gb_fs_load), shows it word-wrapped with a red underline cursor, and edits it
 * from the keyboard (gb_getkey):
 *
 *   printable keys   append a character
 *   Enter            newline
 *   Delete/Backspace remove the last character
 *   Ctrl-S           save (overwrites in place; the status line reports the result)
 *   ESC              quit back to the file manager
 *
 * The view scrolls so the end of the text (where editing happens) stays visible.
 * Typing within a line repaints only that line; the whole window is redrawn only
 * on a newline, a scroll, or a save. It paces with gb_vsync (no pointer), reads
 * only the keyboard, and quits when gb_vsync reports ESC held - so the desktop's
 * pointer/joystick never disturb it.
 *
 * v1 edits at the end (append / backspace); mid-text cursor movement is a
 * follow-up. Save overwrites in place, so the text must fit the file's current
 * disk allocation. */
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
#define K_DEL     0x7F
#define K_BS      0x08
#define K_SAVE    0x13   /* Ctrl-S */
#define K_ESC     0x1B

static char buf[NP_MAX];
static char line[WRAP + 2];
static unsigned int len;
static unsigned char dirty;
static unsigned char status;       /* 0 none, 1 saved, 2 save failed */
static unsigned char prev_total;   /* line count at the last full draw */

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

static void status_line(void)
{
    gb_text(TX_COL, WIN_Y + WIN_H - 11,
            status == 1 ? "saved" :
            status == 2 ? "SAVE FAILED - too big to fit" :
                          "Ctrl-S=save  ESC=quit");
}

static void cursor_at(unsigned char col, unsigned char row)
{
    gb_fill(TX_COL + (col * 3) / 2, TX_Y0 + row * LINE_H + 7, 2, 2, 3);
}

/* draw: full repaint - window, the last screenful of text, status, cursor. */
static void draw(void)
{
    unsigned int i;
    unsigned char ch, col = 0, lineno = 0, row = 0, first, total;
    unsigned char curcol = 0, currow = 0;

    total = count_lines();
    prev_total = total;
    first = (total >= MAX_LINES) ? (total - MAX_LINES + 1) : 0;

    gb_window(WIN_X, WIN_Y, WIN_W, WIN_H, dirty ? "NOTEPAD *" : "NOTEPAD");
    status_line();

    for (i = 0; i < len; i++) {
        ch = buf[i];
        if (ch == '\n') {
            if (lineno >= first && row < MAX_LINES) {
                line[col] = 0;
                gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
                row++;
            }
            col = 0; lineno++;
        } else if (ch >= 32) {
            if (lineno >= first) line[col] = ch;
            if (++col == WRAP) {
                if (lineno >= first && row < MAX_LINES) {
                    line[col] = 0;
                    gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
                    row++;
                }
                col = 0; lineno++;
            }
        }
    }
    if (lineno >= first && row < MAX_LINES) {
        line[col] = 0;
        gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
        curcol = col; currow = row;
    }
    cursor_at(curcol, currow);
}

/* draw_tail: repaint just the current (last) line - used when an append/backspace
   doesn't change the line count, so the whole window needn't flicker. */
static void draw_tail(void)
{
    unsigned int i, ls = 0;
    unsigned char ch, col = 0, lineno = 0, first, currow;

    for (i = 0; i < len; i++) {
        ch = buf[i];
        if (ch == '\n') { lineno++; col = 0; ls = i + 1; }
        else if (ch >= 32) { if (++col == WRAP) { lineno++; col = 0; ls = i + 1; } }
    }
    first = (lineno >= MAX_LINES) ? (lineno - MAX_LINES + 1) : 0;
    currow = lineno - first;

    col = 0;
    for (i = ls; i < len; i++) { ch = buf[i]; if (ch >= 32) line[col++] = ch; }
    line[col] = 0;

    gb_fill(WIN_X + 1, TX_Y0 + currow * LINE_H, WIN_W - 2, LINE_H, 0); /* clear line */
    gb_text(TX_COL, TX_Y0 + currow * LINE_H, line);
    cursor_at(col, currow);
    status_line();
}

void main(void)
{
    unsigned char c, n, edited, need_full, t;

    gb_curhide();
    len = gb_fs_load(buf, NP_MAX);
    dirty = 0; status = 0;
    for (n = 64; n; n--)               /* drop keys buffered while navigating here */
        if (!gb_getkey()) break;
    draw();

    for (;;) {
        if (gb_vsync()) return;        /* pace + reliable ESC via the key matrix */
        edited = 0; need_full = 0;
        for (n = 32; n; n--) {
            c = gb_getkey();
            if (!c) break;
            if (c == K_ESC) return;
            if (c == K_SAVE) {
                status = gb_fs_save(buf, len) ? 1 : 2;
                if (status == 1) dirty = 0;
                edited = 1; need_full = 1;
            } else if (c == K_DEL || c == K_BS) {
                if (len) { len--; dirty = 1; status = 0; edited = 1; }
            } else if (c == K_ENTER) {
                if (len < NP_MAX) { buf[len++] = '\n'; dirty = 1; status = 0; edited = 1; need_full = 1; }
            } else if (c >= 32 && c < 127) {
                if (len < NP_MAX) { buf[len++] = (char)c; dirty = 1; status = 0; edited = 1; }
            }
            /* other keys (cursor, etc.) are ignored - no redraw */
        }
        if (edited) {
            t = count_lines();
            if (need_full || t != prev_total) draw();   /* draw() updates prev_total */
            else draw_tail();
        }
    }
}
