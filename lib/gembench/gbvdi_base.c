/*
 * Compact base-palette VDI profile for code-tight applications.
 *
 * It deliberately exposes only init/fill/frame: semantic roles map directly
 * to the four GEMBENCH base pens, while the full profile adds remapping,
 * raster images, and text.  The context layout remains identical so a caller
 * can move to the full profile without changing its own state.
 */
#include "gb.h"
#include "gbvdi.h"

unsigned char gb_vdi_init(gb_vdi_context_t *context,
                          unsigned char x, unsigned char y,
                          unsigned char w, unsigned char h)
{
    if (context == 0 || w == 0 || h == 0 ||
        (unsigned int)x + w > GB_COLS ||
        (unsigned int)y + h > GB_LINES)
        return 0;
    context->clip_x = x;
    context->clip_w = w;
    context->clip_y = y;
    context->clip_h = h;
    return 1;
}

unsigned char gb_vdi_fill(const gb_vdi_context_t *context,
                          unsigned char x, unsigned char y,
                          unsigned char w, unsigned char h,
                          unsigned char pen)
{
    unsigned char right, bottom, clip_right, clip_bottom;
    unsigned char left, top;
    if (context == 0 || pen > GB_VDI_ROLE_ACCENT || w == 0 || h == 0)
        return 0;
    clip_right = (unsigned char)(context->clip_x + context->clip_w);
    clip_bottom = (unsigned char)(context->clip_y + context->clip_h);
    if (x >= clip_right || y >= clip_bottom) return 1;
    left = x > context->clip_x ? x : context->clip_x;
    top = y > context->clip_y ? y : context->clip_y;
    right = w > (unsigned char)(clip_right - x) ?
        clip_right : (unsigned char)(x + w);
    bottom = h > (unsigned char)(clip_bottom - y) ?
        clip_bottom : (unsigned char)(y + h);
    if (right <= left || bottom <= top) return 1;
    gb_fill(left, top, (unsigned char)(right - left),
            (unsigned char)(bottom - top), pen);
    return 1;
}

unsigned char gb_vdi_frame(const gb_vdi_context_t *context,
                           unsigned char x, unsigned char y,
                           unsigned char w, unsigned char h,
                           unsigned char pen)
{
    unsigned char clip_right, clip_bottom;
    if (context == 0 || pen > GB_VDI_ROLE_ACCENT || w == 0 || h == 0)
        return 0;
    clip_right = (unsigned char)(context->clip_x + context->clip_w);
    clip_bottom = (unsigned char)(context->clip_y + context->clip_h);
    if (x < context->clip_x || x >= clip_right ||
        w > (unsigned char)(clip_right - x) ||
        y < context->clip_y || y >= clip_bottom ||
        h > (unsigned char)(clip_bottom - y))
        return 0;
    gb_frame(x, y, w, h, pen);
    return 1;
}
