/* Bounded text measurement and alignment for the VDI-lite context. */
#include "gb.h"
#include "gbvdi.h"

#ifdef GB_MSX2
#define GB_VDI_MAX_PEN 15u
#else
#define GB_VDI_MAX_PEN 3u
#endif

void gb_vdi_text_raw(unsigned char col, unsigned char line,
                     unsigned char foreground, unsigned char background,
                     const char *text);

static unsigned char text_pen(const gb_vdi_context_t *context,
                              unsigned char value,
                              unsigned char *resolved)
{
    if (value > GB_VDI_MAX_PEN) return 0;
    *resolved = value < 4u ? context->pens[value] : value;
    return (unsigned char)(*resolved <= GB_VDI_MAX_PEN);
}

unsigned char gb_vdi_text_width(const char *text, unsigned char *width)
{
    unsigned char length = 0;
    if (text == 0 || width == 0) return 0;
    while (length < GB_VDI_TEXT_MAX && text[length]) length++;
    if (text[length]) return 0;
    *width = (unsigned char)((length * 6u + 3u) >> 2);
    return 1;
}

unsigned char gb_vdi_text(const gb_vdi_context_t *context,
                          unsigned char x, unsigned char y, unsigned char w,
                          const char *text, unsigned char alignment,
                          unsigned char foreground, unsigned char background)
{
    unsigned char text_width;
    unsigned char right;
    unsigned char clip_right;
    unsigned char clip_bottom;
    unsigned char col;
    unsigned char fg, bg;
    if (!gb_vdi_valid(context) || alignment > GB_VDI_ALIGN_RIGHT ||
        !text_pen(context, foreground, &fg) ||
        !text_pen(context, background, &bg) ||
        !gb_vdi_text_width(text, &text_width) || w == 0)
        return 0;
    if (x >= GB_COLS || w > (unsigned char)(GB_COLS - x)) return 0;
    right = (unsigned char)(x + w);
    clip_right = (unsigned char)(context->clip_x + context->clip_w);
    clip_bottom = (unsigned char)(context->clip_y + context->clip_h);
    if (x < context->clip_x || right > clip_right ||
        y < context->clip_y || (unsigned int)y + 8u > clip_bottom)
        return 0;
    if (text_width > w) return 0;
    col = x;
    if (alignment == GB_VDI_ALIGN_CENTER)
        col = (unsigned char)(col + (w - text_width) / 2u);
    else if (alignment == GB_VDI_ALIGN_RIGHT)
        col = (unsigned char)(col + w - text_width);
    gb_vdi_text_raw(col, y, fg, bg, text);
    return 1;
}
