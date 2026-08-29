#include <stdio.h>
#include <string.h>

#include "gbregion.h"

#define BANK_CUR 0x134Fu
#define CLIP_X   0x1338u
#define WM_NWIN  0x1350u
#define WM_TABLE 0x1352u
#define WM_Z     0x141Au
#define WM_ESZ   25u

unsigned char gb_region_host_memory[65536];
static int failures;

static void check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

static unsigned int entry(unsigned char slot)
{
    return WM_TABLE + (unsigned int)slot * WM_ESZ;
}

static void damage(unsigned char x, unsigned char y,
                   unsigned char w, unsigned char h)
{
    gb_region_host_memory[CLIP_X] = x;
    gb_region_host_memory[CLIP_X + 1] = y;
    gb_region_host_memory[CLIP_X + 2] = w;
    gb_region_host_memory[CLIP_X + 3] = h;
}

static void window(unsigned char z, unsigned char slot, unsigned char page,
                   unsigned char x, unsigned char y,
                   unsigned char w, unsigned char h)
{
    unsigned int p = entry(slot);
    gb_region_host_memory[WM_Z + z] = slot;
    gb_region_host_memory[p] = page;
    gb_region_host_memory[p + 1] = x;
    gb_region_host_memory[p + 2] = y;
    gb_region_host_memory[p + 3] = w;
    gb_region_host_memory[p + 4] = h;
}

static void setup(unsigned char nwin, unsigned char current_page)
{
    memset(gb_region_host_memory, 0, sizeof(gb_region_host_memory));
    gb_region_host_memory[WM_NWIN] = nwin;
    gb_region_host_memory[BANK_CUR] = current_page;
}

static int rect_is(const gb_visible_rect_t *rect, unsigned char x,
                   unsigned char y, unsigned char w, unsigned char h)
{
    return rect->x == x && rect->y == y && rect->w == w && rect->h == h;
}

static void test_layout_and_empty_cases(void)
{
    gb_visible_state_t state;

    check(sizeof(gb_visible_rect_t) == 4, "visible rectangle is four bytes");
    check(sizeof(gb_visible_state_t) == 40, "iterator state is forty caller-owned bytes");

    setup(1, 2);
    window(0, 0, 2, 0, 8, 80, 204);
    damage(0, 0, 0, 212);
    check(!gb_visible_begin(&state) && !state.active,
          "empty damage produces no region");

    damage(0, 0, 10, 8);
    check(!gb_visible_begin(&state) && !state.active,
          "damage disjoint from the calling window produces no region");
}

static void test_single_cover_and_iteration(void)
{
    gb_visible_state_t state;

    setup(2, 2);
    window(0, 0, 2, 0, 8, 80, 204);
    window(1, 1, 3, 20, 40, 30, 50);
    damage(0, 8, 80, 204);
    check(gb_visible_begin(&state), "partially covered window has visible regions");
    check(state.count == 4 && !state.overflow,
          "one interior cover produces four bounded strips");
    check(rect_is(&state.regions[0], 0, 8, 80, 32), "top strip is canonical");
    check(rect_is(&state.regions[1], 0, 90, 80, 122), "bottom strip is canonical");
    check(rect_is(&state.regions[2], 0, 40, 20, 50), "left strip is canonical");
    check(rect_is(&state.regions[3], 50, 40, 30, 50), "right strip is canonical");
    check(gb_region_host_memory[CLIP_X] == 0 &&
              gb_region_host_memory[CLIP_X + 1] == 8 &&
              gb_region_host_memory[CLIP_X + 2] == 80 &&
              gb_region_host_memory[CLIP_X + 3] == 32,
          "begin installs the first visible clip");
    check(gb_visible_next(&state) && gb_region_host_memory[CLIP_X + 1] == 90,
          "next installs the second clip");
    check(gb_visible_next(&state) && gb_region_host_memory[CLIP_X + 2] == 20,
          "next installs the third clip");
    check(gb_visible_next(&state) && gb_region_host_memory[CLIP_X] == 50,
          "next installs the fourth clip");
    check(!gb_visible_next(&state) && !state.active &&
              gb_region_host_memory[CLIP_X] == 0 &&
              gb_region_host_memory[CLIP_X + 1] == 8 &&
              gb_region_host_memory[CLIP_X + 2] == 80 &&
              gb_region_host_memory[CLIP_X + 3] == 204,
          "exhaustion restores the original damage clip");
}

static void test_fully_covered_and_z_order(void)
{
    gb_visible_state_t state;

    setup(2, 2);
    window(0, 0, 2, 10, 20, 20, 30);
    window(1, 1, 3, 0, 0, 80, 212);
    damage(0, 0, 80, 212);
    check(!gb_visible_begin(&state) && state.count == 0,
          "a fully covered window does not redraw");

    setup(3, 3);
    window(0, 0, 2, 0, 0, 80, 212);       /* lower: must not subtract */
    window(1, 1, 3, 10, 20, 40, 80);      /* caller */
    window(2, 2, 4, 30, 50, 20, 20);      /* higher: does subtract */
    damage(0, 0, 80, 212);
    check(gb_visible_begin(&state) && state.count == 3,
          "only windows above the caller affect visibility");
    gb_visible_end(&state);
}

static void test_capacity_fallback(void)
{
    gb_visible_state_t state;

    setup(3, 2);
    window(0, 0, 2, 0, 8, 80, 204);
    window(1, 1, 3, 2, 44, 37, 82);
    window(2, 2, 4, 41, 44, 37, 82);
    damage(0, 0, 80, 212);
    check(gb_visible_begin(&state) && state.overflow && state.count == 1,
          "capacity exhaustion atomically selects the legacy fallback");
    check(rect_is(&state.regions[0], 0, 0, 80, 212),
          "overflow fallback is the original damage rectangle");
    check(!gb_visible_next(&state), "fallback is exactly one iteration");
}

static void test_invalid_snapshot_and_early_end(void)
{
    gb_visible_state_t state;

    setup(9, 2);
    damage(3, 4, 5, 6);
    check(gb_visible_begin(&state) && state.count == 1 && !state.overflow,
          "invalid WM count safely uses the legacy clip");
    gb_visible_end(&state);
    check(!state.active && gb_region_host_memory[CLIP_X] == 3 &&
              gb_region_host_memory[CLIP_X + 1] == 4,
          "explicit end restores the clip after an early exit");

    setup(1, 9);
    window(0, 0, 2, 0, 8, 80, 204);
    damage(7, 8, 9, 10);
    check(gb_visible_begin(&state) && state.count == 1,
          "an unknown current page safely uses the legacy clip");
    gb_visible_end(&state);

    setup(2, 2);
    window(0, 0, 2, 0, 8, 80, 204);
    window(1, 1, 2, 20, 40, 30, 50);
    damage(1, 2, 3, 4);
    check(gb_visible_begin(&state) && state.count == 1 && !state.overflow &&
              rect_is(&state.regions[0], 1, 2, 3, 4),
          "duplicate application pages safely use the legacy clip");
    gb_visible_end(&state);
}

int main(void)
{
    test_layout_and_empty_cases();
    test_single_cover_and_iteration();
    test_fully_covered_and_z_order();
    test_capacity_fallback();
    test_invalid_snapshot_and_early_end();
    if (failures) return 1;
    puts("gbregion: all tests passed");
    return 0;
}
