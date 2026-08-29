#include <stdio.h>
#include <string.h>

#include "gb.h"
#include "gbr_object.h"

static const unsigned char golden[] = {
#include "fixtures/hello-dialog.gbr.inc"
};

#define CALL_FILL  1u
#define CALL_FRAME 2u

typedef struct draw_call {
    unsigned char type, x, y, w, h, pen;
} draw_call_t;

static draw_call_t calls[16];
static unsigned char call_count;
static unsigned int failures;

static void record(unsigned char type, unsigned char x, unsigned char y,
                   unsigned char w, unsigned char h, unsigned char pen)
{
    draw_call_t *call = &calls[call_count++];
    call->type = type; call->x = x; call->y = y;
    call->w = w; call->h = h; call->pen = pen;
}

void gb_fill(unsigned char x, unsigned char y, unsigned char w,
             unsigned char h, unsigned char pen)
{
    record(CALL_FILL, x, y, w, h, pen);
}

void gb_frame(unsigned char x, unsigned char y, unsigned char w,
              unsigned char h, unsigned char pen)
{
    record(CALL_FRAME, x, y, w, h, pen);
}

void gb_textbw(unsigned char x, unsigned char y, const char *text)
{
    (void)x; (void)y; (void)text;
}

void gb_textrev(unsigned char x, unsigned char y, const char *text)
{
    (void)x; (void)y; (void)text;
}

void gb_button(unsigned char x, unsigned char y, unsigned char w,
               unsigned char h, const char *text, unsigned char flags)
{
    (void)x; (void)y; (void)w; (void)h; (void)text; (void)flags;
}

static void check(int condition, const char *name)
{
    if (condition) printf("ok   %s\n", name);
    else { printf("FAIL %s\n", name); failures++; }
}

static void put_u16(unsigned char *data, unsigned int offset,
                    unsigned int value)
{
    data[offset] = (unsigned char)value;
    data[offset + 1u] = (unsigned char)(value >> 8);
}

static void fix_checksum(unsigned char *data, unsigned int size)
{
    unsigned int index, checksum = 0;
    data[GBR_H_CHECKSUM] = 0;
    data[GBR_H_CHECKSUM + 1u] = 0;
    for (index = 0; index < size; index++)
        checksum = (unsigned int)((checksum + data[index]) & 0xffffu);
    put_u16(data, GBR_H_CHECKSUM, checksum);
}

static void make_graphics_resource(unsigned char *data)
{
    unsigned int table;
    unsigned int image;
    unsigned int icon;
    memcpy(data, golden, sizeof(golden));
    table = GBR_U16_AT(data, GBR_H_OBJECT_TABLE);
    image = table + GBR_OBJECT_RECORD_SIZE;
    icon = image + GBR_OBJECT_RECORD_SIZE;

    data[image + GBR_O_TYPE] = GBR_TYPE_IMAGE;
    put_u16(data, image + GBR_O_SPEC, 41u);
    put_u16(data, image + GBR_O_W, 8u);
    data[image + GBR_O_H] = 2u;

    data[icon + GBR_O_TYPE] = GBR_TYPE_ICON;
    put_u16(data, icon + GBR_O_SPEC, 42u);
    put_u16(data, icon + GBR_O_W, 8u);
    data[icon + GBR_O_H] = 2u;
    put_u16(data, icon + GBR_O_STATE, GBR_STATE_OUTLINED);
    fix_checksum(data, sizeof(golden));
}

int main(void)
{
    static const unsigned char image_pixels[] = { 0x01u, 0x23u };
    static const unsigned char icon_pixels[] = { 0x33u, 0x22u };
    static const gb_vdi_raster_t image_raster = {
        image_pixels, sizeof(image_pixels), 2u, 2u, 1u, GB_VDI_TRANSPARENT
    };
    static const gb_vdi_raster_t icon_raster = {
        icon_pixels, sizeof(icon_pixels), 2u, 2u, 1u, GB_VDI_TRANSPARENT
    };
    static const gb_vdi_raster_t short_raster = {
        image_pixels, 1u, 2u, 2u, 1u, GB_VDI_TRANSPARENT
    };
    static const gb_vdi_raster_t wide_raster = {
        image_pixels, sizeof(image_pixels), 3u, 2u, 2u, GB_VDI_TRANSPARENT
    };
    const gbr_graphic_binding_t valid[2] = {
        { 41u, &image_raster }, { 42u, &icon_raster }
    };
    const gbr_graphic_binding_t duplicate[2] = {
        { 41u, &image_raster }, { 41u, &icon_raster }
    };
    const gbr_graphic_binding_t unreferenced[2] = {
        { 41u, &image_raster }, { 99u, &icon_raster }
    };
    const gbr_graphic_binding_t truncated[2] = {
        { 41u, &short_raster }, { 42u, &icon_raster }
    };
    const gbr_graphic_binding_t mismatched[2] = {
        { 41u, &wide_raster }, { 42u, &icon_raster }
    };
    unsigned char data[sizeof(golden)];
    unsigned int states[3];
    gbr_resource_t resource;
    gbr_runtime_t runtime;
    gb_vdi_context_t context;

    make_graphics_resource(data);
    check(gbr_open(&resource, data, sizeof(data)) == GBR_OK &&
              gbr_runtime_init(&runtime, &resource, 0, states, 3) == GBR_RT_OK,
          "GBR ICON and IMAGE resource opens");
    call_count = 0;
    check(gbr_draw_tree(&runtime, 120u, 54u) == GBR_RT_ERR_GRAPHIC &&
              call_count == 0u,
          "missing graphics bindings fail before partial drawing");
    check(gb_vdi_init(&context, 0u, 0u, 128u, 212u) &&
              gb_vdi_set_pens(&context, 4u, 5u, 6u, 7u),
          "graphics context accepts Screen-7 extension pens");
    check(!gbr_bind_graphics(&runtime, &context, valid, 1u) &&
              runtime.graphic_bindings == 0,
          "a missing resource binding is rejected atomically");
    check(!gbr_bind_graphics(&runtime, &context, duplicate, 2u) &&
              !gbr_bind_graphics(&runtime, &context, unreferenced, 2u) &&
              !gbr_bind_graphics(&runtime, &context, truncated, 2u) &&
              !gbr_bind_graphics(&runtime, &context, mismatched, 2u) &&
              runtime.graphic_bindings == 0,
          "duplicate, unused, truncated, and mismatched bindings are rejected");
    check(gbr_bind_graphics(&runtime, &context, valid, 2u),
          "bounded graphics bindings are accepted");
    check(!gbr_bind_graphics(&runtime, &context, truncated, 2u) &&
              runtime.graphic_bindings == valid &&
              runtime.graphic_binding_count == 2u,
          "a failed replacement preserves the live binding table");

    call_count = 0;
    check(gbr_draw_tree(&runtime, 121u, 54u) == GBR_RT_ERR_GRAPHIC &&
              call_count == 0u,
          "misaligned placement fails before partial drawing");
    call_count = 0;
    check(gbr_draw_tree(&runtime, 120u, 54u) == GBR_RT_OK &&
              call_count == 9u,
          "bound IMAGE and ICON objects render with one icon state frame");
    check(calls[2].type == CALL_FILL && calls[2].x == 34u &&
              calls[2].y == 74u && calls[2].pen == 4u &&
              calls[5].pen == 7u,
          "IMAGE cells map semantic roles through the caller context");
    check(calls[6].x == 54u && calls[6].y == 118u &&
              calls[6].w == 2u && calls[6].pen == 7u &&
              calls[8].type == CALL_FRAME && calls[8].pen == 7u,
          "ICON runs coalesce and outlined state uses the accent role");

    if (failures) return 1;
    puts("GBR graphics tests: ok");
    return 0;
}
