/*
 * XAOS.APP - GEOBENCH's first "fun" app (#116): a fixed-point Mandelbrot generator,
 * inspired by XaoS (https://github.com/xaos-project/XaoS) but trimmed to what a
 * 4 MHz Z80 in Mode 1 (4 colours) can do. NOT real-time zoom (XaoS's incremental
 * approximation is out of reach here) - a render-then-explore fractal viewer.
 *
 * A window shows the current fractal; on-screen [+]/[-] buttons zoom in/out, a
 * click on the canvas recentres there, and a top-bar File > Save writes the picture
 * as a .PIC (the versioned format the Viewer displays). Uses the fractal.png icon.
 *
 * Maths is Q4.12 signed fixed point (16-bit: 4 integer bits incl. sign, 12
 * fractional). The hot op - a signed (a*b)>>12 - is a hand-written Z80 routine
 * (fixmul); the per-pixel escape loop is C around it. The canvas is a Mode-1 bitmap
 * blitted with gb_restorerect; each row shows as it finishes. The canvas lives
 * inside a .PIC buffer (header + bitmap) so Save is a single gb_fs_save.
 */
#include "gb.h"

#define DEF_X     6
#define DEF_Y     14
#define TITLE_H   14

#define CANVAS_WB 20                    /* 80 px / 4 */
#define CANVAS_W  (CANVAS_WB * 4)       /* 80 px */
#define CANVAS_H  56
#define WIN_W     (CANVAS_WB + 2)
#define WIN_H     (TITLE_H + CANVAS_H + 14)        /* title + canvas + control strip */

#define MAXITER   20

static unsigned char win_x = DEF_X, win_y = DEF_Y;
#define CVX    (unsigned char)(win_x + 1)            /* canvas left, byte column */
#define CVY    (unsigned char)(win_y + TITLE_H + 1)  /* canvas top, screen row   */
#define CTRL_Y (unsigned char)(CVY + CANVAS_H + 2)   /* control strip (the +/- buttons) */

/* .PIC v2 header (14 bytes) then the canvas, in one buffer so Save is one fs call.
   See apps/paint/main.c for the layout. */
#define PIC_HDR 14
#define PIC_LEN (PIC_HDR + CANVAS_WB * CANVAS_H)
static unsigned char picbuf[PIC_LEN];
#define canvas (picbuf + PIC_HDR)
static const unsigned char pic_inks[4] = { 1, 26, 0, 6 };   /* GEOBENCH palette inks */

/* view: centre (cx0,cy0) and per-pixel step, all Q4.12. Home = the whole set. */
#define HOME_CX   (-2048)               /* -0.5 */
#define HOME_CY   0
#define HOME_STEP 160                   /* ~0.039/px -> ~3.1 wide, square pixels */
static int cx0 = HOME_CX, cy0 = HOME_CY, step = HOME_STEP;

/* File menu state + the saved file name (shown in the title once saved). */
#define FILE_COL 10
#define FILE_END 16
static unsigned char want_menu;
static char name83[11];
static char fbase[14];
static char wtitle[18];
static char namebuf[16];
static const unsigned char top_menu[] = { 1, FILE_COL, 'F','i','l','e',0,0,0,0 };

/* ---- Q4.12 signed multiply: fr = (fa * fb) >> 12 (hand-written, the hot op) ---- */
static int fa, fb, fr;
static void fixmul(void) __naked
{
__asm
        ld   hl,(_fa)
        ld   de,(_fb)
        ld   a,h
        xor  d
        push af                  ; result sign in bit 7
        bit  7,h                 ; |fa| -> HL
        jr   z,1$
        ld   a,h
        cpl
        ld   h,a
        ld   a,l
        cpl
        ld   l,a
        inc  hl
1$:     bit  7,d                 ; |fb| -> DE
        jr   z,2$
        ld   a,d
        cpl
        ld   d,a
        ld   a,e
        cpl
        ld   e,a
        inc  de
2$:     ld   b,h                 ; BC = multiplicand |fa|, DE = multiplier |fb|
        ld   c,l
        ld   hl,#0
        ld   a,#16
3$:     add  hl,hl               ; DE:HL <<= 1, add BC on multiplier carry-out
        rl   e
        rl   d
        jr   nc,4$
        add  hl,bc
        jr   nc,4$
        inc  de
4$:     dec  a
        jr   nz,3$               ; DE:HL = |fa| * |fb|
        ld   a,#4                 ; >>12 = shift DE:HL left 4, keep the high word DE
5$:     add  hl,hl
        rl   e
        rl   d
        dec  a
        jr   nz,5$
        ex   de,hl               ; HL = |result|
        pop  af
        bit  7,a                 ; apply the sign
        jr   z,6$
        ld   a,h
        cpl
        ld   h,a
        ld   a,l
        cpl
        ld   l,a
        inc  hl
6$:     ld   (_fr),hl
        ret
__endasm;
}
static int FMUL(int a, int b) { fa = a; fb = b; fixmul(); return fr; }

/* mand: escape iterations for c = (cx,cy) in Q4.12 (the Mandelbrot inner loop). */
static unsigned char mand(int cx, int cy)
{
    int zx = 0, zy = 0, zx2, zy2;
    unsigned char i;
    for (i = 0; i < MAXITER; i++) {
        zx2 = FMUL(zx, zx);
        zy2 = FMUL(zy, zy);
        if ((unsigned int)(zx2 + zy2) >= 0x4000u) break;   /* |z|^2 >= 4 -> escaped */
        zy = 2 * FMUL(zx, zy) + cy;
        zx = zx2 - zy2 + cx;
    }
    return i;
}

/* iteration count -> a Mode-1 pen (0 blue, 1 white, 2 black, 3 red) */
static unsigned char pen_of(unsigned char it)
{
    if (it >= MAXITER) return 2;        /* inside the set: black */
    if (it < 5)  return 0;              /* far outside: blue   */
    if (it < 11) return 3;              /* mid:         red    */
    return 1;                           /* near the edge: white */
}

/* ---- Mode-1 pixel packing (pixel i: bit0 @ 7-i, bit1 @ 3-i) ------------------ */
static unsigned char set_pixel(unsigned char b, unsigned char i, unsigned char p)
{
    b &= (unsigned char)~((1 << (7 - i)) | (1 << (3 - i)));
    if (p & 1) b |= (unsigned char)(1 << (7 - i));
    if (p & 2) b |= (unsigned char)(1 << (3 - i));
    return b;
}

static void blit_row(unsigned char row)
{
    gb_curhide();
    gb_restorerect(CVX, (unsigned char)(CVY + row), CANVAS_WB, 1,
                   canvas + (unsigned int)row * CANVAS_WB);
    gb_curshow();
}
static void blit_canvas(void)
{
    gb_curhide();
    gb_restorerect(CVX, CVY, CANVAS_WB, CANVAS_H, canvas);
    gb_curshow();
}

/* render the whole canvas a row at a time (so you watch it paint). Any key aborts. */
static void render(void)
{
    unsigned char px, py, b;
    int cx, cy;
    for (py = 0; py < CANVAS_H; py++) {
        cy = cy0 + (int)((int)py - CANVAS_H / 2) * step;
        for (b = 0; b < CANVAS_WB; b++) canvas[(unsigned int)py * CANVAS_WB + b] = 0;
        for (px = 0; px < CANVAS_W; px++) {
            unsigned int off = (unsigned int)py * CANVAS_WB + (px >> 2);
            cx = cx0 + (int)((int)px - CANVAS_W / 2) * step;
            canvas[off] = set_pixel(canvas[off], (unsigned char)(px & 3), pen_of(mand(cx, cy)));
        }
        blit_row(py);
        if (gb_getkey()) return;        /* any key aborts the render */
    }
}

/* ---- window chrome ---------------------------------------------------------- */
static const char *win_title(void)
{
    /* single-index copy: the two-index `wtitle[j++] = fbase[i++]` form is
       miscompiled by SDCC under --fomit-frame-pointer (copied only 1 char, #142). */
    unsigned char j = 0;
    char c;
    if (!fbase[0]) return "XAOS";
    while ((c = fbase[j]) != 0) { wtitle[j] = c; j++; }
    wtitle[j] = 0;
    return wtitle;
}

static void btn(unsigned char bx, const char *label)
{
    gb_fill(bx, CTRL_Y, 4, 9, 1);
    gb_frame(bx, CTRL_Y, 4, 9, 2);
    gb_textbw((unsigned char)(bx + 1), (unsigned char)(CTRL_Y + 1), label);
}
static void draw_buttons(void)
{
    gb_curhide();
    btn((unsigned char)(win_x + 1), "+");
    btn((unsigned char)(win_x + 6), "-");
    gb_curshow();
}
static void draw_all(void)
{
    gb_curhide();
    gb_window(win_x, win_y, WIN_W, WIN_H, win_title());
    gb_curshow();
    blit_canvas();
    draw_buttons();
}
static void on_repaint(void) { draw_all(); }

/* recentre the view on canvas pixel (px,py) and rescale step by num/den, re-render. */
static void rezoom(unsigned char px, unsigned char py, unsigned char num, unsigned char den)
{
    cx0 += (int)((int)px - CANVAS_W / 2) * step;
    cy0 += (int)((int)py - CANVAS_H / 2) * step;
    step = (int)((long)step * num / den);
    if (step < 1) step = 1;
    render();
}

/* ---- File > Save (.PIC) ----------------------------------------------------- */
static void fmt83(char *dst, const char *n11)
{
    unsigned char i, j = 0;
    for (i = 0; i < 8 && n11[i] != ' '; i++) dst[j++] = n11[i];
    if (n11[8] != ' ') { dst[j++] = '.'; for (i = 8; i < 11 && n11[i] != ' '; i++) dst[j++] = n11[i]; }
    dst[j] = 0;
}
static void to_83(const char *s)
{
    unsigned char i = 0, j;
    for (j = 0; j < 11; j++) name83[j] = ' ';
    while (s[i] && s[i] != '.' && i < 8) { name83[i] = s[i]; i++; }
    while (s[i] && s[i] != '.') i++;
    if (s[i] == '.') { i++; for (j = 0; j < 3 && s[i]; j++, i++) name83[8 + j] = s[i]; }
}
static void ensure_pic_ext(void)
{
    unsigned char i = 0, has = 0;
    while (namebuf[i]) { if (namebuf[i] == '.') has = 1; i++; }
    if (!has && i && i <= 8) { namebuf[i++] = '.'; namebuf[i++] = 'P'; namebuf[i++] = 'I'; namebuf[i++] = 'C'; namebuf[i] = 0; }
}
static void write_pic(void)            /* v2 header + the canvas -> the open file */
{
    picbuf[0] = 'G'; picbuf[1] = 'B'; picbuf[2] = 'P'; picbuf[3] = 'C';
    picbuf[4] = 2; picbuf[5] = 1;                          /* version 2, mode 1 */
    picbuf[6] = CANVAS_W; picbuf[7] = 0;                   /* width  px */
    picbuf[8] = CANVAS_H; picbuf[9] = 0;                   /* height px */
    picbuf[10] = pic_inks[0]; picbuf[11] = pic_inks[1];
    picbuf[12] = pic_inks[2]; picbuf[13] = pic_inks[3];
    gb_fs_save((char *)picbuf, PIC_LEN);
}
static void do_save(void)
{
    if (!gb_prompt("Save as:", namebuf, 12)) return;
    ensure_pic_ext();
    to_83(namebuf);
    gb_set_name(name83);
    fmt83(fbase, name83);              /* title -> the saved name */
    write_pic();
}
static const char *const file_items[] = { "Save" };
static void run_menu(void)
{
    if (gb_popup(FILE_COL, 8, file_items, 1) == 0) do_save();
}
static void on_menu(void)
{
    if (gb_msg.type != GB_MSG_MENU || gb_modal()) return;
    if (gb_msg.p0 >= FILE_COL && gb_msg.p0 < FILE_END) want_menu = 1;
}

static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my, c, cy;
    unsigned int px;

    if (flags & GB_QUIT) { gb_wm_close(); return; }

    if (want_menu) { want_menu = 0; run_menu(); draw_all(); return; }

    while ((c = gb_getkey()) != 0)                     /* 'r' resets the home view */
        if (c == 'r' || c == 'R') { cx0 = HOME_CX; cy0 = HOME_CY; step = HOME_STEP; render(); return; }

    if (!(flags & GB_CLICK)) return;
    mx = gb_mx(); my = gb_my();

    if (my >= win_y && my < (unsigned char)(win_y + TITLE_H)) {         /* title bar */
        if (mx >= win_x && mx < (unsigned char)(win_x + 5)) { gb_wm_close(); return; }
        if (mx >= (unsigned char)(win_x + 5) && mx < (unsigned char)(win_x + WIN_W)) {
            if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
                gb_wm_setpos(win_x, win_y);
                gb_restore_parent();
                draw_all();
            }
        }
        return;
    }
    if (my >= CTRL_Y && my < (unsigned char)(CTRL_Y + 9)) {             /* +/- buttons */
        if (mx >= (unsigned char)(win_x + 1) && mx < (unsigned char)(win_x + 5))
            rezoom(CANVAS_W / 2, CANVAS_H / 2, 1, 2);                   /* zoom in  */
        else if (mx >= (unsigned char)(win_x + 6) && mx < (unsigned char)(win_x + 10))
            rezoom(CANVAS_W / 2, CANVAS_H / 2, 2, 1);                   /* zoom out */
        return;
    }
    if (my >= CVY && (unsigned char)(my - CVY) < CANVAS_H) {            /* canvas: recentre */
        cy = (unsigned char)(my - CVY);
        px = gb_mxp();
        if (px >= (unsigned int)CVX * 4) {
            px -= (unsigned int)CVX * 4;
            if (px < CANVAS_W) rezoom((unsigned char)px, cy, 1, 1);     /* pan, no zoom */
        }
    }
}

static gb_win_t xwin = { DEF_X, DEF_Y, WIN_W, WIN_H, on_frame, on_repaint, on_menu, top_menu };

void main(void)
{
    unsigned char n;
    win_x = DEF_X; win_y = DEF_Y;
    cx0 = HOME_CX; cy0 = HOME_CY; step = HOME_STEP;
    want_menu = 0; fbase[0] = 0;
    gb_wm_add(&xwin);
    draw_all();
    for (n = 64; n; n--) if (!gb_getkey()) break;       /* drop buffered keys */
    render();
}
