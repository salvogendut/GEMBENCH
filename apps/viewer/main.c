/* viewer - GEOBENCH text-file viewer, the first C app that does real work.
 *
 * Launched by the file manager for any non-.TXT file (the type->app default).
 * Issue #45: a co-resident window - main() loads the file, renders it, registers
 * with gb_wm_add and returns; the kernel WM loop drives on_frame / on_repaint.
 * The close gadget (title-bar left) or ESC closes it; other clicks just focus it.
 *
 * Binary files load fine too; they just show as gibberish (control bytes are
 * skipped), so this doubles as a quick "peek" at anything on the disk. */
#include "gb.h"

#define VIEW_MAX  6144   /* file buffer size; also the load cap passed to gb_fs_load */
#define TX_COL    4      /* text start: byte column inside the window         */
#define TX_Y0     26     /* first text line (pixels), below the title bar     */
#define LINE_H    11     /* line pitch (pixels)                               */
#define MAX_LINES ((win_h - 16) / LINE_H)       /* visible text rows (runtime) */
#define WRAP      ((win_w - 9) * 2 / 3)          /* chars per line (runtime)    */
#define MAXWRAP   48     /* line[] cap = max WRAP at 80-col                    */

#define WIN_X     2
#define WIN_Y     14
#define DEF_W     76     /* default size; the window is resizeable (#81)      */
#define DEF_H     180
#define MIN_W     30
#define MIN_H     72
#define TITLE_H   14

static char filebuf[VIEW_MAX];
static char line[MAXWRAP];
static unsigned int filen;       /* bytes loaded (for repaint) */
static unsigned char win_w = DEF_W, win_h = DEF_H;   /* live size (resizeable) */

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

/* paint the whole window (title + text). */
static void v_draw(void)
{
    gb_window(WIN_X, WIN_Y, win_w, win_h, "VIEWER");
    if (filen == 0)
        gb_text(TX_COL, TX_Y0, "(file is empty or could not be read)");
    else
        render(filen);
    gb_draw_grip(WIN_X, WIN_Y, win_w, win_h);   /* resize grip (#81) */
}

/* on_repaint: redraw the window when the WM restacks us. */
static void v_repaint(void)
{
    gb_curhide();
    v_draw();
    gb_curshow();
}

/* on_frame: close on ESC or a click in the close gadget; other clicks just focus. */
static void on_frame(void)
{
    unsigned char flags = gb_flags();
    if (flags & GB_QUIT) { gb_wm_close(); return; }
    if (!(flags & GB_CLICK)) return;
    if (gb_in_grip(WIN_X, WIN_Y, win_w, win_h, gb_mx(), gb_my())) {  /* resize grip (#81) */
        if (gb_drag_resize(WIN_X, WIN_Y, &win_w, &win_h, MIN_W, MIN_H)) {
            gb_wm_setsize(win_w, win_h);
            gb_restore_parent();
            gb_curhide(); v_draw(); gb_curshow();
        }
        return;
    }
    if (gb_my() >= WIN_Y && gb_my() < WIN_Y + TITLE_H &&
        gb_mx() >= WIN_X && gb_mx() < WIN_X + 5)
        gb_wm_close();                     /* close gadget */
}

static const gb_win_t vwin = { WIN_X, WIN_Y, DEF_W, DEF_H, on_frame, v_repaint, 0, 0 };

void main(void)
{
    gb_wm_add(&vwin);                       /* register FIRST: captures our file arg
                                              (per-window) so the load below is ours */
    filen = gb_fs_load(filebuf, VIEW_MAX);
    gb_curhide();
    v_draw();
    gb_curshow();
}
