/* gbslider.c - opt-in horizontal slider and pointer-to-value mapping. */
#include "gb.h"

#define THUMB_W    2

void gb_slider(unsigned char x, unsigned char y, unsigned char w, unsigned char h,
               unsigned char value, unsigned char max, unsigned char flags)
{
    unsigned char span, tx, pen;
    if (w < 5 || h < 3) return;
    if (value > max) value = max;
    span = (unsigned char)(w - THUMB_W - 2);
    tx = (unsigned char)(x + 1);
    if (max) tx = (unsigned char)(tx + ((unsigned int)span * value) / max);
    pen = (flags & GB_WIDGET_FOCUSED) ? GB_UI_ACCENT : GB_UI_EDGE;
    gb_fill(x, y, w, h, GB_UI_SURFACE);
    gb_frame(x, y, w, h, pen);
    gb_fill((unsigned char)(x + 1), (unsigned char)(y + (h >> 1)),
            (unsigned char)(w - 2), 1, GB_UI_EDGE);
    gb_fill(tx, (unsigned char)(y + 1), THUMB_W,
            (unsigned char)(h - 2), GB_UI_ACCENT);
}

unsigned char gb_slider_hit(unsigned char x, unsigned char y,
                            unsigned char w, unsigned char h,
                            unsigned char mx, unsigned char my)
{
    return (unsigned char)(mx >= x && mx < x + w && my >= y && my < y + h);
}

unsigned char gb_slider_value(unsigned char x, unsigned char w,
                              unsigned char max, unsigned char mx)
{
    unsigned char start, span, rel;
    if (!max || w < 5) return 0;
    start = (unsigned char)(x + 1);
    span = (unsigned char)(w - THUMB_W - 2);
    if (mx <= start) return 0;
    if (mx >= start + span) return max;
    rel = (unsigned char)(mx - start);
    return (unsigned char)(((unsigned int)rel * max + (span >> 1)) / span);
}
