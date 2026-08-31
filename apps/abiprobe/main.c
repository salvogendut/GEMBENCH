/* ABIPROBE.APP - first compile-once GEOBENCH-2 SDK/package proof. */
#include "gbuniversal.h"

#define PROBE_W 58u
#define PROBE_H 68u
#define CONTENT_TOP 14u

static unsigned char accent;

static void draw(void)
{
    gb_rect_t rect;
    gb_window_rect(&rect);
    gb_fill((unsigned char)(rect.x + 1u),
            (unsigned char)(rect.y + CONTENT_TOP),
            (unsigned char)(rect.w - 2u),
            (unsigned char)(rect.h - CONTENT_TOP - 1u), GB_UI_SURFACE);
    gb_textbw((unsigned char)(rect.x + 4u),
              (unsigned char)(rect.y + CONTENT_TOP + 8u),
              "GEOBENCH-2 ABI");
    gb_textbw((unsigned char)(rect.x + 4u),
              (unsigned char)(rect.y + CONTENT_TOP + 24u),
              "ONE APP / 3 Z80S");
    gb_fill((unsigned char)(rect.x + 4u),
            (unsigned char)(rect.y + CONTENT_TOP + 40u),
            (unsigned char)(rect.w - 8u), 6u,
            accent ? GB_UI_ACCENT : GB_UI_EDGE);
}

static void click(void)
{
    gb_rect_t rect;
    accent ^= 1u;
    gb_window_rect(&rect);
    gb_wm_damage((unsigned char)(rect.x + 4u),
                 (unsigned char)(rect.y + CONTENT_TOP + 40u),
                 (unsigned char)(rect.w - 8u), 6u);
    gb_restore_parent();
}

static void window_proc(void)
{
    gb_msg_t message;
    gb_message_read(&message);
    switch (message.type) {
        case GB_MSG_DRAW:  draw();             break;
        case GB_MSG_CLICK: click();            break;
        case GB_MSG_DRAG:
            if (gb_window_drag() == GB_APP_OK) gb_restore_parent();
            break;
        case GB_MSG_CLOSE: gb_wm_close();      break;
    }
}

static gb_mwin_t probe_window = {
    0, 0, PROBE_W, PROBE_H, 0, 0, window_proc, "Universal ABI"
};

void main(void)
{
    unsigned char columns;
    unsigned char lines;
    if (!gb_universal_ready()) return;
    columns = gb_screen_columns();
    lines = gb_screen_lines();
    if (columns < PROBE_W || lines < PROBE_H) return;
    probe_window.x = (unsigned char)((columns - PROBE_W) >> 1);
    probe_window.y = (unsigned char)((lines - PROBE_H) >> 1);
    gb_wm_managed(&probe_window);
    gb_restore_parent();
}
