/* Bounded packed-cell raster renderer for the app-linked VDI-lite context. */
#include "gb.h"
#include "gbvdi.h"

#ifdef GB_MSX2
#define GB_VDI_MAX_PEN 15u
#else
#define GB_VDI_MAX_PEN 3u
#endif

static unsigned char sample_at(const gb_vdi_raster_t *raster,
                               unsigned char x, unsigned char y)
{
    unsigned char value = raster->data[(unsigned int)y * raster->stride +
                                       (x >> 1)];
    return (unsigned char)((x & 1u) ? (value & 15u) : (value >> 4));
}

static unsigned char raster_pen(const gb_vdi_context_t *context,
                                unsigned char sample)
{
    return sample < 4u ? context->pens[sample] : sample;
}

unsigned char gb_vdi_raster_valid(const gb_vdi_raster_t *raster)
{
    unsigned int required;
#ifndef GB_MSX2
    unsigned char x, y, sample;
#endif
    if (raster == 0 || raster->data == 0 || raster->width_cells == 0 ||
        raster->width_cells > 128u || raster->height == 0 ||
        raster->stride < (unsigned char)((raster->width_cells + 1u) >> 1) ||
        (raster->transparent != GB_VDI_TRANSPARENT &&
         raster->transparent > GB_VDI_MAX_PEN))
        return 0;
    required = (unsigned int)raster->stride * raster->height;
    if (required > raster->size) return 0;
#ifndef GB_MSX2
    for (y = 0; y < raster->height; y++)
        for (x = 0; x < raster->width_cells; x++) {
            sample = sample_at(raster, x, y);
            if (sample > GB_VDI_MAX_PEN && sample != raster->transparent)
                return 0;
        }
#endif
    return 1;
}

unsigned char gb_vdi_raster(const gb_vdi_context_t *context,
                            unsigned char x, unsigned char y,
                            const gb_vdi_raster_t *raster)
{
    unsigned char right;
    unsigned char clip_right;
    unsigned char clip_bottom;
    unsigned char first_cell;
    unsigned char end_cell;
    unsigned char top;
    unsigned char bottom;
    unsigned char row, cell, sample, pen;
    unsigned char run_start = 0, run_pen = 0, run_length = 0;
    if (!gb_vdi_valid(context) || !gb_vdi_raster_valid(raster))
        return 0;
    if (x >= GB_COLS || raster->width_cells > (unsigned char)(GB_COLS - x) ||
        (unsigned int)y + raster->height > GB_LINES)
        return 0;
    right = (unsigned char)(x + raster->width_cells);
    clip_right = (unsigned char)(context->clip_x + context->clip_w);
    clip_bottom = (unsigned char)(context->clip_y + context->clip_h);
    first_cell = context->clip_x > x ?
        (unsigned char)(context->clip_x - x) : 0;
    end_cell = clip_right < right ?
        (unsigned char)(clip_right - x) : raster->width_cells;
    top = context->clip_y > y ? (unsigned char)(context->clip_y - y) : 0;
    bottom = clip_bottom < (unsigned int)y + raster->height ?
        (unsigned char)(clip_bottom - y) : raster->height;
    if (end_cell <= first_cell || bottom <= top) return 1;
    for (row = (unsigned char)top; row < (unsigned char)bottom; row++) {
        run_length = 0;
        for (cell = first_cell; cell < end_cell; cell++) {
            sample = sample_at(raster, cell, row);
            if (sample == raster->transparent) {
                if (run_length) {
                    gb_fill((unsigned char)(x + run_start),
                            (unsigned char)(y + row), run_length, 1u, run_pen);
                    run_length = 0;
                }
                continue;
            }
            pen = raster_pen(context, sample);
            if (run_length && pen == run_pen) {
                run_length++;
            } else {
                if (run_length)
                    gb_fill((unsigned char)(x + run_start),
                            (unsigned char)(y + row), run_length, 1u, run_pen);
                run_start = cell;
                run_pen = pen;
                run_length = 1;
            }
        }
        if (run_length)
            gb_fill((unsigned char)(x + run_start),
                    (unsigned char)(y + row), run_length, 1u, run_pen);
    }
    return 1;
}
