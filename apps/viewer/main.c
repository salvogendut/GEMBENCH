/* viewer - GEOBENCH text + .PIC viewer, a KERNEL-MANAGED window (#146).
 *
 * The WM owns the chrome (frame, title, close, drag, resize): the viewer registers
 * a gb_mwin_t and provides only content (on_draw) + the gb_doc menus (File>Load,
 * View>Fullscreen). It reads its live rect with gb_wm_x/y/w/h and asks the WM to
 * repaint with gb_restore_parent. Binary files load fine too - they show as
 * gibberish, so this doubles as a quick "peek" at anything on the disk. */
#include "gb.h"

#define VIEW_MAX  10240   /* file buffer + load cap = 20 sectors, holds a full 200x200 .PIC. */
#define TX_COL    (unsigned char)(win_x + 2)
#define TX_Y0     (unsigned char)(win_y + 12)
#define LINE_H    11
#define MAX_LINES ((win_h - 16) / LINE_H)
#define WRAP      ((win_w - 9) * 2 / 3)
#define MAXWRAP   48

#define DEF_X     2
#define DEF_Y     14
#define DEF_W     76
#define DEF_H     180
#define MIN_W     30
#define MIN_H     72

static char filebuf[VIEW_MAX];
static char line[MAXWRAP];
static unsigned int filen;
static unsigned char win_x, win_y, win_w, win_h;   /* refreshed from the WM each draw */
static char vtitle[14];                            /* "NAME.EXT" - the WM draws it */
static unsigned char opened;                       /* 0 -> the next frame sizes to a picture */
static unsigned char loaded;                       /* 0 until the file is read (blank, no msg) */

/* fmt83: 11-byte 8.3 name -> "NAME.EXT". */
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

static void render(unsigned int n)
{
    unsigned int i = 0;
    unsigned char row = 0, col = 0, c;
    while (i < n && row < MAX_LINES) {
        c = filebuf[i++];
        if (c == '\r') continue;
        if (c == '\n') { line[col] = 0; gb_text(TX_COL, TX_Y0 + row * LINE_H, line); row++; col = 0; continue; }
        if (c < 32) continue;
        line[col++] = c;
        if (col == WRAP) { line[col] = 0; gb_text(TX_COL, TX_Y0 + row * LINE_H, line); row++; col = 0; }
    }
    if (col > 0 && row < MAX_LINES) { line[col] = 0; gb_text(TX_COL, TX_Y0 + row * LINE_H, line); }
}

static unsigned char pic_wb, pic_h;
static unsigned int  pic_off;

static unsigned char is_pic(void)
{
    return (unsigned char)(filen >= 6 &&
        filebuf[0] == 'G' && filebuf[1] == 'B' && filebuf[2] == 'P' && filebuf[3] == 'C');
}
static void parse_pic(void)
{
    if ((unsigned char)filebuf[4] == 2) {
        unsigned int w = (unsigned char)filebuf[6] | ((unsigned int)(unsigned char)filebuf[7] << 8);
        pic_wb  = (unsigned char)((w + 3) >> 2);
        pic_h   = (unsigned char)filebuf[8];
        pic_off = 14;
    } else {
        pic_wb  = (unsigned char)filebuf[4];
        pic_h   = (unsigned char)filebuf[5];
        pic_off = 6;
    }
}
static void draw_pic(void)
{
    unsigned char h = pic_h, maxh = (unsigned char)(win_h - 14);   /* window content height */
    if (h > maxh) h = maxh;                                        /* don't spill past the frame */
    if (pic_off + (unsigned int)pic_wb * h > filen) return;
    gb_restorerect((unsigned char)(win_x + 2), TX_Y0, pic_wb, h, (unsigned char *)filebuf + pic_off);
}

/* on_draw: the WM already drew the frame/title; paint the content. */
static void v_draw(void)
{
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = gb_wm_w(); win_h = gb_wm_h();
    if (!loaded)           ;   /* still loading -> blank window, not the empty-file message */
    else if (filen == 0)   gb_text(TX_COL, TX_Y0, "(file is empty or could not be read)");
    else if (is_pic())     draw_pic();
    else                   render(filen);
    gb_draw_grip(win_x, win_y, win_w, win_h);   /* resize grip (#146) */
}

/* on_frame: size the window to a picture on the first frame (deferred from main so the
   resize runs after the WM services the window), then run pending menus. */
static void v_frame(void)
{
    if (!opened) {
        opened = 1;
        if (is_pic()) {
            unsigned char x = gb_wm_x(), y = gb_wm_y(), w, h;
            w = (unsigned char)(pic_wb + 3);
            if (w < MIN_W) w = MIN_W;
            if (w > (unsigned char)(80 - x)) w = (unsigned char)(80 - x);
            h = (unsigned char)(pic_h + 16);
            if (h < MIN_H) h = MIN_H;
            if (h > (unsigned char)(200 - y)) h = (unsigned char)(200 - y);
            gb_wm_setsize(w, h);
        }
        gb_restore_parent();          /* repaint at the new size */
        return;
    }
    if (gb_doc_frame()) gb_restore_parent();   /* a menu ran -> repaint */
}

static void v_close(void) { if (gb_doc_close()) gb_wm_close(); }
static void v_event(void) { gb_doc_event(); }

/* on_drag: a title-bar press - move the window (#146 slice 2). */
static void v_drag(void)
{
    unsigned char x = gb_wm_x(), y = gb_wm_y();
    if (gb_drag_window(&x, &y, gb_wm_w(), gb_wm_h())) {
        gb_wm_setpos(x, y);
        gb_restore_parent();
    }
}

/* on_click: a content-area press - only the resize grip matters to the viewer. */
static void v_click(void)
{
    unsigned char x = gb_wm_x(), y = gb_wm_y(), w = gb_wm_w(), h = gb_wm_h();
    if (gb_in_grip(x, y, w, h, gb_mx(), gb_my()))
        if (gb_drag_resize(x, y, &w, &h, MIN_W, MIN_H)) {
            gb_wm_setsize(w, h);
            gb_restore_parent();
        }
}

/* View > Fullscreen (gb_doc): the WM owns the geometry, so just setpos/setsize. */
static void v_fullscreen(unsigned char on)
{
    static unsigned char px, py, pw, ph;
    if (on) { px = gb_wm_x(); py = gb_wm_y(); pw = gb_wm_w(); ph = gb_wm_h();
              gb_wm_setpos(0, 8); gb_wm_setsize(80, 192); }
    else    { gb_wm_setpos(px, py); gb_wm_setsize(pw, ph); }
    gb_restore_parent();
}

/* on_open (File>Load): adopt the name, parse a picture, re-arm the resize. */
static void v_open(unsigned int len)
{
    filen = len;
    fmt83(vtitle, gb_doc_name());
    if (is_pic()) parse_pic();
    opened = 0;                       /* the next frame sizes to the new picture */
}

static const gb_mwin_t vmw = {
    DEF_X, DEF_Y, DEF_W, DEF_H, MIN_W, MIN_H,
    v_draw, v_click, v_frame, v_close, v_event, vtitle, v_drag
};
/* read-only doc: File offers only Load; View offers Fullscreen (exts NULL = show all). */
static const gb_doc_t vdoc = {
    filebuf, VIEW_MAX, 0, v_open, 0, 0, 0, 0, 0, 0, 0, 0, v_fullscreen, 0, 0
};

void main(void)
{
    char nm[11];
    gb_get_name(nm);                 /* the file we were launched with (kernel launch arg) */
    gb_set_name(nm);                 /* target it for the load - NOT the stale boot name */
    filen = gb_fs_load(filebuf, VIEW_MAX);   /* load BEFORE the window is drawn, so its first
                                                paint already has the picture (no empty flash) */
    loaded = 1;
    fmt83(vtitle, nm);               /* title ready for the initial paint too */
    if (is_pic()) parse_pic();
    gb_wm_managed(&vmw);             /* register + initial paint: the content is ready */
    if (is_pic()) {                  /* size to the picture now, before the WM loop's repaint */
        unsigned char x = gb_wm_x(), y = gb_wm_y(), w, h;
        w = (unsigned char)(pic_wb + 3);
        if (w < MIN_W) w = MIN_W;
        if (w > (unsigned char)(80 - x)) w = (unsigned char)(80 - x);
        h = (unsigned char)(pic_h + 16);
        if (h < MIN_H) h = MIN_H;
        if (h > (unsigned char)(200 - y)) h = (unsigned char)(200 - y);
        gb_wm_setsize(w, h);
        opened = 1;                  /* already sized; v_frame's deferred resize is for File>Load */
    }
    gb_doc(&vdoc);                   /* menus on the focused window */
    gb_restore_parent();             /* one repaint at the fitted size */
}
