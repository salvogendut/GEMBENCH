/* gbtoggle.c - opt-in checkbox/toggle shared by GEOBENCH applications. */
#include "gb.h"

#define UI_SURFACE 1
#define UI_EDGE    2
#define UI_ACCENT  3
#define BOX_W      3

static unsigned char toggle_text_y(unsigned char y, unsigned char h)
{
    if (h <= 8) return y;
    return (unsigned char)(y + ((h - 8 + 1) >> 1));
}

void gb_toggle(unsigned char x, unsigned char y, unsigned char w, unsigned char h,
               const char *label, unsigned char flags)
{
    unsigned char ty = toggle_text_y(y, h);
    gb_fill(x, y, w, h, UI_SURFACE);
    gb_frame(x, y, BOX_W, h,
             (flags & GB_WIDGET_FOCUSED) ? UI_ACCENT : UI_EDGE);
    if (flags & GB_WIDGET_CHECKED)
        gb_textbw((unsigned char)(x + 1), ty, "x");
    gb_textbw((unsigned char)(x + BOX_W + 1), ty, label);
}

unsigned char gb_toggle_hit(unsigned char x, unsigned char y,
                            unsigned char w, unsigned char h,
                            unsigned char mx, unsigned char my)
{
    return (unsigned char)(mx >= x && mx < x + w && my >= y && my < y + h);
}
