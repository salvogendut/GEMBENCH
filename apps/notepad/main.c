/* notepad - the GEOBENCH text editor (C), and the first app that writes to disk.
 *
 * Launched by the file manager when a .TXT is double-clicked. Loads the file
 * (gb_fs_load), shows it word-wrapped with a cursor, and edits it from the
 * keyboard (gb_getkey):
 *
 *   printable keys  append a character
 *   Enter           newline
 *   Delete/Backspace remove the last character
 *   Ctrl-S          save (overwrites the file in place; the title shows * when
 *                   there are unsaved changes)
 *   ESC             quit back to the file manager
 *
 * v1 edits at the end of the buffer (append / backspace); mid-text cursor
 * movement and scrolling past one screenful are follow-ups. Save overwrites in
 * place, so the text must fit the file's existing disk allocation. */
#include "gb.h"

#define NP_MAX    1024   /* edit buffer */
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

/* draw: window + the buffer, word-wrapped, with a '_' cursor at the end. */
static void draw(void)
{
    unsigned int i = 0;
    unsigned char row = 0, col = 0, c;

    gb_window(WIN_X, WIN_Y, WIN_W, WIN_H, dirty ? "NOTEPAD *" : "NOTEPAD");
    gb_text(TX_COL, WIN_Y + WIN_H - 11, "Ctrl-S=save  ESC=quit");

    while (i < len && row < MAX_LINES) {
        c = buf[i++];
        if (c == '\n') {
            line[col] = 0;
            gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
            row++; col = 0;
            continue;
        }
        if (c < 32) continue;
        line[col++] = c;
        if (col == WRAP) {
            line[col] = 0;
            gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
            row++; col = 0;
        }
    }
    if (row < MAX_LINES) {              /* the partial line + the cursor marker */
        line[col++] = '_';
        line[col] = 0;
        gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
    }
}

void main(void)
{
    unsigned char k;

    gb_curhide();                      /* a keyboard editor: no pointer */
    len = gb_fs_load(buf, NP_MAX);
    dirty = 0;
    draw();

    for (;;) {
        k = gb_getkey();
        if (!k) continue;
        if (k == K_ESC) return;
        if (k == K_SAVE) {
            if (gb_fs_save(buf, len)) dirty = 0;
            draw();
            continue;
        }
        if (k == K_DEL || k == K_BS) {
            if (len) { len--; dirty = 1; draw(); }
            continue;
        }
        if (k == K_ENTER) {
            if (len < NP_MAX) { buf[len++] = '\n'; dirty = 1; draw(); }
            continue;
        }
        if (k >= 32 && k < 127) {
            if (len < NP_MAX) { buf[len++] = (char)k; dirty = 1; draw(); }
        }
    }
}
