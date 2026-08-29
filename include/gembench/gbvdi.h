#ifndef GEMBENCH_GBVDI_H
#define GEMBENCH_GBVDI_H

/*
 * Small, app-linked drawing context for GEMBENCH resources.
 *
 * Horizontal coordinates are four-pixel VDP cells, matching the inherited
 * drawing ABI.  All 128 cells (512 Screen-7 pixels) remain addressable.  No
 * context or raster state is resident.
 */

#define GB_VDI_ROLE_CANVAS   0u
#define GB_VDI_ROLE_SURFACE  1u
#define GB_VDI_ROLE_EDGE     2u
#define GB_VDI_ROLE_ACCENT   3u

#define GB_VDI_TRANSPARENT 255u

#define GB_VDI_ALIGN_LEFT    0u
#define GB_VDI_ALIGN_CENTER  1u
#define GB_VDI_ALIGN_RIGHT   2u
#define GB_VDI_TEXT_MAX     31u

typedef struct gb_vdi_context {
    unsigned char clip_x;
    unsigned char clip_w;
    unsigned char clip_y;
    unsigned char clip_h;
    /* Reserved and left uninitialized by GB_VDI_BASE_PROFILE; that compact
     * profile maps roles 0..3 directly instead of reading this array. */
    unsigned char pens[4];
} gb_vdi_context_t;

/* Packed 4-bit cells.  Each sample represents four horizontal target pixels;
 * the high nibble is the left sample.  Values 0..3 are semantic roles mapped
 * through the context.  On MSX2, 4..15 are direct Screen-7 palette entries.
 * `transparent` may name one of those samples; 255 disables transparency. */
typedef struct gb_vdi_raster {
    const unsigned char *data;
    unsigned int size;
    unsigned char width_cells;
    unsigned char height;
    unsigned char stride;
    unsigned char transparent;
} gb_vdi_raster_t;

unsigned char gb_vdi_init(gb_vdi_context_t *context,
                          unsigned char x, unsigned char y,
                          unsigned char w, unsigned char h);
#ifndef GB_VDI_BASE_PROFILE
unsigned char gb_vdi_valid(const gb_vdi_context_t *context);
unsigned char gb_vdi_set_pens(gb_vdi_context_t *context,
                              unsigned char canvas, unsigned char surface,
                              unsigned char edge, unsigned char accent);
#endif
unsigned char gb_vdi_fill(const gb_vdi_context_t *context,
                          unsigned char x, unsigned char y,
                          unsigned char w, unsigned char h,
                          unsigned char pen);
unsigned char gb_vdi_frame(const gb_vdi_context_t *context,
                           unsigned char x, unsigned char y,
                           unsigned char w, unsigned char h,
                           unsigned char pen);

#ifndef GB_VDI_BASE_PROFILE
unsigned char gb_vdi_raster_valid(const gb_vdi_raster_t *raster);
unsigned char gb_vdi_raster(const gb_vdi_context_t *context,
                            unsigned char x, unsigned char y,
                            const gb_vdi_raster_t *raster);

unsigned char gb_vdi_text_width(const char *text, unsigned char *width);
unsigned char gb_vdi_text(const gb_vdi_context_t *context,
                          unsigned char x, unsigned char y, unsigned char w,
                          const char *text, unsigned char alignment,
                          unsigned char foreground, unsigned char background);
#endif

#endif
