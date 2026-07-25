/* gbselect.c - opt-in popup/list selector field. */
#include "gb.h"

#define UI_SURFACE 1
#define UI_EDGE    2
#define UI_ACCENT  3

static unsigned char select_text_y(unsigned char y, unsigned char h)
{
    if (h <= 8) return y;
    return (unsigned char)(y + ((h - 8 + 1) >> 1));
}

void gb_select(unsigned char x, unsigned char y, unsigned char w, unsigned char h,
               const char *value, unsigned char flags)
{
    unsigned char ty = select_text_y(y, h);
    gb_fill(x, y, w, h, UI_SURFACE);
    gb_frame(x, y, w, h,
             (flags & GB_WIDGET_FOCUSED) ? UI_ACCENT : UI_EDGE);
    gb_textbw((unsigned char)(x + 1), ty, value);
    if (w >= 4) gb_textbw((unsigned char)(x + w - 3), ty, ">");
}

unsigned char gb_select_hit(unsigned char x, unsigned char y,
                            unsigned char w, unsigned char h,
                            unsigned char mx, unsigned char my)
{
    return (unsigned char)(mx >= x && mx < x + w && my >= y && my < y + h);
}
