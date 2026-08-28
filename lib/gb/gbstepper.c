/* gbstepper.c - opt-in decrement/value/increment control. */
#include "gb.h"

#define STEP_W     3

static unsigned char step_text_cols(const char *s)
{
    unsigned char n = 0;
    while (s[n]) n++;
    return (unsigned char)(n + ((n + 1) >> 1));
}

static unsigned char step_text_y(unsigned char y, unsigned char h)
{
    if (h <= 8) return y;
    return (unsigned char)(y + ((h - 8 + 1) >> 1));
}

void gb_stepper(unsigned char x, unsigned char y, unsigned char w, unsigned char h,
                const char *value, unsigned char flags)
{
    unsigned char middle, tw, tx, ty, pen;
    if (w < STEP_W * 2 + 1) return;
    middle = (unsigned char)(w - STEP_W * 2);
    tw = step_text_cols(value);
    tx = (tw < middle) ? (unsigned char)(x + STEP_W + ((middle - tw) >> 1))
                       : (unsigned char)(x + STEP_W);
    ty = step_text_y(y, h);
    pen = (flags & GB_WIDGET_FOCUSED) ? GB_UI_ACCENT : GB_UI_EDGE;
    gb_fill(x, y, w, h, GB_UI_SURFACE);
    gb_frame(x, y, STEP_W, h, pen);
    gb_frame((unsigned char)(x + STEP_W), y, middle, h, pen);
    gb_frame((unsigned char)(x + w - STEP_W), y, STEP_W, h, pen);
    gb_textbw((unsigned char)(x + 1), ty, "-");
    gb_textbw(tx, ty, value);
    gb_textbw((unsigned char)(x + w - STEP_W + 1), ty, "+");
}

unsigned char gb_stepper_hit(unsigned char x, unsigned char y,
                             unsigned char w, unsigned char h,
                             unsigned char mx, unsigned char my)
{
    if (w < STEP_W * 2 + 1 || mx < x || mx >= x + w ||
        my < y || my >= y + h)
        return GB_STEPPER_NONE;
    if (mx < x + STEP_W) return GB_STEPPER_DEC;
    if (mx >= x + w - STEP_W) return GB_STEPPER_INC;
    return GB_STEPPER_VALUE;
}
