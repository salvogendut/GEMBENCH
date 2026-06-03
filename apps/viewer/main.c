/* viewer - GEOBENCH text-file viewer, the first C app that does real work.
 *
 * Launched by the file manager when a file is double-clicked (and the type->app
 * table routes .TXT here). Runs co-resident in its own bank page, asks the
 * kernel to load the opened file into a bank buffer (gb_fs_load), and renders
 * the text in a window - word-wrapped, the first screenful. A click or ESC
 * closes it, back to the file manager.
 *
 * Binary files load fine too; they just show as gibberish (control bytes are
 * skipped), so this doubles as a quick "peek" at anything on the disk. */
#include "gb.h"

#define VIEW_MAX  6144   /* must match the max in gb_fs_load (gblib.s)        */
#define TX_COL    4      /* text start: byte column inside the window         */
#define TX_Y0     26     /* first text line (pixels), below the title bar     */
#define LINE_H    11     /* line pitch (pixels)                               */
#define MAX_LINES 14     /* visible lines (no scrolling yet)                  */
#define WRAP      44     /* characters per line before a forced wrap          */

static char filebuf[VIEW_MAX];
static char line[WRAP + 1];

/* render: lay out n bytes of filebuf as wrapped text lines in the window. */
static void render(unsigned int n)
{
    unsigned int i = 0;
    unsigned char row = 0, col = 0, c;

    while (i < n && row < MAX_LINES) {
        c = filebuf[i++];
        if (c == '\r') continue;            /* CR: ignore (CRLF -> LF)        */
        if (c == '\n') {                    /* LF: flush the line             */
            line[col] = 0;
            gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
            row++; col = 0;
            continue;
        }
        if (c < 32) continue;               /* other control bytes: skip      */
        line[col++] = c;
        if (col == WRAP) {                  /* wrap a long line               */
            line[col] = 0;
            gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
            row++; col = 0;
        }
    }
    if (col > 0 && row < MAX_LINES) {       /* flush a trailing partial line  */
        line[col] = 0;
        gb_text(TX_COL, TX_Y0 + row * LINE_H, line);
    }
}

void main(void)
{
    unsigned int n;

    gb_window(2, 14, 76, 180, "VIEWER");
    n = gb_fs_load(filebuf);
    if (n == 0)
        gb_text(TX_COL, TX_Y0, "(file is empty or could not be read)");
    else
        render(n);

    gb_curshow();
    while (!(gb_poll() & (GB_QUIT | GB_CLICK))) {
        /* idle until ESC or a click closes the viewer */
    }
}
