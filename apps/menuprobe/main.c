/* Compile-once menu/focus integration check. No native state or target macros. */
#include "gbuniversal.h"

static unsigned char accent, pending;
volatile unsigned char menuprobe_state[3]; /* delivered, selected, popup live */
static const unsigned char menu[] = {
    2, 10, 'P','r','o','b','e',0,0,0, 26, 'T','o','o','l','s',0,0,0
};
static const char *const items[] = { "Toggle", "Cancel" };

static void draw(void)
{
    gb_rect_t r;
    gb_window_rect(&r);
    gb_fill(r.x+1, r.y+14, r.w-2, r.h-15, GB_UI_SURFACE);
    gb_textbw(r.x+4, r.y+22, "GEOBENCH-2 ABI");
    gb_textbw(r.x+4, r.y+38, "ONE APP / 3 Z80S");
    gb_fill(r.x+4, r.y+54, r.w-8, 6, accent ? GB_UI_ACCENT : GB_UI_EDGE);
}

static void toggle(void)
{
    gb_rect_t r;
    accent ^= 1;
    gb_window_rect(&r);
    gb_wm_damage(r.x+4, r.y+54, r.w-8, 6);
    gb_restore_parent();
}

static void window_proc(void)
{
    gb_msg_t m;
    gb_message_read(&m);
    switch (m.type) {
    case GB_MSG_DRAW: draw(); break;
    case GB_MSG_CLICK: toggle(); break;
    case GB_MSG_MENU:
        if (gb_universal_popup_active()) gb_universal_popup_close();
        else if ((m.p0 >= 10 && m.p0 < 18) || (m.p0 >= 26 && m.p0 < 34)) {
            ++menuprobe_state[0];
            pending = m.p0 < 18 ? 10 : 26;
        }
        break;
    case GB_MSG_FRAME:
        if (pending) {
            unsigned char x = pending, selected;
            pending = 0;
            menuprobe_state[2] = 1;
            selected = gb_universal_popup(x, items, 2);
            menuprobe_state[2] = 0;
            if (selected == 0) { ++menuprobe_state[1]; toggle(); }
        }
        break;
    case GB_MSG_DRAG:
        if (gb_window_drag() == GB_APP_OK) gb_restore_parent();
        break;
    case GB_MSG_CLOSE: gb_wm_close(); break;
    }
}

static gb_mwin_t window = { 17, 90, 58, 68, 0, 0, window_proc, "Menu ABI" };

void main(void)
{
    if (!gb_universal_ready() || gb_screen_columns() < 75 || gb_screen_lines() < 158) return;
    gb_wm_managed(&window);
    gb_menu(menu);
    gb_restore_parent();
}
