/* viewer - GEOBENCH text + .PIC viewer, a KERNEL-MANAGED window (#146).
 *
 * The WM owns the chrome (frame, title, close, drag, resize): the viewer registers
 * a gb_mwin_t and provides only content (on_draw) + the gb_doc menus (File>Load,
 * View>Fullscreen). It reads its live rect with gb_wm_x/y/w/h and asks the WM to
 * repaint with gb_restore_parent. Binary files load fine too - they show as
 * gibberish, so this doubles as a quick "peek" at anything on the disk. */
#include "gb.h"

#define VIEW_MAX  8192    /* in-page buffer = 16 sectors. Pictures use the banked buffer on
                             GBALB/ROM (#164) - so where a spare bank exists this is just the
                             TEXT buffer; it's the picture fallback only with no free bank (bare
                             128K). Trimmed a sector to make room for fullscreen image cycling. */
#define TX_COL    (unsigned char)(win_x + 2)
#define TX_Y0     (unsigned char)(win_y + 12)
#define LINE_H    11
#define MAX_LINES ((win_h - 16) / LINE_H)
#define WRAP      ((win_w - 9) * 2 / 3)
/* line[] holds WRAP chars + a NUL. On the CPC's 80-col screen WRAP <= 47, so 48
   fits; but MSX2 Screen 6 reaches GB_COLS=128, where WRAP reaches (128-9)*2/3 =
   79 - which overran this 48-byte buffer and corrupted memory, hanging the viewer
   the instant it drew text (#287). The viewer's page has no room to grow line[],
   so render() hard-caps the wrap at MAXWRAP-1 instead (MSX text wraps a little
   narrower than the window, but never overflows). */
#define MAXWRAP   48

#define DEF_X     2
#define DEF_Y     14
#define DEF_W     76
#define DEF_H     180
#define MIN_W     30
#define MIN_H     72
#define WM_FS     ((volatile unsigned char *)0x130A)   /* 1 = fullscreen (kernel sets it) */
#define SB_W      3       /* scrollbar width, byte cols (#166) */

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
        if (col == WRAP || col >= MAXWRAP - 1) { line[col] = 0; gb_text(TX_COL, TX_Y0 + row * LINE_H, line); row++; col = 0; }
    }
    if (col > 0 && row < MAX_LINES) { line[col] = 0; gb_text(TX_COL, TX_Y0 + row * LINE_H, line); }
}

static unsigned char pic_wb;
static unsigned int  pic_h;                            /* 16-bit: tall pictures exceed 255 (#166) */
static unsigned int  pic_off;
static unsigned char rmin_w = MIN_W, rmin_h = MIN_H;   /* live resize floor (= picture size) */
static unsigned char banked;                           /* the borrowed bank (0 = in-page), #164 */
static unsigned char scroll_y;                         /* top visible picture row (#166 scroll) */
static unsigned char pic_toobig;                       /* 1 = .PIC too big for the in-page buffer and
                                                          no spare RAM bank -> show a message, not blank */
#define PIC_PAGE_K (*(volatile unsigned char *)0x130B) /* the kernel's single "active pic bank";
                                                          re-select OURS before each blit/close so
                                                          a second Viewer window can't steal it (#164) */
#define PIC_WB_K  (*(volatile unsigned char *)0x130C)  /* kernel-parsed header for the banked .PIC */
#define PIC_H_K   (*(volatile unsigned int  *)0x130D)  /* 16-bit height */
#define PIC_OFF_K (*(volatile unsigned char *)0x130F)

static unsigned char is_pic(void)
{
    return (unsigned char)(filen >= 6 &&
        filebuf[0] == 'G' && filebuf[1] == 'B' && filebuf[2] == 'P' && filebuf[3] == 'C');
}
static unsigned char is_pic_name(const char *n);   /* fwd: defined with the cycling code below */
static unsigned char have_pic(void) { return (unsigned char)(banked || is_pic() || pic_toobig); }

/* the window can't shrink below the picture (the blit has no width clip). */
static void pic_floor(void)
{
    rmin_w = (unsigned char)(pic_wb + 3 + (pic_h > 186 ? SB_W : 0));   /* +scrollbar cols if tall */
    if (rmin_w < MIN_W) rmin_w = MIN_W;
    rmin_h = MIN_H;                                /* tall pics scroll, so allow a small window */
}
static void parse_pic(void)
{
    if ((unsigned char)filebuf[4] == 2) {
        unsigned int w = (unsigned char)filebuf[6] | ((unsigned int)(unsigned char)filebuf[7] << 8);
        pic_wb  = (unsigned char)((w + 3) >> 2);
        pic_h   = (unsigned char)filebuf[8] | ((unsigned int)(unsigned char)filebuf[9] << 8);
        pic_off = 14;
    } else {
        pic_wb  = (unsigned char)filebuf[4];
        pic_h   = (unsigned char)filebuf[5];
        pic_off = 6;
    }
    pic_floor();
}

/* load the opened file: a large .PIC into a borrowed bank (#164, kernels with the pic service),
   else the in-page filebuf (text, or a small .PIC on plain GBIDE). */
static void bank_or_parse(void)
{
    scroll_y = 0;                                  /* a fresh file starts at the top (#166) */
    if (banked) { PIC_PAGE_K = banked; gb_pic_close(); banked = 0; }  /* free OUR old bank only -
                                                      PIC_PAGE may hold another window's (#164) */
    banked = gb_pic_open();                        /* open sets PIC_PAGE to the new bank itself */
    pic_toobig = 0;
    if (banked) {                                  /* in a bank: read the kernel-parsed header */
        pic_wb = PIC_WB_K; pic_h = PIC_H_K; pic_off = PIC_OFF_K;
        pic_floor();
        return;
    }
    filen = gb_fs_load(filebuf, VIEW_MAX);
    if (is_pic()) { parse_pic(); return; }         /* a .PIC small enough to load in-page */
    {
        char nm[11];
        gb_get_name(nm);                           /* this window's launch name (gb_doc_name isn't
                                                      set until gb_doc() runs, after us). The AMSDOS
                                                      reader REFUSES a file bigger than the buffer,
                                                      so a .PIC that loaded nothing + no spare bank
                                                      = too big for this machine (#viewer). */
        if (!filen && is_pic_name(nm)) {
            pic_toobig = 1;
            pic_wb = 26; pic_h = 32; pic_off = 0;  /* a small window just for the message */
            pic_floor();
            return;
        }
    }
    rmin_w = MIN_W; rmin_h = MIN_H;
}

static void size_to_pic(void)   /* size the window to the picture, clamped on screen */
{
    unsigned char x = gb_wm_x(), y = gb_wm_y(), w, h, avail = (unsigned char)(GB_LINES - y);
    unsigned int hh = pic_h + 16;
    h = (hh > avail) ? avail : (unsigned char)hh; if (h < MIN_H) h = MIN_H;   /* 16-bit clamp */
    /* the scrollbar (sb_shown) appears when the content is shorter than the picture; widen for
       it using the SAME test so a clamped window can't push the blit past its right edge. */
    w = (unsigned char)(pic_wb + 3 + (pic_h > (unsigned int)(h - 14) ? SB_W : 0));
    if (w < MIN_W) w = MIN_W;
    if (w > (unsigned char)(GB_COLS - x)) w = (unsigned char)(GB_COLS - x);
    gb_wm_setsize(w, h);
}

/* visible picture rows: the window content height (windowed) or the whole screen. */
static unsigned char vis_rows(void)
{
    return (unsigned char)(*WM_FS ? GB_LINES : win_h - 14);
}

/* sb_shown: 1 when the (left) scrollbar is drawn - windowed + taller than the visible area. */
static unsigned char sb_shown(unsigned char vh) { return (unsigned char)(!*WM_FS && pic_h > vh); }

/* draw_toobig: the .PIC can't fit the in-page buffer and there was no spare RAM bank, so
   show a message instead of a blank window (#viewer). */
static void draw_toobig(void)
{
    gb_text(TX_COL, TX_Y0,                           "Pic too big");
    gb_text(TX_COL, (unsigned char)(TX_Y0 + LINE_H), "Need 256K+");
}

static void draw_pic(void)
{
    unsigned char x, y, vh = vis_rows(), rows, sb = sb_shown(vh);
    unsigned int src, r;
    if (pic_toobig) { draw_toobig(); return; }
    if (*WM_FS) {                                  /* fullscreen: centre (top-align if too tall) */
        x = (unsigned char)(pic_wb < GB_COLS ? (GB_COLS - pic_wb) / 2 : 0);
        y = (unsigned char)(pic_h <= GB_LINES ? (GB_LINES - pic_h) / 2 : 0);
    } else { x = (unsigned char)(win_x + 2 + (sb ? SB_W : 0)); y = TX_Y0; }   /* right of the bar */
    r = pic_h - scroll_y; rows = (r > vh) ? vh : (unsigned char)r;
    src = pic_off + (unsigned int)scroll_y * pic_wb;          /* scrolled window into the bitmap */
    if (banked) { PIC_PAGE_K = banked; gb_pic_blit(x, y, pic_wb, rows, src); }  /* our bank (#164) */
    else if (src + (unsigned int)pic_wb * rows <= filen)
        gb_restorerect(x, y, pic_wb, rows, (unsigned char *)filebuf + src);
    if (sb) {                                      /* vertical scrollbar at the LEFT edge (#166) */
        unsigned char th = (unsigned char)((unsigned int)vh * vh / pic_h); if (th < 4) th = 4;
        unsigned char ty = (unsigned char)(TX_Y0 + (unsigned int)scroll_y * (vh - th) / (pic_h - vh));
        gb_fill((unsigned char)(win_x + 1), TX_Y0, SB_W, vh, 1);          /* white track */
        gb_fill((unsigned char)(win_x + 2), ty, 1, th, 3);               /* red thumb */
    }
}

/* sb_drag: while the fire is held, map the pointer Y onto scroll_y and repaint. */
static void sb_drag(unsigned char vh)
{
    unsigned char th = (unsigned char)((unsigned int)vh * vh / pic_h); if (th < 4) th = 4;
    unsigned char half = (unsigned char)(th / 2), ny;
    unsigned int max = pic_h - vh, my, v;
    while (gb_poll() & GB_FIRE) {
        my = gb_my();
        if (my < (unsigned int)(TX_Y0 + half)) ny = 0;
        else { v = ((my - TX_Y0 - half) * max) / (vh - th); ny = (v > max) ? (unsigned char)max : (unsigned char)v; }
        if (ny != scroll_y) { scroll_y = ny; gb_curhide(); draw_pic(); gb_curshow(); }
    }
}

/* on_draw: the WM already drew the frame/title; paint the content. */
static void v_draw(void)
{
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = gb_wm_w(); win_h = gb_wm_h();
    if (*WM_FS) {                               /* true fullscreen: blue backdrop, centred image,
                                                   no chrome/grip (the WM drops the frame+title) */
        gb_fill(0, 0, GB_COLS, GB_LINES, 0);    /* pen 0 = desktop blue, whole screen */
        if (loaded && have_pic()) draw_pic();
        return;
    }
    if (!loaded)           ;   /* still loading, or empty/unreadable -> blank (render(0) is a no-op) */
    else if (have_pic())   draw_pic();
    else                   render(filen);
    gb_draw_grip(win_x, win_y, win_w, win_h);   /* resize grip (#146) */
}

static void v_fullscreen(unsigned char on);    /* defined below */

/* --- fullscreen image cycling: Space / Right = next, Left = previous (#viewer) -------
   In fullscreen there's no menu bar, so the viewer reads the keys itself. The current
   directory is enumerated for .PIC files; the chosen one is re-pointed via gb_set_name
   (the window's file arg, which gb_pic_open reads) and reloaded by bank_or_parse. */
static void copy11(char *d, const char *s) { unsigned char i; for (i = 0; i < 11; i++) d[i] = s[i]; }
static unsigned char is_pic_name(const char *n) { return (unsigned char)(n[8]=='P' && n[9]=='I' && n[10]=='C'); }
static unsigned char eq11(const char *a, const char *b)
{
    unsigned char i;
    for (i = 0; i < 11; i++) if (a[i] != b[i]) return 0;
    return 1;
}

/* read_lr: matrix state of the Left/Right cursor keys -> lr_bits (bit0 left, bit1 right).
   The firmware keys are disarmed (the joystick floods them), so read them directly with
   KM_TEST_KEY (&BB1E): key 8 = Left, key 1 = Right - same approach as Notepad's caret nav. */
static unsigned char lr_bits;
#ifdef GB_MSX2
/* MSX: read cursor Left/Right from the BIOS NEWKEY matrix (row 8, updated by the
 * interrupt; bit4=Left, bit7=Right, active-low) - no CALSLT needed (#287). */
static void read_lr(void) __naked
{
__asm
    xor  a
    ld   (_lr_bits), a
    ld   a, (0xFBED)       ; NEWKEY row 8
    bit  4, a              ; Left held? (bit clear = pressed)
    jr   nz, 1$
    ld   a, (_lr_bits)
    or   #0x01
    ld   (_lr_bits), a
1$: ld   a, (0xFBED)
    bit  7, a              ; Right held?
    jr   nz, 2$
    ld   a, (_lr_bits)
    or   #0x02
    ld   (_lr_bits), a
2$: ret
__endasm;
}
#else
static void read_lr(void) __naked
{
__asm
    xor  a
    ld   (_lr_bits), a
    ld   a, #8             ; cursor Left = key 8
    call #0xBB1E
    jr   z, 1$
    ld   a, (_lr_bits)
    or   #0x01
    ld   (_lr_bits), a
1$: ld   a, #1             ; cursor Right = key 1
    call #0xBB1E
    jr   z, 2$
    ld   a, (_lr_bits)
    or   #0x02
    ld   (_lr_bits), a
2$: ret
__endasm;
}
#endif

/* cycle to the next (dir>0) / previous (dir<0) .PIC in the current directory, wrapping. */
static void cycle(signed char dir)
{
    char cur[11], first[11], last[11], prevn[11], nextn[11], target[11];
    unsigned char have_first = 0, have_prev = 0, have_next = 0, seen = 0;
    char *p;
    gb_get_name(cur);                          /* this window's current file (11-byte arg) */
    p = gb_dir1();
    while (p) {
        char *e = gb_entname();
        if (is_pic_name(e)) {
            if (!have_first) { copy11(first, e); have_first = 1; }
            copy11(last, e);
            if (seen) { if (!have_next) { copy11(nextn, e); have_next = 1; } }
            else if (eq11(e, cur)) seen = 1;
            else { copy11(prevn, e); have_prev = 1; }
        }
        p = gb_dirn();
    }
    if (!have_first) return;                    /* no pictures in this directory */
    if (dir > 0) copy11(target, have_next ? nextn : first);   /* next, wrap to first */
    else         copy11(target, have_prev ? prevn : last);    /* prev, wrap to last */
    if (eq11(target, cur)) return;              /* only one image -> nothing to do */
    gb_set_name(target);                        /* re-point the window arg gb_pic_open reads */
    bank_or_parse();                            /* reload the picture */
    fmt83(vtitle, target);
    gb_curhide(); v_draw(); gb_curshow();        /* repaint OUR fullscreen content directly (blue
                                                    fill + the new image) - NOT gb_restore_parent,
                                                    which would flash the desktop/windows behind us */
}

/* fullscreen key handler: F exits, Space/Right advance, Left goes back (debounced). */
static unsigned char cyc_cool;
static void fs_nav(void)
{
    unsigned char c = gb_getkey();
    if ((c | 0x20) == 'f') { v_fullscreen(0); gb_restore_parent(); return; }   /* exit fullscreen */
    if (cyc_cool) { cyc_cool--; return; }       /* debounce a recent step */
    if (c == ' ') { cycle(1); cyc_cool = 10; return; }
    read_lr();
    if (lr_bits & 0x02)      { cycle(1);  cyc_cool = 10; }   /* Right -> next */
    else if (lr_bits & 0x01) { cycle(-1); cyc_cool = 10; }   /* Left  -> previous */
}

/* on_frame: size the window to a picture on the first frame (deferred from main so the
   resize runs after the WM services the window), then run pending menus / fullscreen keys. */
static void v_frame(void)
{
    if (!opened) {
        opened = 1;
        if (have_pic()) size_to_pic();
        gb_restore_parent();          /* repaint at the new size */
        return;
    }
    if (*WM_FS) { fs_nav(); return; }           /* fullscreen: cycle images with Space / arrows */
    if (gb_doc_frame()) gb_restore_parent();    /* windowed: a menu ran (or the 'F' shortcut) */
}

static void v_close(void) { if (gb_doc_close()) { if (banked) PIC_PAGE_K = banked; gb_pic_close(); gb_wm_close(); } }
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
    unsigned char w = gb_wm_w(), h = gb_wm_h(), vh;
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = w; win_h = h;   /* draw_pic/TX_Y0 read these */
    vh = vis_rows();
    if (have_pic() && pic_h > vh && gb_mx() >= (unsigned char)(win_x + 1)
        && gb_mx() < (unsigned char)(win_x + 1 + SB_W)
        && gb_my() >= TX_Y0 && gb_my() < (unsigned char)(TX_Y0 + vh)) {
        sb_drag(vh);                               /* drag the LEFT scrollbar (#166) */
        return;
    }
    if (gb_in_grip(win_x, win_y, w, h, gb_mx(), gb_my()))
        if (gb_drag_resize(win_x, win_y, &w, &h, rmin_w, rmin_h)) {
            gb_wm_setsize(w, h);
            gb_restore_parent();
        }
}

/* View > Fullscreen (gb_doc) / the 'F' key: TRUE fullscreen. WM_FS (the shared low-RAM byte)
   tells the desktop to blank its top bar; we cover the WHOLE screen (so v_draw's blue fill
   paints over the WM's chrome) and centre the image. Off restores the exact prior window. */
static void v_fullscreen(unsigned char on)
{
    static unsigned char px, py, pw, ph;
    if (on) {
        px = gb_wm_x(); py = gb_wm_y(); pw = gb_wm_w(); ph = gb_wm_h();
        gb_wm_setpos(0, 0); gb_wm_setsize(GB_COLS, GB_LINES); *WM_FS = 1;
    } else {
        *WM_FS = 0; gb_wm_setpos(px, py); gb_wm_setsize(pw, ph);
    }
    gb_wm_damage(0, 0, GB_COLS, GB_LINES); /* repaint the whole screen ONCE in the frame handler (the
                                      toggle changes the entire screen); v_draw does the paint */
}

/* on_open (File>Load): adopt the name, (re-)load via the bank-or-in-page path, re-arm resize. */
static void v_open(unsigned int len)
{
    (void)len;                        /* bank_or_parse re-loads (gb_doc's filebuf load is for text) */
    fmt83(vtitle, gb_doc_name());
    bank_or_parse();
    opened = 0;                       /* the next frame sizes to the new picture */
}

/* the window's single handler (#148): the kernel calls it for every message. */
static void v_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  v_draw();  break;
        case GB_MSG_CLICK: v_click(); break;
        case GB_MSG_FRAME: v_frame(); break;
        case GB_MSG_CLOSE: v_close(); break;
        case GB_MSG_DRAG:  v_drag();  break;
        case GB_MSG_MENU:
        case GB_MSG_DROP:  v_event(); break;
    }
}

static const gb_mwin_t vmw = {            /* register SMALL (#206): main() then GROWS to the
                                            picture/reading size, so the first paint damages only
                                            that area instead of the near-fullscreen DEF rect. */
    DEF_X, DEF_Y, MIN_W, MIN_H, MIN_W, MIN_H, v_proc, vtitle
};
/* read-only doc: File offers only Load; View offers Fullscreen (exts NULL = show all). */
static const gb_doc_t vdoc = {
    filebuf, VIEW_MAX, 0, v_open, 0, 0, 0, 0, 0, 0, 0, 0, v_fullscreen, 0, 0
};

void main(void)
{
    gb_wm_managed(&vmw);             /* register + focus FIRST, but it does NOT draw yet (#146):
                                        now gb_fs_load/gb_doc target THIS window's launch file,
                                        and nothing is on screen while we do the slow load. The
                                        window is registered SMALL (MIN_W x MIN_H, #206) so the
                                        size below only ever GROWS it - a shrink from a big
                                        default would damage (and progressively repaint) almost
                                        the whole screen, the "weird redraw" on open. */
    bank_or_parse();                 /* load the launch file: banked .PIC (#164) or in-page */
    loaded = 1;
    if (have_pic()) {                /* size to the picture before the first paint (grows) */
        size_to_pic();
        opened = 1;                  /* already sized; v_frame's deferred resize is for File>Load */
    }
    else gb_wm_setsize(DEF_W, DEF_H);   /* #206: text/binary - grow to a readable window */
    gb_doc(&vdoc);                   /* menus + adopt the name for the title */
    fmt83(vtitle, gb_doc_name());
    gb_restore_parent();             /* FIRST paint: content, fitted - the window appears ready */
}
