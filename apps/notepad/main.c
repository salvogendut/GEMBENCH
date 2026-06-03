/* notepad - the GEOBENCH text editor (C), and the first app that writes to disk.
 *
 * Launched by the file manager when a .TXT is double-clicked. Loads the file
 * (gb_fs_load), shows it word-wrapped with a red underline cursor, and edits it
 * from the keyboard (gb_getkey):
 *
 *   printable keys   append a character
 *   Enter            newline
 *   Delete/Backspace remove the last character
 *   Ctrl-S           save (overwrites in place; the title shows * when unsaved)
 *   ESC              quit back to the file manager
 *
 * The view scrolls to keep the end of the text (where editing happens) on
 * screen. v1 edits at the end (append / backspace); mid-text cursor movement is
 * a follow-up. Save overwrites in place, so the text must fit the file's current
 * disk allocation.
 *
 * It paces with gb_vsync (no pointer) and reads only the keyboard, so the
 * desktop's pointer/joystick never disturb it. */
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

/* count_lines: index of the last display line (total lines = result + 1), with
   the same wrap rule the renderer uses. */
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

/* draw: window + the last screenful of text (so the end stays visible), then a
   red underline cursor at the end of the text. */
static void draw(void)
{
    unsigned int i;
    unsigned char ch, col = 0, lineno = 0, row = 0, first, total;
    unsigned char curcol = 0, currow = 0, cx;

    total = count_lines();
    first = (total >= MAX_LINES) ? (total - MAX_LINES + 1) : 0;

    gb_window(WIN_X, WIN_Y, WIN_W, WIN_H, dirty ? "NOTEPAD *" : "NOTEPAD");
    gb_text(TX_COL, WIN_Y + WIN_H - 11, "Ctrl-S=save  ESC=quit");

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
    if (lineno >= first && row < MAX_LINES) {   /* the partial last line */
        line[col] = 0;
        gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
        curcol = col; currow = row;
    }

    cx = TX_COL + (curcol * 3) / 2;             /* ~cursor pixel column / 4 */
    gb_fill(cx, TX_Y0 + currow * LINE_H + 7, 2, 2, 3);   /* red underline */
}

void main(void)
{
    unsigned char c, n, changed;

    gb_curhide();
    len = gb_fs_load(buf, NP_MAX);
    dirty = 0;
    for (n = 64; n; n--)                        /* drop keys buffered while navigating */
        if (!gb_getkey()) break;
    draw();

    for (;;) {
        gb_vsync();                             /* pace 50 Hz, no pointer */
        changed = 0;
        for (n = 32; n; n--) {                  /* drain a bounded burst of typed keys */
            c = gb_getkey();
            if (!c) break;
            if (c == K_ESC) return;
            if (c == K_SAVE) {
                if (gb_fs_save(buf, len)) dirty = 0;
                changed = 1;
            } else if (c == K_DEL || c == K_BS) {
                if (len) { len--; dirty = 1; changed = 1; }
            } else if (c == K_ENTER) {
                if (len < NP_MAX) { buf[len++] = '\n'; dirty = 1; changed = 1; }
            } else if (c >= 32 && c < 127) {
                if (len < NP_MAX) { buf[len++] = (char)c; dirty = 1; changed = 1; }
            }
            /* other keys (cursor, etc.) are ignored - no redraw */
        }
        if (changed) draw();
    }
}
