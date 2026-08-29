/* SYSINFO.APP - MSX2 Architecture Milestone 1 diagnostic (#31).
 *
 * This development-only app exercises the public capability, owner, and opaque
 * page APIs. One cache page is deliberately left allocated: closing the window
 * must reclaim it with the owner. Reopening the app should therefore report the
 * same initial free-page count.
 */
#include "gb.h"

#define WIN_X 34
#define WIN_Y 28
#define WIN_W 60
#define WIN_H 146

#define TEST_ALLOC  0x01
#define TEST_COUNT  0x02
#define TEST_FREE   0x04
#define TEST_DOUBLE 0x08
#define TEST_STALE  0x10
#define TEST_RESTORE 0x20
#define TEST_LEAK   0x40
#define TEST_LEGACY 0x80
#define TEST_EXHAUST 0x100
#define TEST_FOREIGN 0x200
#define TEST_ALL    0x3FF

#define LEGACY_PAGE_COUNT (*(volatile unsigned char *)0x1437)
#define LEGACY_PAGE_NATIVE ((volatile unsigned char *)0x1438)
#define LEGACY_PAGE_BUSY  ((volatile unsigned char *)0x1440)
#define M1_PAGE_GENERATION ((volatile unsigned char *)0xC280)
#define M1_PAGE_PURPOSE    ((volatile unsigned char *)0xC2A0)
#define M1_PIC_PAGE       (*(volatile unsigned char *)0x130B)
#define M1_PIC_PAGE2      (*(volatile unsigned char *)0x1348)
#define M1_PIC_PAGE3      (*(volatile unsigned char *)0x1291)
#define M1_PIC_PAGE4      (*(volatile unsigned char *)0x1292)
#define M1_PIC_LENGTH     (*(volatile unsigned int *)0x14FD)

static unsigned int tests;
static unsigned char initial_free;
static unsigned char final_free;
static gb_owner_t owner;
static gb_page_t retained_page;

static char hex_digit(unsigned char value)
{
    value &= 15;
    return (char)(value < 10 ? '0' + value : 'A' + value - 10);
}

static void hex8(char *text, unsigned char value)
{
    text[0] = hex_digit((unsigned char)(value >> 4));
    text[1] = hex_digit(value);
    text[2] = 0;
}

static void hex16(char *text, unsigned int value)
{
    text[0] = hex_digit((unsigned char)(value >> 12));
    text[1] = hex_digit((unsigned char)(value >> 8));
    text[2] = hex_digit((unsigned char)(value >> 4));
    text[3] = hex_digit((unsigned char)value);
    text[4] = 0;
}

static void test_pages(void)
{
    const gb_sysinfo_t *info = gb_sysinfo();
    gb_page_t first, second, replacement;
    gb_page_t exhaust_pages[32];
    unsigned char exhaust_count;
    unsigned char legacy_index;

    owner = gb_owner_current();
    initial_free = info->free_pages;

    /* The diagnostic may inspect private metadata solely to obtain a real
     * foreign handle; ordinary clients must treat page handles as opaque. */
    first = (gb_page_t)(((unsigned int)M1_PAGE_GENERATION[0] << 8) | 1u);
    if (M1_PAGE_GENERATION[0] && gb_page_check(first) == GB_PAGE_ERR_OWNER &&
        gb_page_free(first) == GB_PAGE_ERR_OWNER &&
        gb_sysinfo()->free_pages == initial_free)
        tests |= TEST_FOREIGN;

    /* Compatibility isolation: older picture clients reserve one of the
     * eight mirrored pages directly. The general allocator must count and
     * skip it, then make it available again when the mirror is cleared. */
    for (legacy_index = 0; legacy_index < LEGACY_PAGE_COUNT; legacy_index++)
        if (!LEGACY_PAGE_BUSY[legacy_index]) break;
    if (legacy_index < LEGACY_PAGE_COUNT) {
        LEGACY_PAGE_BUSY[legacy_index] = 1;
        if (gb_sysinfo()->free_pages == (unsigned char)(initial_free - 1)) {
            first = gb_page_alloc(GB_PAGE_TEMPORARY);
            if (first && gb_sysinfo()->free_pages == (unsigned char)(initial_free - 2) &&
                gb_page_free(first) == GB_PAGE_OK) {
                M1_PIC_PAGE = LEGACY_PAGE_NATIVE[legacy_index];
                M1_PIC_PAGE2 = M1_PIC_PAGE3 = M1_PIC_PAGE4 = 0;
                gb_copybuf[0] = (char)0xA5;
                gb_pic_edit_buf = (unsigned int)gb_copybuf;
                gb_pic_edit_off = 0;
                M1_PIC_LENGTH = 1;
                if (gb_pic_edit(GB_PICEDIT_WRITE) &&
                    gb_sysinfo()->free_pages == (unsigned char)(initial_free - 1)) {
                    gb_pic_close();
                    if (!LEGACY_PAGE_BUSY[legacy_index] &&
                        gb_sysinfo()->free_pages == initial_free)
                        tests |= TEST_LEGACY;
                } else {
                    gb_pic_close();
                    LEGACY_PAGE_BUSY[legacy_index] = 0;
                }
            } else LEGACY_PAGE_BUSY[legacy_index] = 0;
        } else LEGACY_PAGE_BUSY[legacy_index] = 0;
    }

    exhaust_count = 0;
    while (exhaust_count < 32) {
        first = gb_page_alloc(GB_PAGE_TEMPORARY);
        if (!first) break;
        exhaust_pages[exhaust_count++] = first;
    }
    if (exhaust_count == initial_free && !gb_page_alloc(GB_PAGE_TEMPORARY) &&
        gb_sysinfo()->free_pages == 0) {
        while (exhaust_count) gb_page_free(exhaust_pages[--exhaust_count]);
        if (gb_sysinfo()->free_pages == initial_free) tests |= TEST_EXHAUST;
    } else while (exhaust_count) gb_page_free(exhaust_pages[--exhaust_count]);

    first = gb_page_alloc(GB_PAGE_TEMPORARY);
    second = gb_page_alloc(GB_PAGE_RESOURCE);
    if (owner && first && second && gb_page_check(first) == GB_PAGE_OK &&
        gb_page_check(second) == GB_PAGE_OK &&
        M1_PAGE_PURPOSE[(unsigned char)first - 1] == GB_PAGE_TEMPORARY &&
        M1_PAGE_PURPOSE[(unsigned char)second - 1] == GB_PAGE_RESOURCE)
        tests |= TEST_ALLOC;
    info = gb_sysinfo();
    if (initial_free >= 2 && info->free_pages == (unsigned char)(initial_free - 2))
        tests |= TEST_COUNT;
    if (first && gb_page_free(first) == GB_PAGE_OK) tests |= TEST_FREE;
    if (first && gb_page_free(first) == GB_PAGE_ERR_FREE) tests |= TEST_DOUBLE;
    replacement = gb_page_alloc(GB_PAGE_TEMPORARY);
    if (replacement && first != replacement &&
        gb_page_check(first) == GB_PAGE_ERR_STALE)
        tests |= TEST_STALE;
    if (second) gb_page_free(second);
    if (replacement) gb_page_free(replacement);
    info = gb_sysinfo();
    if (info->free_pages == initial_free) tests |= TEST_RESTORE;

    retained_page = gb_page_alloc(GB_PAGE_CACHE);
    if (retained_page) tests |= TEST_LEAK;
    final_free = gb_sysinfo()->free_pages;
}

static void draw_result(unsigned char x, unsigned char y,
                        const char *label, unsigned int mask)
{
    gb_textbw(x, y, label);
    gb_textbw((unsigned char)(x + 36), y,
              (tests & mask) == mask ? "PASS" : "FAIL");
}

static void draw(void)
{
    const gb_sysinfo_t *info = gb_sysinfo();
    unsigned char x = (unsigned char)(gb_wm_x() + 3);
    unsigned char y = (unsigned char)(gb_wm_y() + 18);
    char value[5];

    gb_fill(gb_wm_x(), (unsigned char)(gb_wm_y() + 14), WIN_W,
            (unsigned char)(WIN_H - 14), 1);
    gb_textbw(x, y, "GB_SYSINFO v1   MSX Screen");
    hex8(value, info->video_mode);
    gb_textbw((unsigned char)(x + 51), y, value);
    hex16(value, owner);
    gb_textbw(x, (unsigned char)(y + 13), "Owner handle:");
    gb_textbw((unsigned char)(x + 30), (unsigned char)(y + 13), value);
    hex8(value, info->pool_pages);
    gb_textbw(x, (unsigned char)(y + 26), "Pool pages:");
    gb_textbw((unsigned char)(x + 30), (unsigned char)(y + 26), value);
    hex8(value, initial_free);
    gb_textbw(x, (unsigned char)(y + 39), "Initial free:");
    gb_textbw((unsigned char)(x + 30), (unsigned char)(y + 39), value);
    hex8(value, final_free);
    gb_textbw((unsigned char)(x + 39), (unsigned char)(y + 39), "held:");
    gb_textbw((unsigned char)(x + 51), (unsigned char)(y + 39), value);
    draw_result(x, (unsigned char)(y + 55), "Allocate/check/count", TEST_ALLOC|TEST_COUNT);
    draw_result(x, (unsigned char)(y + 68), "Free/double-free", TEST_FREE|TEST_DOUBLE);
    draw_result(x, (unsigned char)(y + 81), "Stale generation", TEST_STALE);
    draw_result(x, (unsigned char)(y + 94), "Free count restored", TEST_RESTORE);
    draw_result(x, (unsigned char)(y + 107), "Owner-held cache", TEST_LEAK);
    draw_result(x, (unsigned char)(y + 120), "Owner/legacy/exhaust",
                TEST_FOREIGN|TEST_LEGACY|TEST_EXHAUST);
}

static void proc(void)
{
    if (gb_msg.type == GB_MSG_DRAW) draw();
    else if (gb_msg.type == GB_MSG_CLOSE) gb_wm_close();
}

static const gb_mwin_t window = {
    WIN_X, WIN_Y, WIN_W, WIN_H, 0, 0, proc, "Architecture M1", 0
};

void main(void)
{
    tests = 0;
    retained_page = 0;
    gb_wm_managed(&window);
    test_pages();
    gb_restore_parent();
}
