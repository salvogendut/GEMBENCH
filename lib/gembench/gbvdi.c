/* Caller-owned VDI-lite clip, semantic pen mapping, fill, and frame. */
#include "gb.h"
#include "gbvdi.h"

#ifdef GB_MSX2
#define GB_VDI_MAX_PEN 15u
#else
#define GB_VDI_MAX_PEN 3u
#endif

static unsigned char resolve_pen(const gb_vdi_context_t *context,
                                 unsigned char value,
                                 unsigned char *resolved)
{
    if (value > GB_VDI_MAX_PEN) return 0;
    *resolved = value < 4u ? context->pens[value] : value;
    return (unsigned char)(*resolved <= GB_VDI_MAX_PEN);
}

unsigned char gb_vdi_valid(const gb_vdi_context_t *context)
{
    unsigned int bottom;
    unsigned char index;
    if (context == 0 || context->clip_w == 0 || context->clip_h == 0 ||
        context->clip_x >= GB_COLS || context->clip_y >= GB_LINES)
        return 0;
    bottom = (unsigned int)context->clip_y + context->clip_h;
    if (context->clip_w > (unsigned char)(GB_COLS - context->clip_x) ||
        bottom > GB_LINES)
        return 0;
    for (index = 0; index < 4u; index++)
        if (context->pens[index] > GB_VDI_MAX_PEN) return 0;
    return 1;
}

unsigned char gb_vdi_init(gb_vdi_context_t *context,
                          unsigned char x, unsigned char y,
                          unsigned char w, unsigned char h)
{
    unsigned int bottom;
    if (context == 0 || w == 0 || h == 0 || x >= GB_COLS || y >= GB_LINES)
        return 0;
    bottom = (unsigned int)y + h;
    if (w > (unsigned char)(GB_COLS - x) || bottom > GB_LINES) return 0;
    context->clip_x = x;
    context->clip_w = w;
    context->clip_y = y;
    context->clip_h = h;
    context->pens[0] = 0;
    context->pens[1] = 1;
    context->pens[2] = 2;
    context->pens[3] = 3;
    return 1;
}

unsigned char gb_vdi_set_pens(gb_vdi_context_t *context,
                              unsigned char canvas, unsigned char surface,
                              unsigned char edge, unsigned char accent)
{
    if (!gb_vdi_valid(context) || canvas > GB_VDI_MAX_PEN ||
        surface > GB_VDI_MAX_PEN || edge > GB_VDI_MAX_PEN ||
        accent > GB_VDI_MAX_PEN)
        return 0;
    context->pens[0] = canvas;
    context->pens[1] = surface;
    context->pens[2] = edge;
    context->pens[3] = accent;
    return 1;
}

unsigned char gb_vdi_fill(const gb_vdi_context_t *context,
                          unsigned char x, unsigned char y,
                          unsigned char w, unsigned char h,
                          unsigned char pen)
{
    unsigned char left, right, top, bottom;
    unsigned char clip_right, clip_bottom;
    unsigned char resolved;
    if (!gb_vdi_valid(context) || !resolve_pen(context, pen, &resolved) ||
        w == 0 || h == 0)
        return 0;
    if (x >= GB_COLS || w > (unsigned char)(GB_COLS - x) ||
        (unsigned int)y + h > GB_LINES)
        return 0;
    right = (unsigned char)(x + w);
    bottom = (unsigned char)(y + h);
    clip_right = (unsigned char)(context->clip_x + context->clip_w);
    clip_bottom = (unsigned char)(context->clip_y + context->clip_h);
    left = x > context->clip_x ? x : context->clip_x;
    if (right > clip_right) right = clip_right;
    top = y > context->clip_y ? y : context->clip_y;
    if (bottom > clip_bottom) bottom = clip_bottom;
    if (right <= left || bottom <= top) return 1;
    gb_fill(left, top, (unsigned char)(right - left),
            (unsigned char)(bottom - top), resolved);
    return 1;
}

unsigned char gb_vdi_frame(const gb_vdi_context_t *context,
                           unsigned char x, unsigned char y,
                           unsigned char w, unsigned char h,
                           unsigned char pen)
{
    unsigned char right;
    unsigned char bottom;
    unsigned char clip_right;
    unsigned char clip_bottom;
    unsigned char resolved;
    if (!gb_vdi_valid(context) || !resolve_pen(context, pen, &resolved) ||
        w == 0 || h == 0)
        return 0;
    if (x >= GB_COLS || w > (unsigned char)(GB_COLS - x) ||
        (unsigned int)y + h > GB_LINES)
        return 0;
    right = (unsigned char)(x + w);
    bottom = (unsigned char)(y + h);
    clip_right = (unsigned char)(context->clip_x + context->clip_w);
    clip_bottom = (unsigned char)(context->clip_y + context->clip_h);
    if (right > clip_right || x < context->clip_x ||
        y < context->clip_y || bottom > clip_bottom)
        return 0;
    gb_frame(x, y, w, h, resolved);
    return 1;
}
