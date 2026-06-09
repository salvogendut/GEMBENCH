/* viewer - GEOBENCH text-file viewer, the first C app that does real work.
 *
 * Launched by the file manager for any non-.TXT file (the type->app default).
 * Issue #45: a co-resident window - main() loads the file, renders it, registers
 * with gb_wm_add and returns; the kernel WM loop drives on_frame / on_repaint.
 * The close gadget (title-bar left) or ESC closes it; the title bar drags it, the
 * corner grip resizes it; other clicks just focus it.
 *
 * Binary files load fine too; they just show as gibberish (control bytes are
 * skipped), so this doubles as a quick "peek" at anything on the disk. */
#include "gb.h"

#define VIEW_MAX  12288  /* file buffer + load cap. Big enough for a ~200x200 .PIC
                            (a full-screen 320x200 is 16K - won't fit the 16K bank). */
#define TX_COL    (unsigned char)(win_x + 2)     /* text/image start: byte col in window */
#define TX_Y0     (unsigned char)(win_y + 12)    /* first text line / image top (rows)  */
#define LINE_H    11     /* line pitch (pixels)                               */
#define MAX_LINES ((win_h - 16) / LINE_H)       /* visible text rows (runtime) */
#define WRAP      ((win_w - 9) * 2 / 3)          /* chars per line (runtime)    */
#define MAXWRAP   48     /* line[] cap = max WRAP at 80-col                    */

#define DEF_X     2      /* initial position; the window is draggable now      */
#define DEF_Y     14
#define DEF_W     76     /* default size; the window is resizeable (#81)      */
#define DEF_H     180
#define MIN_W     30
#define MIN_H     72
#define TITLE_H   14

static char filebuf[VIEW_MAX];
static char line[MAXWRAP];
static unsigned int filen;       /* bytes loaded (for repaint) */
static unsigned char win_x = DEF_X, win_y = DEF_Y;   /* live position (draggable)   */
static unsigned char win_w = DEF_W, win_h = DEF_H;   /* live size (resizeable) */
static char fbase[14];           /* "NAME.EXT" of the open file (window title) */

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

/* A .PIC, once parsed: row stride in bytes, height in rows, and the bitmap offset
   into filebuf. Set by parse_pic for either header version. */
static unsigned char pic_wb, pic_h;
static unsigned int  pic_off;

/* is_pic: does the loaded file start with PAINT's .PIC header "GBPC"? (#114) */
static unsigned char is_pic(void)
{
    return (unsigned char)(filen >= 6 &&
        filebuf[0] == 'G' && filebuf[1] == 'B' && filebuf[2] == 'P' && filebuf[3] == 'C');
}

/* parse_pic: read the dimensions + bitmap offset for v1 or v2 (#114).
     v2: GBPC | ver=2 | mode | width_px(2) | height_px(2) | inks[4] | bitmap@14
     v1: GBPC | wb     | h    | bitmap@6
   (the palette is recorded but not applied - Mode-1's palette is global, shared with
   the desktop, so a windowed view stays in the standard inks.) */
static void parse_pic(void)
{
    if ((unsigned char)filebuf[4] == 2) {            /* v2 */
        unsigned int w = (unsigned char)filebuf[6] | ((unsigned int)(unsigned char)filebuf[7] << 8);
        pic_wb  = (unsigned char)((w + 3) >> 2);     /* Mode-1: 4 px per byte */
        pic_h   = (unsigned char)filebuf[8];         /* height low byte (>255 needs scroll) */
        pic_off = 14;
    } else {                                         /* v1 */
        pic_wb  = (unsigned char)filebuf[4];
        pic_h   = (unsigned char)filebuf[5];
        pic_off = 6;
    }
}

/* draw_pic: blit the .PIC bitmap 1:1 (same call PAINT uses), height clamped to the
   screen; oversized widths / heights await a scrolling view. */
static void draw_pic(void)
{
    unsigned char h = pic_h, maxh = (unsigned char)(199 - TX_Y0);
    if (h > maxh) h = maxh;
    if (pic_off + (unsigned int)pic_wb * h > filen) return;   /* truncated/bad */
    gb_restorerect((unsigned char)(win_x + 2), TX_Y0, pic_wb, h,
                   (unsigned char *)filebuf + pic_off);
}

/* paint the whole window (title + text, or a .PIC image). */
static void v_draw(void)
{
    gb_window(win_x, win_y, win_w, win_h, fbase[0] ? fbase : "VIEWER");
    if (filen == 0)
        gb_text(TX_COL, TX_Y0, "(file is empty or could not be read)");
    else if (is_pic())
        draw_pic();
    else
        render(filen);
    gb_draw_grip(win_x, win_y, win_w, win_h);   /* resize grip (#81) */
}

/* on_repaint: redraw the window when the WM restacks us. */
static void v_repaint(void)
{
    gb_curhide();
    v_draw();
    gb_curshow();
}

/* on_frame: ESC / close gadget closes; the title bar drags the window; the grip
   resizes; other clicks just focus. */
static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my;
    if (flags & GB_QUIT) { gb_wm_close(); return; }
    if (!(flags & GB_CLICK)) return;
    mx = gb_mx(); my = gb_my();
    if (gb_in_grip(win_x, win_y, win_w, win_h, mx, my)) {       /* resize grip (#81) */
        if (gb_drag_resize(win_x, win_y, &win_w, &win_h, MIN_W, MIN_H)) {
            gb_wm_setsize(win_w, win_h);
            gb_restore_parent();
            gb_curhide(); v_draw(); gb_curshow();
        }
        return;
    }
    if (my >= win_y && my < (unsigned char)(win_y + TITLE_H)) { /* title bar */
        if (mx >= win_x && mx < (unsigned char)(win_x + 5)) { gb_wm_close(); return; }  /* close */
        if (mx >= (unsigned char)(win_x + 5) && mx < (unsigned char)(win_x + win_w)) {  /* drag */
            if (gb_drag_window(&win_x, &win_y, win_w, win_h)) {
                gb_wm_setpos(win_x, win_y);
                gb_restore_parent();
                gb_curhide(); v_draw(); gb_curshow();
            }
        }
    }
}

static const gb_win_t vwin = { DEF_X, DEF_Y, DEF_W, DEF_H, on_frame, v_repaint, 0, 0 };

void main(void)
{
    char raw[11];
    gb_wm_add(&vwin);                       /* register FIRST: captures our file arg
                                              (per-window) so the load below is ours */
    gb_get_name(raw);                       /* the file we were launched with -> title */
    fmt83(fbase, raw);
    filen = gb_fs_load(filebuf, VIEW_MAX);
    if (is_pic()) {                         /* a picture -> size the window to it (#114) */
        parse_pic();
        win_w = (unsigned char)(pic_wb + 3);
        if (win_w < MIN_W) win_w = MIN_W;
        if (win_w > (unsigned char)(80 - win_x)) win_w = (unsigned char)(80 - win_x);
        win_h = (unsigned char)((TX_Y0 - win_y) + pic_h + 4);
        if (win_h < MIN_H) win_h = MIN_H;
        if (win_h > (unsigned char)(200 - win_y)) win_h = (unsigned char)(200 - win_y);
        gb_wm_setsize(win_w, win_h);
    }
    gb_curhide();
    v_draw();
    gb_curshow();
}
