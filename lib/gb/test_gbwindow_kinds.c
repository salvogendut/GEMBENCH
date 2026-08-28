#include <stddef.h>
#include <stdio.h>

#define GB_MSX2 1
#include "gb.h"

static int failures;

static void check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

static void test_public_values(void)
{
    check(GB_WK_STANDARD == 0x1F, "standard kind contains the five v1 capabilities");
    check((GB_WK_CLOSE & GB_WK_MOVE) == 0, "kind capabilities use distinct bits");
    check(GB_MSG_MOVED == GB_MSG_DRAG + 1, "moved message appends to the legacy ABI");
    check(GB_MSG_SIZED == GB_MSG_MOVED + 1, "sized message follows moved");
    check(GB_MSG_MAXIMIZED == GB_MSG_SIZED + 1, "maximized message follows sized");
}

static void test_descriptor_tail(void)
{
    gb_mwin_kind_t window = {
        { 1, 2, 40, 80, 20, 40, 0, 0, 0 },
        GB_WK_STANDARD, GB_WK_ABI_V1
    };

    check(offsetof(gb_mwin_kind_t, kind) == sizeof(gb_mwin_t),
          "kind is appended after the unchanged legacy descriptor");
    check(offsetof(gb_mwin_kind_t, kind_abi) == offsetof(gb_mwin_kind_t, kind) + 1,
          "kind ABI tag immediately follows the flags");
    check(window.kind == GB_WK_STANDARD && window.kind_abi == GB_WK_ABI_V1,
          "tagged descriptor preserves its kind");
}

int main(void)
{
    test_public_values();
    test_descriptor_tail();
    if (failures) return 1;
    puts("gbwindow kinds: all tests passed");
    return 0;
}
