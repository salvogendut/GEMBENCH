/* clock - the GEOBENCH analog clock (C), a co-resident window (#72).
 *
 * An xclock-style analog face: a round rim, 12 hour ticks, and hour/minute (and
 * optionally second) hands placed from a fixed-point sin/cos table, with a digital
 * read-out below. By default it shows hours+minutes and refreshes once a minute; an
 * "Options" top-bar menu toggles "Show Seconds" (per-second refresh) and offers
 * "Set time".
 *
 * Flicker-free: the hands are all shorter than the tick ring, so erasing a hand
 * (redrawing it in the background) never touches the rim/ticks - a tick just erases
 * the old hands and draws the new ones, and only lifts the pointer when it actually
 * sits over the window. The kernel has no line primitive (to stay lean); the clock
 * calls the CPC firmware graphics VDU directly for the hands.
 */
#include "gb.h"

#define DEF_X    24
#define DEF_Y    20
#define WIN_W    28           /* bytes (112 px) */
#define WIN_H    122          /* px */
#define TITLE_H  14

#define R        44           /* face radius (px) */
#define TICK_IN  37           /* hour-tick inner radius; hands stay inside this */
#define L_HOUR   20
#define L_MIN    30
#define L_SEC    36

#define MENU_COL 10           /* "Options" title column in the top bar */
#define MENU_END 22

#define CX       (win_x * 4 + WIN_W * 2)     /* live clock centre, screen pixels */
#define CY       (win_y + 58)

static unsigned char win_x = DEF_X, win_y = DEF_Y;
static unsigned char show_sec;               /* 0 = H:M (minute refresh), 1 = +seconds */
static unsigned char ph, pm, ps, pshow, have_prev;  /* previous h/m/s + show state */
static unsigned char want_menu, modal;

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

/* --- firmware graphics line (the kernel has no line primitive) --------------- */
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

/* --- RTC write (Set time), straight to the Dallas registers via inline asm ----- */
static volatile unsigned char rtc_reg, rtc_val;
static void rtc_poke(void) __naked
{
__asm
    ld   a, (_rtc_reg)
    ld   bc, #0xFD15     ; RTC address port
    out  (c), a
    ld   a, (_rtc_val)
    ld   bc, #0xFD14     ; RTC data port
    out  (c), a
    ret
__endasm;
}
static void set_rtc(unsigned char reg, unsigned char val) { rtc_reg = reg; rtc_val = val; rtc_poke(); }

/* the kernel hands us raw RTC registers; convert BCD -> binary unless it's binary */
static unsigned char bin(unsigned char v)
{
    return gb_binmode ? v : (unsigned char)((v >> 4) * 10 + (v & 15));
}
static unsigned char tobcd(unsigned char v)
{
    return gb_binmode ? v : (unsigned char)(((v / 10) << 4) | (v % 10));
}

/* --- drawing ----------------------------------------------------------------- */

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

static void draw_face(void)
{
    unsigned char k, k2;
    for (k = 0; k < 60; k += 2) {                 /* rim: 30 segments */
        k2 = (unsigned char)((k + 2) % 60);
        line(px_at(k, R), py_at(k, R), px_at(k2, R), py_at(k2, R), 1);
    }
    for (k = 0; k < 60; k += 5)                    /* 12 hour ticks */
        line(px_at(k, R), py_at(k, R), px_at(k, TICK_IN), py_at(k, TICK_IN), 1);
}

/* draw (or erase, pen 0) the hands for h:m[:s]. withsec controls the second hand. */
static void hands(unsigned char h, unsigned char m, unsigned char s,
                  unsigned char withsec, unsigned char pen_hm, unsigned char pen_s)
{
    hand(hourpos(h, m), L_HOUR, pen_hm);
    hand(m, L_MIN, pen_hm);
    if (withsec) hand(s, L_SEC, pen_s);
}

static char dig[9];
static void put2(char *p, unsigned char v) { p[0] = '0' + v / 10; p[1] = '0' + v % 10; }
static void draw_digital(unsigned char h, unsigned char m, unsigned char s)
{
    unsigned char x = show_sec ? (win_x + 8) : (win_x + 9);
    put2(dig, h); dig[2] = ':'; put2(dig + 3, m);
    if (show_sec) { dig[5] = ':'; put2(dig + 6, s); dig[8] = 0; }
    else dig[5] = 0;
    gb_fill(win_x + 6, win_y + 106, 16, 8, 0);
    gb_text(x, win_y + 106, dig);
}

static unsigned char cursor_over(void)
{
    unsigned char mx = gb_mx(), my = gb_my();
    return (unsigned char)(mx >= win_x && mx < win_x + WIN_W && my >= win_y && my < win_y + WIN_H);
}

/* full_draw: paint the whole window (open / on_repaint / after a drag or toggle). */
static void full_draw(void)
{
    unsigned char h, m, s;
    gb_time();
    h = bin(gb_hour); m = bin(gb_min); s = bin(gb_sec);
    gb_curhide();
    gb_window(win_x, win_y, WIN_W, WIN_H, "Clock");
    draw_face();
    hands(h, m, s, show_sec, 1, 3);
    draw_digital(h, m, s);
    gb_curshow();
    ph = h; pm = m; ps = s; pshow = show_sec; have_prev = 1;
}

/* tick: move the hands without touching the face. Only lifts the pointer if it is
   actually over the window (else no per-tick cursor flicker). */
static void tick(void)
{
    unsigned char h = bin(gb_hour), m = bin(gb_min), s = bin(gb_sec);
    unsigned char co = cursor_over();
    if (co) gb_curhide();
    if (have_prev) hands(ph, pm, ps, pshow, 0, 0);  /* erase old hands (background) */
    hands(h, m, s, show_sec, 1, 3);                 /* white hands, red second */
    draw_digital(h, m, s);
    if (co) gb_curshow();
    ph = h; pm = m; ps = s; pshow = show_sec; have_prev = 1;
}

/* changed: has the displayed time advanced (minute, or second when shown)? */
static unsigned char changed(void)
{
    if (!have_prev) return 1;
    return show_sec ? (bin(gb_sec) != ps) : (bin(gb_min) != pm);
}

/* --- Options menu + dialogs (modal, self-polling like the other apps) --------- */

static const unsigned char clk_menu[] = { 1, MENU_COL, 'O','p','t','i','o','n','s' };

static void on_menu(void)
{
    if (gb_msg.type != GB_MSG_MENU) return;
    if (gb_msg.p0 < MENU_COL || gb_msg.p0 >= MENU_END) return;
    want_menu = 1;
}

static unsigned char popup(unsigned char x, unsigned char y,
                           const char *const *labels, unsigned char n)
{
    unsigned char i, flags, row, sel = 0xFF;
    modal = 1;
    gb_curhide();
    gb_fill(x, y, 22, n * 10 + 4, 1);          /* white, no frame: a seamless drop from
                                                  the (white) top bar - black ink only */
    for (i = 0; i < n; i++) gb_textbw(x + 1, y + 2 + i * 10, labels[i]);
    gb_curshow();
    for (;;) {
        flags = gb_poll();
        if (flags & GB_QUIT) break;
        if (!(flags & GB_CLICK)) continue;
        if (gb_my() >= y + 2 && gb_my() < y + 2 + n * 10 && gb_mx() >= x && gb_mx() < x + 22) {
            row = (gb_my() - (y + 2)) / 10;
            if (row < n) { sel = row; break; }
        }
        break;
    }
    modal = 0;
    if (sel == 0xFF) while (gb_poll() & GB_QUIT) ;
    gb_curhide();
    gb_fill(x, y, 22, n * 10 + 4, 0);
    gb_curshow();
    return sel;
}

/* set_time_dialog: +/- on hours and minutes (triangle glyphs), OK applies to the
   RTC. Returns 1 if the time was set. */
static unsigned char hh, mm;
static void draw_field(unsigned char x, unsigned char y, unsigned char v)
{
    char t[3];
    gb_textbw(x, y, GLYPH_TRI_UP);
    put2(t, v); t[2] = 0;
    gb_fill(x, y + 9, 4, 8, 1);
    gb_textbw(x, y + 9, t);
    gb_textbw(x, y + 18, GLYPH_TRI_DOWN);
}
static unsigned char set_time_dialog(void)
{
    unsigned char flags, done = 0, ok = 0;
    unsigned char x = win_x + 3, y = win_y + 34, w = 22, h = 44;
    unsigned char hx = x + 4, mx = x + 13, ay = y + 6;

    gb_time();
    hh = bin(gb_hour); mm = bin(gb_min);
    modal = 1;
    gb_curhide();
    gb_fill(x, y, w, h, 1);
    gb_frame(x, y, w, h, 2);
    gb_textbw(x + 1, y + 1, "Set time");
    gb_textbw(hx + 5, ay + 9, ":");
    draw_field(hx, ay, hh);
    draw_field(mx, ay, mm);
    gb_textbw(x + 7, y + h - 9, "OK");
    gb_curshow();

    while (!done) {
        flags = gb_poll();
        if (flags & GB_QUIT) { done = 1; break; }
        if (!(flags & GB_CLICK)) continue;
        {
            unsigned char cx = gb_mx(), cy = gb_my();
            if (cy >= ay && cy < ay + 8) {                 /* up arrows */
                if (cx >= hx && cx < hx + 3) { hh = (hh + 1) % 24; draw_field(hx, ay, hh); }
                else if (cx >= mx && cx < mx + 3) { mm = (mm + 1) % 60; draw_field(mx, ay, mm); }
            } else if (cy >= ay + 18 && cy < ay + 26) {    /* down arrows */
                if (cx >= hx && cx < hx + 3) { hh = (hh + 23) % 24; draw_field(hx, ay, hh); }
                else if (cx >= mx && cx < mx + 3) { mm = (mm + 59) % 60; draw_field(mx, ay, mm); }
            } else if (cy >= y + h - 9 && cx >= x + 7 && cx < x + 13) {  /* OK */
                ok = 1; done = 1;
            } else if (cy < y || cy >= y + h || cx < x || cx >= x + w) {
                done = 1;                                   /* clicked away -> cancel */
            }
        }
    }
    modal = 0;
    if (flags & GB_QUIT) while (gb_poll() & GB_QUIT) ;
    gb_curhide();
    gb_fill(x, y, w, h, 0);
    gb_curshow();
    if (ok) {
        gb_time();                       /* refresh binmode before writing */
        set_rtc(4, tobcd(hh));           /* hours  */
        set_rtc(2, tobcd(mm));           /* minutes */
        set_rtc(0, tobcd(0));            /* seconds */
    }
    return ok;
}

static void run_menu(void)
{
    const char *items[2];
    unsigned char sel;
    items[0] = "Set time";
    items[1] = show_sec ? "Hide Seconds" : "Show Seconds";
    sel = popup(MENU_COL, 8, items, 2);
    if (sel == 0) { if (set_time_dialog()) have_prev = 0; full_draw(); }
    else if (sel == 1) { show_sec ^= 1; full_draw(); }
}

/* --- WM callbacks ------------------------------------------------------------ */

static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx, my;

    if (flags & GB_QUIT) { gb_wm_close(); return; }

    if (want_menu) { want_menu = 0; run_menu(); return; }

    gb_time();
    if (changed()) tick();

    if (!(flags & GB_CLICK)) return;
    mx = gb_mx(); my = gb_my();
    if (my >= win_y && my < win_y + TITLE_H) {
        if (mx >= win_x && mx < win_x + 5) { gb_wm_close(); return; }
        if (mx >= win_x + 5 && mx < win_x + WIN_W) {
            if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
                gb_wm_setpos(win_x, win_y);
                gb_restore_parent();
                full_draw();                       /* redraw the face at the new spot */
            }
        }
    }
}

static const gb_win_t clkwin = {
    DEF_X, DEF_Y, WIN_W, WIN_H, on_frame, full_draw, on_menu, clk_menu
};

void main(void)
{
    win_x = DEF_X; win_y = DEF_Y;
    show_sec = 0; have_prev = 0; want_menu = 0; modal = 0;
    gb_wm_add(&clkwin);
    full_draw();
}
