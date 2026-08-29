#include <stdio.h>
#include <string.h>

#include "gb.h"
#include "gbvdi.h"

static unsigned char calls;
static unsigned char last_x, last_y, last_w, last_h, last_pen;
static unsigned int failures;

void gb_fill(unsigned char x, unsigned char y, unsigned char w,
             unsigned char h, unsigned char pen)
{
    calls++;
    last_x = x; last_y = y; last_w = w; last_h = h; last_pen = pen;
}

void gb_frame(unsigned char x, unsigned char y, unsigned char w,
              unsigned char h, unsigned char pen)
{
    gb_fill(x, y, w, h, pen);
}

static void check(int condition, const char *name)
{
    if (condition) printf("ok   %s\n", name);
    else { printf("FAIL %s\n", name); failures++; }
}

int main(void)
{
    gb_vdi_context_t context, original;

    memset(&context, 0xA5, sizeof(context));
    original = context;
    check(!gb_vdi_init(&context, 127u, 0, 2u, 8u) &&
              !memcmp(&context, &original, sizeof(context)),
          "base context rejects overflow atomically");
    check(gb_vdi_init(&context, 2u, 4u, 8u, 12u),
          "base context initializes");
    calls = 0;
    check(gb_vdi_fill(&context, 0u, 0u, 6u, 20u, GB_VDI_ROLE_ACCENT) &&
              calls == 1u && last_x == 2u && last_y == 4u &&
              last_w == 4u && last_h == 12u &&
              last_pen == GB_VDI_ROLE_ACCENT,
          "base fill clips and preserves the semantic role");
    check(gb_vdi_init(&context, 0u, 0u, 128u, 212u) &&
              gb_vdi_fill(&context, 126u, 210u, 4u, 4u,
                          GB_VDI_ROLE_SURFACE) &&
              last_x == 126u && last_y == 210u &&
              last_w == 2u && last_h == 2u,
          "base fill clips a target rectangle at the screen edge");
    check(gb_vdi_init(&context, 2u, 4u, 8u, 12u),
          "base context resets after the edge case");
    calls = 0;
    check(!gb_vdi_frame(&context, 1u, 4u, 3u, 8u, GB_VDI_ROLE_EDGE) &&
              calls == 0u,
          "base frame rejects a clipped outline atomically");
    check(gb_vdi_frame(&context, 3u, 5u, 3u, 8u, GB_VDI_ROLE_EDGE) &&
              calls == 1u && last_pen == GB_VDI_ROLE_EDGE,
          "base frame draws with the requested semantic role");
    if (failures) return 1;
    puts("gbvdi base-profile tests: ok");
    return 0;
}
