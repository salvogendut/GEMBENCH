#include <stdio.h>
#include <string.h>

#include "gb.h"
#include "gbvdi.h"

#define CALL_FILL  1u
#define CALL_FRAME 2u
#define CALL_TEXT  3u

typedef struct draw_call {
    unsigned char type, x, y, w, h, pen, paper;
    const char *text;
} draw_call_t;

static draw_call_t calls[32];
static unsigned char call_count;
static unsigned int failures;

static void record(unsigned char type, unsigned char x, unsigned char y,
                   unsigned char w, unsigned char h, unsigned char pen,
                   unsigned char paper, const char *value)
{
    draw_call_t *call = &calls[call_count++];
    call->type = type;
    call->x = x;
    call->y = y;
    call->w = w;
    call->h = h;
    call->pen = pen;
    call->paper = paper;
    call->text = value;
}

void gb_fill(unsigned char x, unsigned char y, unsigned char w,
             unsigned char h, unsigned char pen)
{
    record(CALL_FILL, x, y, w, h, pen, 0, 0);
}

void gb_frame(unsigned char x, unsigned char y, unsigned char w,
              unsigned char h, unsigned char pen)
{
    record(CALL_FRAME, x, y, w, h, pen, 0, 0);
}

void gb_vdi_text_raw(unsigned char x, unsigned char y,
                     unsigned char foreground, unsigned char background,
                     const char *text)
{
    record(CALL_TEXT, x, y, 0, 0, foreground, background, text);
}

static void check(int condition, const char *name)
{
    if (condition) printf("ok   %s\n", name);
    else {
        printf("FAIL %s\n", name);
        failures++;
    }
}

static void test_context_and_primitives(void)
{
    gb_vdi_context_t context;
    gb_vdi_context_t original;

    memset(&context, 0xA5, sizeof(context));
    original = context;
    check(!gb_vdi_init(&context, 127u, 0, 2u, 8u),
          "context rejects a clip beyond the target");
    check(!memcmp(&context, &original, sizeof(context)),
          "failed context initialization is atomic");
    check(gb_vdi_init(&context, 1u, 2u, 5u, 10u) &&
              gb_vdi_valid(&context),
          "context accepts a bounded VDP-cell clip");
    check(gb_vdi_set_pens(&context, 4u, 5u, 6u, 7u),
          "Screen 7 extension pens are accepted");

    call_count = 0;
    check(gb_vdi_fill(&context, 0, 0, 10u, 20u, GB_VDI_ROLE_ACCENT) &&
              call_count == 1 && calls[0].type == CALL_FILL &&
              calls[0].x == 1 && calls[0].y == 2 && calls[0].w == 5 &&
              calls[0].h == 10 && calls[0].pen == 7,
          "fill intersects the clip and maps a semantic pen");
    check(gb_vdi_fill(&context, 1u, 2u, 1u, 1u, 12u) &&
              call_count == 2 && calls[1].pen == 12,
          "native Screen 7 pen passes through the semantic map");

    call_count = 0;
    check(!gb_vdi_frame(&context, 0u, 2u, 2u, 8u, GB_VDI_ROLE_EDGE) &&
              call_count == 0,
          "frame rejects a rectangle crossing the clip atomically");
    check(gb_vdi_frame(&context, 2u, 2u, 2u, 8u, GB_VDI_ROLE_EDGE) &&
              call_count == 1 && calls[0].type == CALL_FRAME &&
              calls[0].x == 2 && calls[0].w == 2 && calls[0].pen == 6,
          "frame uses the context edge role");
}

static void test_raster(void)
{
    static const unsigned char pixels[] = { 0x01, 0x12, 0x3F, 0xF2 };
    gb_vdi_raster_t raster = { pixels, sizeof(pixels), 4, 2, 2, 15u };
    gb_vdi_raster_t short_raster = { pixels, 3, 4, 2, 2,
                                     15u };
    gb_vdi_context_t context;

    check(gb_vdi_init(&context, 0, 0, 128u, 212u) &&
              gb_vdi_set_pens(&context, 4u, 5u, 6u, 7u),
          "raster test context initializes");
    call_count = 0;
    check(!gb_vdi_raster(&context, 2u, 6u, &short_raster) && call_count == 0,
          "truncated raster fails before drawing");
    check(gb_vdi_raster_valid(&raster), "packed raster validates");
    check(gb_vdi_raster(&context, 2u, 6u, &raster) && call_count == 5,
          "raster draws coalesced opaque runs");
    check(calls[0].x == 2 && calls[0].y == 6 && calls[0].w == 1 &&
              calls[0].pen == 4 &&
              calls[1].x == 3 && calls[1].w == 2 && calls[1].pen == 5 &&
              calls[2].x == 5 && calls[2].pen == 6,
          "first raster row maps semantic roles and merges equal pens");
    check(calls[3].y == 7 && calls[3].x == 2 && calls[3].pen == 7 &&
              calls[4].x == 5 && calls[4].pen == 6,
          "transparent raster cells split the second row");
}

static void test_text(void)
{
    static const char too_long[] = "12345678901234567890123456789012";
    gb_vdi_context_t context;
    unsigned char width = 0;

    check(gb_vdi_init(&context, 0, 0, 128u, 212u) &&
              gb_vdi_set_pens(&context, 4u, 5u, 6u, 7u),
          "text test context initializes");
    check(gb_vdi_text_width("ABC", &width) && width == 5u,
          "text measurement rounds six-pixel glyphs to VDP cells");
    call_count = 0;
    check(gb_vdi_text(&context, 2u, 10u, 10u, "ABC", GB_VDI_ALIGN_RIGHT,
                      GB_VDI_ROLE_ACCENT, GB_VDI_ROLE_EDGE) &&
              call_count == 1 && calls[0].type == CALL_TEXT &&
              calls[0].x == 7 && calls[0].y == 10 && calls[0].pen == 7 &&
              calls[0].paper == 6 && !strcmp(calls[0].text, "ABC"),
          "right-aligned text uses mapped foreground and paper pens");
    call_count = 0;
    check(!gb_vdi_text(&context, 2u, 10u, 50u, too_long,
                       GB_VDI_ALIGN_LEFT, 1u, 0u) && call_count == 0,
          "overlong text fails atomically");
}

int main(void)
{
    test_context_and_primitives();
    test_raster();
    test_text();
    if (failures) return 1;
    puts("gbvdi contract tests: ok");
    return 0;
}
