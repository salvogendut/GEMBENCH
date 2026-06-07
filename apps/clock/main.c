/* clock - the GEOBENCH analog clock (C), a co-resident window (#72).
 *
 * An xclock-style analog face: a round rim, 12 hour ticks, and hour/minute/second
 * hands placed from a fixed-point sin/cos table, with a digital HH:MM:SS readout
 * below. The kernel exposes the time (gb_time -> gb_hour/min/sec) and a pixel-coord
 * line primitive (gb_line); the hands are drawn with those.
 *
 * It updates once a second while focused (the cooperative WM only calls the focused
 * window's on_frame). To avoid flicker the face is not cleared each tick: the old
 * hands are erased (redrawn in the background pen), the rim/ticks repaired, and the
 * new hands drawn. Drag the title bar to move it; the close gadget / ESC closes it.
 */
#include "gb.h"

#define DEF_X    24           /* initial window position (draggable) */
#define DEF_Y    20
#define WIN_W    28           /* bytes (112 px) */
#define WIN_H    128          /* px */
#define TITLE_H  14

#define R        44           /* face radius (px) */
#define TICK_IN  37           /* hour-tick inner radius */
#define L_HOUR   24           /* hand lengths */
#define L_MIN    36
#define L_SEC    42

/* live (draggable) clock centre, in screen pixels */
#define CX       (win_x * 4 + WIN_W * 2)
#define CY       (win_y + 60)

static unsigned char win_x = DEF_X, win_y = DEF_Y;
static unsigned char ph, pm, ps, have_prev;   /* previous h/m/s, for erasing hands */

/* sin/cos * 64 for the 60 clock positions (0 = 12 o'clock, clockwise, 6 deg each) */
static const signed char SIN64[60] = {
      0,  7, 13, 20, 26, 32, 38, 43, 48, 52, 55, 58,
     61, 63, 64, 64, 64, 63, 61, 58, 55, 52, 48, 43,
     38, 32, 26, 20, 13,  7,  0, -7,-13,-20,-26,-32,
    -38,-43,-48,-52,-55,-58,-61,-63,-64,-64,-64,-63,
    -61,-58,-55,-52,-48,-43,-38,-32,-26,-20,-13, -7
};
static const signed char COS64[60] = {
     64, 64, 63, 61, 58, 55, 52, 48, 43, 38, 32, 26,
     20, 13,  7,  0, -7,-13,-20,-26,-32,-38,-43,-48,
    -52,-55,-58,-61,-63,-64,-64,-64,-63,-61,-58,-55,
    -52,-48,-43,-38,-32,-26,-20,-13, -7,  0,  7, 13,
     20, 26, 32, 38, 43, 48, 52, 55, 58, 61, 63, 64
};

/* The kernel exposes no line primitive (to stay lean), so the clock draws its hands
   by calling the CPC firmware graphics VDU directly: GRA_SET_PEN (&BBDE), GRA_MOVE_
   ABS (&BBC0), GRA_LINE_ABS (&BBF6). Coords are firmware graphics units (0-639 x
   0-399 from the bottom-left). The jumpblock is always mapped, so an app can call it;
   the screen (&C000+) is untouched by our #4000 bank. */
static volatile unsigned int fx0, fy0, fx1, fy1;
static volatile unsigned char fpen;
static void fw_line(void) __naked
{
__asm
    ld   a, (_fpen)
    call 0xBBDE          ; GRA_SET_PEN  (A = pen)
    ld   de, (_fx0)
    ld   hl, (_fy0)
    call 0xBBC0          ; GRA_MOVE_ABS (DE = x, HL = y)
    ld   de, (_fx1)
    ld   hl, (_fy1)
    call 0xBBF6          ; GRA_LINE_ABS (DE = x, HL = y)
    ret
__endasm;
}

/* line: pixel coords (x 0-319, y 0-199 from top-left) -> firmware coords, then draw. */
static void line(int x0, int y0, int x1, int y1, unsigned char pen)
{
    fx0 = (unsigned int)(x0 * 2); fy0 = (unsigned int)((199 - y0) * 2);
    fx1 = (unsigned int)(x1 * 2); fy1 = (unsigned int)((199 - y1) * 2);
    fpen = pen;
    fw_line();
}

/* the kernel hands us raw RTC registers; convert BCD -> binary unless it's already
   binary (software clock, or an RTC running in binary mode). */
static unsigned char bin(unsigned char v)
{
    return gb_binmode ? v : (unsigned char)((v >> 4) * 10 + (v & 15));
}

/* px/py of position `pos` (0..59) at radius `rad` from the clock centre */
static int px_at(unsigned char pos, unsigned char rad) { return CX + (int)SIN64[pos] * rad / 64; }
static int py_at(unsigned char pos, unsigned char rad) { return CY - (int)COS64[pos] * rad / 64; }

static void hand(unsigned char pos, unsigned char len, unsigned char pen)
{
    line(CX, CY, px_at(pos, len), py_at(pos, len), pen);
}

static unsigned char hourpos(unsigned char h, unsigned char m)
{
    return (unsigned char)(((h % 12) * 5 + m / 12) % 60);
}

static void draw_marks(void)
{
    unsigned char k, k2;
    for (k = 0; k < 60; k += 2) {                 /* rim: 30 segments */
        k2 = (unsigned char)((k + 2) % 60);
        line(px_at(k, R), py_at(k, R), px_at(k2, R), py_at(k2, R), 1);
    }
    for (k = 0; k < 60; k += 5)                    /* 12 hour ticks */
        line(px_at(k, R), py_at(k, R), px_at(k, TICK_IN), py_at(k, TICK_IN), 1);
}

static void draw_hands(unsigned char h, unsigned char m, unsigned char s,
                       unsigned char pen_hm, unsigned char pen_s)
{
    hand(hourpos(h, m), L_HOUR, pen_hm);
    hand(m, L_MIN, pen_hm);
    hand(s, L_SEC, pen_s);
}

static char dig[9];
static void put2(char *p, unsigned char v) { p[0] = '0' + v / 10; p[1] = '0' + v % 10; }
static void draw_digital(unsigned char h, unsigned char m, unsigned char s)
{
    put2(dig, h); dig[2] = ':'; put2(dig + 3, m); dig[5] = ':'; put2(dig + 6, s); dig[8] = 0;
    gb_fill(win_x + 8, win_y + 108, 12, 8, 0);
    gb_text(win_x + 8, win_y + 108, dig);
}

/* full_draw: paint the whole window (initial / on_repaint). */
static void full_draw(void)
{
    unsigned char h, m, s;
    gb_time();
    h = bin(gb_hour); m = bin(gb_min); s = bin(gb_sec);
    gb_curhide();
    gb_window(win_x, win_y, WIN_W, WIN_H, "Clock");
    draw_marks();
    draw_hands(h, m, s, 1, 3);
    draw_digital(h, m, s);
    gb_curshow();
    ph = h; pm = m; ps = s; have_prev = 1;
}

/* tick: advance the hands one step without clearing the face (erase old, repair the
   rim/ticks, draw new) so only the hands appear to move. */
static void tick(void)
{
    unsigned char h = bin(gb_hour), m = bin(gb_min), s = bin(gb_sec);
    gb_curhide();
    if (have_prev) {
        draw_hands(ph, pm, ps, 0, 0);             /* erase old hands (background) */
        draw_marks();                              /* repair the rim/ticks they crossed */
    }
    draw_hands(h, m, s, 1, 3);                     /* white hands, red second */
    draw_digital(h, m, s);
    gb_curshow();
    ph = h; pm = m; ps = s; have_prev = 1;
}

static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my;

    if (flags & GB_QUIT) { gb_wm_close(); return; }

    gb_time();                                     /* update once the second changes */
    if (!have_prev || bin(gb_sec) != ps) tick();

    if (!(flags & GB_CLICK)) return;
    mx = gb_mx(); my = gb_my();
    if (my >= win_y && my < win_y + TITLE_H) {
        if (mx >= win_x && mx < win_x + 5) { gb_wm_close(); return; }   /* close gadget */
        if (mx >= win_x + 5 && mx < win_x + WIN_W) {                    /* drag */
            if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
                gb_wm_setpos(win_x, win_y);
                gb_restore_parent();
            }
        }
    }
}

static const gb_win_t clkwin = {
    DEF_X, DEF_Y, WIN_W, WIN_H, on_frame, full_draw, 0, 0
};

void main(void)
{
    win_x = DEF_X; win_y = DEF_Y; have_prev = 0;
    gb_wm_add(&clkwin);
    full_draw();
}
