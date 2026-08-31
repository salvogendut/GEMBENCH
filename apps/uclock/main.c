/* Compile-once Clock with generation-safe, occlusion-aware background damage. */
#include "gbuniversal.h"
#include "gbdefer.h"
#include "gbshell.h"

#define DEF_W        28u
#define DEF_H        122u
#define MIN_W        22u
#define MIN_H        96u
#define TITLE_H      14u
#define ACCESSORY_ID 1u

#define TIMER_HANDS   1u
#define TIMER_SECONDS 2u
#define TIMER_DIGITAL 3u

static unsigned char win_x, win_y, win_w = DEF_W, win_h = DEF_H;
static unsigned char show_sec, have_prev;
static unsigned char ph, pm, ps, pshow;
static unsigned char dh, dm, ds, dshow;
static unsigned char timer_part, timer_digit_due;
static unsigned char timer_h, timer_m, timer_s;
static gb_window_t clock_window_handle;
static unsigned char pending_menu, fullscreen;
static unsigned char saved_x, saved_y, saved_w, saved_h;

#define VIEW_COL    10u
#define OPTIONS_COL 17u

static const unsigned char clock_menu[] = {
    2u,
    VIEW_COL,    'V', 'i', 'e', 'w', 0u, 0u, 0u, 0u,
    OPTIONS_COL, 'O', 'p', 't', 'i', 'o', 'n', 's', 0u
};
static const char *const view_items[] = { "Fullscreen" };
static const char *const option_items[] = { "Toggle Seconds" };

static int cx, cy;
static unsigned char rr, tick_in, l_hour, l_min, l_sec, dig_y;
static unsigned int aspect_x;

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

static unsigned char binary_time(unsigned char value, unsigned char binary)
{
    return binary ? value : (unsigned char)((value >> 4) * 10u + (value & 15u));
}

static void read_time(unsigned char refresh, unsigned char *h,
                      unsigned char *m, unsigned char *s)
{
    gb_time_snapshot_t time;
    if (refresh) gb_time_read(&time);
    else gb_time_observe(&time);
    *h = binary_time(time.hour, time.binary);
    *m = binary_time(time.minute, time.binary);
    *s = binary_time(time.second, time.binary);
}

static void relayout(void)
{
    unsigned char top = (unsigned char)(win_y + TITLE_H);
    unsigned char dy = (unsigned char)(win_y + win_h - 16u);
    unsigned char avail = (unsigned char)(dy - 2u - top);
    unsigned char rw = (unsigned char)(win_w * 2u - 6u);
    unsigned char rh = (unsigned char)(avail / 2u - 2u);
    unsigned char rwv = (unsigned char)((unsigned long)rw * 256u / aspect_x);
    rr = rwv < rh ? rwv : rh;
    cx = (int)((unsigned int)win_x * 4u + (unsigned int)win_w * 2u);
    cy = (int)(top + avail / 2u);
    tick_in = (unsigned char)((unsigned int)rr * 37u / 44u);
    l_hour = (unsigned char)((unsigned int)rr * 20u / 44u);
    l_min = (unsigned char)((unsigned int)rr * 30u / 44u);
    l_sec = (unsigned char)((unsigned int)rr * 36u / 44u);
    dig_y = dy;
}

static int px_at(unsigned char pos, unsigned char rad)
{
    long delta = (long)SIN64[pos] * (long)rad * (long)aspect_x;
    return cx + (int)(delta / 16384L);
}

static int py_at(unsigned char pos, unsigned char rad)
{
    return cy - (int)COS64[pos] * rad / 64;
}

static void hand(unsigned char pos, unsigned char length, unsigned char pen)
{
    gb_line((unsigned int)cx, (unsigned int)cy,
            (unsigned int)px_at(pos, length),
            (unsigned int)py_at(pos, length), pen);
}

static unsigned char hour_pos(unsigned char h, unsigned char m)
{
    return (unsigned char)(((h % 12u) * 5u + m / 12u) % 60u);
}

static void draw_face(void)
{
    unsigned char k, next;
    for (k = 0u; k < 60u; k += 2u) {
        next = (unsigned char)((k + 2u) % 60u);
        gb_line((unsigned int)px_at(k, rr), (unsigned int)py_at(k, rr),
                (unsigned int)px_at(next, rr), (unsigned int)py_at(next, rr),
                GB_UI_SURFACE);
    }
    for (k = 0u; k < 60u; k += 5u)
        gb_line((unsigned int)px_at(k, rr), (unsigned int)py_at(k, rr),
                (unsigned int)px_at(k, tick_in),
                (unsigned int)py_at(k, tick_in), GB_UI_SURFACE);
}

static void hands(unsigned char h, unsigned char m, unsigned char s,
                  unsigned char seconds, unsigned char hm_pen,
                  unsigned char second_pen)
{
    hand(hour_pos(h, m), l_hour, hm_pen);
    hand(m, l_min, hm_pen);
    if (seconds) hand(s, l_sec, second_pen);
}

static char digits[9];

static void put2(char *out, unsigned char value)
{
    out[0] = (char)('0' + value / 10u);
    out[1] = (char)('0' + value % 10u);
}

static void draw_digital(unsigned char h, unsigned char m, unsigned char s)
{
    unsigned char width = show_sec ? 12u : 8u;
    unsigned char x = (unsigned char)(win_x + (win_w - width) / 2u);
    put2(digits, h); digits[2] = ':'; put2(digits + 3, m);
    if (show_sec) { digits[5] = ':'; put2(digits + 6, s); digits[8] = 0; }
    else digits[5] = 0;
    gb_fill(x, dig_y, width, 8u, GB_UI_CANVAS);
    gb_text_semantic(x, dig_y, digits, GB_UI_SURFACE, GB_UI_CANVAS);
}

static void draw_seconds(unsigned char s)
{
    unsigned char x = (unsigned char)(win_x + (win_w - 12u) / 2u + 9u);
    put2(digits, s); digits[2] = 0;
    gb_fill(x, dig_y, 3u, 8u, GB_UI_CANVAS);
    gb_text_semantic(x, dig_y, digits, GB_UI_SURFACE, GB_UI_CANVAS);
}

static int damage_l, damage_r, damage_t, damage_b;

static void damage_endpoint(unsigned char pos, unsigned char length)
{
    int x = px_at(pos, length), y = py_at(pos, length);
    if (x < damage_l) damage_l = x;
    if (x > damage_r) damage_r = x;
    if (y < damage_t) damage_t = y;
    if (y > damage_b) damage_b = y;
}

static void publish_hand_damage(unsigned char h, unsigned char m, unsigned char s)
{
    unsigned char x, right;
    damage_l = damage_r = cx;
    damage_t = damage_b = cy;
    damage_endpoint(hour_pos(ph, pm), l_hour);
    damage_endpoint(pm, l_min);
    if (pshow) damage_endpoint(ps, l_sec);
    damage_endpoint(hour_pos(h, m), l_hour);
    damage_endpoint(m, l_min);
    if (show_sec) damage_endpoint(s, l_sec);
    x = (unsigned char)(damage_l >> 2);
    right = (unsigned char)((damage_r + 4) >> 2);
    timer_part = TIMER_HANDS;
    (void)gb_timer_damage_for(clock_window_handle, x, (unsigned char)damage_t,
                              (unsigned char)(right - x),
                              (unsigned char)(damage_b - damage_t + 1));
}

static void clock_timer(void)
{
    unsigned char h, m, s;
    if (!have_prev || !clock_window_handle) return;
    if (gb_timer_take_dropped(clock_window_handle)) {
        if (timer_part == TIMER_HANDS) {
            ph = timer_h; pm = timer_m; ps = timer_s; pshow = show_sec;
            timer_digit_due = 1u;
        } else {
            dh = timer_h; dm = timer_m; ds = timer_s; dshow = show_sec;
            timer_digit_due = 0u;
        }
    }
    if (gb_timer_busy()) return;
    read_time(0u, &h, &m, &s);
    timer_h = h; timer_m = m; timer_s = s;
    if (timer_digit_due) {
        if (show_sec && h == dh && m == dm && dshow) {
            timer_part = TIMER_SECONDS;
            (void)gb_timer_damage_for(clock_window_handle,
                (unsigned char)(win_x + (win_w - 12u) / 2u + 9u), dig_y, 3u, 8u);
        } else {
            unsigned char width = show_sec ? 12u : 8u;
            timer_part = TIMER_DIGITAL;
            (void)gb_timer_damage_for(clock_window_handle,
                (unsigned char)(win_x + (win_w - width) / 2u), dig_y, width, 8u);
        }
        return;
    }
    if (h != ph || m != pm || (show_sec && s != ps) || show_sec != pshow) {
        publish_hand_damage(h, m, s);
        return;
    }
    if (h == dh && m == dm && show_sec == dshow && (!show_sec || s == ds)) return;
    if (show_sec && h == dh && m == dm && dshow) {
        timer_part = TIMER_SECONDS;
        (void)gb_timer_damage_for(clock_window_handle,
            (unsigned char)(win_x + (win_w - 12u) / 2u + 9u), dig_y, 3u, 8u);
    } else {
        unsigned char width = show_sec ? 12u : 8u;
        timer_part = TIMER_DIGITAL;
        (void)gb_timer_damage_for(clock_window_handle,
            (unsigned char)(win_x + (win_w - width) / 2u), dig_y, width, 8u);
    }
}

static void sync_rect(void)
{
    gb_rect_t rect;
    gb_window_rect(&rect);
    win_x = rect.x; win_y = rect.y; win_w = rect.w; win_h = rect.h;
    relayout();
}

static void draw(void)
{
    unsigned char h, m, s;
    sync_rect();
    if (gb_timer_take_dropped(clock_window_handle)) { }
    if (gb_timer_active_for(clock_window_handle)) {
        h = timer_h; m = timer_m; s = timer_s;
        if (timer_part == TIMER_HANDS) {
            hands(h, m, s, show_sec, GB_UI_SURFACE, GB_UI_ACCENT);
            ph = h; pm = m; ps = s; pshow = show_sec;
            timer_digit_due = 1u;
        } else if (timer_part == TIMER_SECONDS) {
            draw_seconds(s);
            dh = h; dm = m; ds = s; dshow = show_sec;
            timer_digit_due = 0u;
        } else {
            draw_digital(h, m, s);
            dh = h; dm = m; ds = s; dshow = show_sec;
            timer_digit_due = 0u;
        }
        return;
    }
    gb_timer_cancel(clock_window_handle);
    read_time(1u, &h, &m, &s);
    /* The compositor owns the one-column side/bottom frame.  Painting the
     * complete rectangle here erases that chrome after every callback. */
    gb_fill((unsigned char)(win_x + 1u), (unsigned char)(win_y + TITLE_H),
            (unsigned char)(win_w - 2u),
            (unsigned char)(win_h - TITLE_H - 1u), GB_UI_CANVAS);
    draw_face();
    hands(h, m, s, show_sec, GB_UI_SURFACE, GB_UI_ACCENT);
    draw_digital(h, m, s);
    ph = dh = h; pm = dm = m; ps = ds = s;
    pshow = dshow = show_sec;
    have_prev = 1u;
    timer_digit_due = 0u;
}

static void focused_tick(void)
{
    unsigned char h, m, s;
    read_time(1u, &h, &m, &s);
    if (have_prev && h == ph && m == pm && (!show_sec || s == ps) &&
        show_sec == pshow) return;
    if (have_prev) hands(ph, pm, ps, pshow, GB_UI_CANVAS, GB_UI_CANVAS);
    hands(h, m, s, show_sec, GB_UI_SURFACE, GB_UI_ACCENT);
    if (show_sec && dshow && h == dh && m == dm) draw_seconds(s);
    else draw_digital(h, m, s);
    ph = dh = h; pm = dm = m; ps = ds = s;
    pshow = dshow = show_sec;
    have_prev = 1u;
    timer_digit_due = 0u;
}

static void toggle_fullscreen(void)
{
    unsigned char columns = gb_screen_columns();
    unsigned char lines = gb_screen_lines();
    if (!fullscreen) {
        saved_x = win_x; saved_y = win_y; saved_w = win_w; saved_h = win_h;
        gb_wm_setpos(0u, 8u);
        gb_wm_setsize(columns, (unsigned char)(lines - 8u));
        fullscreen = 1u;
    } else {
        gb_wm_setpos(saved_x, saved_y);
        gb_wm_setsize(saved_w, saved_h);
        fullscreen = 0u;
    }
    sync_rect();
    have_prev = 0u;
    gb_timer_cancel(clock_window_handle);
    gb_wm_damage(0u, 8u, columns, (unsigned char)(lines - 8u));
    gb_restore_parent();
}

static unsigned char run_pending_menu(void)
{
    unsigned char request = pending_menu, selected;
    if (!request) return 0u;
    pending_menu = 0u;
    if (request == 1u) {
        selected = gb_universal_popup(VIEW_COL, view_items, 1u);
        if (selected == 0u) toggle_fullscreen();
    } else {
        selected = gb_universal_popup(OPTIONS_COL, option_items, 1u);
        if (selected == 0u) {
            show_sec ^= 1u;
            have_prev = 0u;
            gb_timer_cancel(clock_window_handle);
            gb_wm_damage(win_x, win_y, win_w, win_h);
            gb_restore_parent();
        }
    }
    return 1u;
}

static void window_proc(void)
{
    gb_msg_t message;
    gb_message_read(&message);
    if (message.type == GB_MSG_DEFER) {
        const gb_defer_message_t *deferred = gb_defer_current();
        if (deferred && deferred->type == GB_DEFER_SHELL && deferred->p0 == 2u)
            gb_message_set_p2(1u);
        return;
    }
    switch (message.type) {
        case GB_MSG_DRAW: draw(); break;
        case GB_MSG_FRAME: {
            unsigned char key = gb_getkey();
            if (run_pending_menu()) break;
            if (key == 's' || key == 'S') {
                show_sec ^= 1u;
                have_prev = 0u;
                gb_wm_damage(win_x, win_y, win_w, win_h);
                gb_restore_parent();
            } else focused_tick();
            break;
        }
        case GB_MSG_MENU:
            if (gb_universal_popup_active()) gb_universal_popup_close();
            else if (message.p0 >= VIEW_COL && message.p0 < OPTIONS_COL)
                pending_menu = 1u;
            else if (message.p0 >= OPTIONS_COL && message.p0 < 28u)
                pending_menu = 2u;
            break;
        case GB_MSG_MOVED:
        case GB_MSG_SIZED:
        case GB_MSG_MAXIMIZED:
            sync_rect(); have_prev = 0u; gb_timer_cancel(clock_window_handle); break;
        case GB_MSG_CLOSE: gb_wm_close(); break;
    }
}

static gb_mwin_kind_t clock_window = {
    { 0u, 20u, DEF_W, DEF_H, MIN_W, MIN_H, window_proc, "Clock", clock_timer },
    GB_WK_STANDARD
};

void main(void)
{
    unsigned char columns, lines;
    if (!gb_universal_ready() ||
        !gb_has_capability(GB_CAP_BACKGROUND_TIMERS)) return;
    columns = gb_screen_columns();
    lines = gb_screen_lines();
    if (columns < DEF_W || lines < DEF_H) return;
    aspect_x = gb_pixel_aspect_x_256();
    clock_window.window.x = (unsigned char)((columns - DEF_W) >> 1);
    gb_wm_managed_kind(&clock_window);
    clock_window_handle = gb_window_current();
    gb_menu(clock_menu);
    (void)gb_shell_register_accessory(ACCESSORY_ID);
    (void)gb_defer_register(window_proc);
    gb_restore_parent();
    gb_task_enable();
}
