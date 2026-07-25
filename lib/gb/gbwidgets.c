/* gbwidgets.c - compact, opt-in controls shared by GEOBENCH applications.
 *
 * Keep state and layout in the app. These helpers only draw consistent controls
 * and classify clicks, which avoids a retained widget tree and any kernel cost.
 */
#include "gb.h"

#define UI_SURFACE 1
#define UI_EDGE    2
#define UI_ACCENT  3

static unsigned char text_cols(const char *s)
{
    unsigned char n = 0;
    while (s[n]) n++;
    return (unsigned char)(n + ((n + 1) >> 1));  /* ceil((n * 6px) / 4px columns) */
}

static unsigned char text_y(unsigned char y, unsigned char h)
{
    if (h <= 8) return y;
    return (unsigned char)(y + ((h - 8 + 1) >> 1));
}

void gb_button(unsigned char x, unsigned char y, unsigned char w, unsigned char h,
               const char *label, unsigned char flags)
{
    unsigned char tw = text_cols(label);
    unsigned char tx = (tw + 2 < w) ? (unsigned char)(x + ((w - tw) >> 1))
                                     : (unsigned char)(x + 1);
    unsigned char ty = text_y(y, h);
    unsigned char pen = (flags & GB_WIDGET_DISABLED) ? UI_SURFACE :
                        (flags & (GB_WIDGET_FOCUSED | GB_WIDGET_PRESSED))
                            ? UI_ACCENT : UI_EDGE;
    if ((flags & GB_WIDGET_PRESSED) && !(flags & GB_WIDGET_DISABLED) && h > 9)
        ty++;
    gb_fill(x, y, w, h, UI_SURFACE);
    gb_frame(x, y, w, h, pen);
    gb_textbw(tx, ty, label);
}

void gb_field(unsigned char x, unsigned char y, unsigned char w, unsigned char h,
              const char *text, unsigned char flags)
{
    gb_fill(x, y, w, h, UI_SURFACE);
    gb_frame(x, y, w, h, (flags & GB_WIDGET_DISABLED) ? UI_SURFACE :
             (flags & GB_WIDGET_FOCUSED) ? UI_ACCENT : UI_EDGE);
    gb_textbw((unsigned char)(x + 1), text_y(y, h), text);
}

unsigned char gb_widget_hit(unsigned char x, unsigned char y,
                            unsigned char w, unsigned char h,
                            unsigned char mx, unsigned char my)
{
    return (unsigned char)(mx >= x && mx < x + w && my >= y && my < y + h);
}
