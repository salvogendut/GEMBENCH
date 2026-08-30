/* SYSINFO.APP - MSX2 Architecture Milestones 1-4 diagnostic (#31/#32/#35/#37).
 *
 * This development-only app exercises the public capability, owner, and opaque
 * page APIs. One cache page is deliberately left allocated: closing the window
 * must reclaim it with the owner. Reopening the app should therefore report the
 * same initial free-page count.
 */
#include "gb.h"
#ifdef GB_DEFER_MESSAGES
#include "gbdefer.h"
#endif
#ifdef GB_FILESYSTEM_CONTEXTS
#include "gbfsctx.h"
#endif

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
#define TEST_SYSINFO_V2 0x400
#define TEST_WIN_ADD 0x800
#define TEST_WIN_CLOSE 0x1000
#define TEST_APP_API 0x2000
#define TEST_FSCTX 0x4000
#define TEST_FSCTX_STALE 0x8000
#define TEST_ALL    0xFFFF

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
#ifdef GB_FILESYSTEM_CONTEXTS
volatile unsigned char fsctx_tests;
#define FSCTX_TEST_SYSINFO 0x01
#define FSCTX_TEST_FULL    0x02
#define FSCTX_TEST_OFFSET  0x04
#define FSCTX_TEST_RW      0x08
#define FSCTX_TEST_STALE   0x10
#define FSCTX_TEST_REUSE   0x20
#define FSCTX_TEST_CLEAN   0x40
#define FSCTX_TEST_ALL     0x7F
#endif
#ifdef GB_DEFER_MESSAGES
volatile unsigned char defer_tests;
static unsigned char defer_seen;
static unsigned char defer_expected;
static gb_defer_send_t defer_heartbeat;

#define DEFER_TEST_CONTEXT  0x01
#define DEFER_TEST_REGISTER 0x02
#define DEFER_TEST_FULL     0x04
#define DEFER_TEST_CANCEL   0x08
#define DEFER_TEST_FIFO     0x10
#define DEFER_TEST_OWNER    0x20
#define DEFER_TEST_BADARG   0x40
#define DEFER_TEST_LATER    0x80
#define DEFER_TEST_ALL      0xFF
#define DEFER_TEST_TYPE     0x40
#define DEFER_HEARTBEAT     0x41
#endif

static void probe_frame(void) { }
static void probe_repaint(void) { }
static void probe_event(void) { }

#ifdef GB_DEFER_MESSAGES
static void defer_handler(void)
{
    const gb_defer_message_t *message = gb_defer_current();

    if (gb_msg.type != GB_MSG_DEFER || !message) return;
    defer_tests |= DEFER_TEST_LATER;
    if (message->sender == owner && message->receiver == owner)
        defer_tests |= DEFER_TEST_OWNER;
    if (message->type == DEFER_TEST_TYPE) {
        if (message->p0 == defer_expected) {
            defer_expected++;
            defer_seen++;
        }
        if (defer_seen == GB_DEFER_QUEUE_CAPACITY)
            defer_tests |= DEFER_TEST_FIFO;
    }

    /* Keep a bounded self-message pending after the initial FIFO drains. The
     * lifecycle probe closes this app and checks that owner teardown purges it. */
    if (message->type == DEFER_HEARTBEAT || defer_seen)
        (void)gb_defer_send(&defer_heartbeat);
}

static void test_deferred_messages(void)
{
    const gb_sysinfo_t *info = gb_sysinfo();
    gb_defer_send_t message;
    unsigned char i;

    defer_tests = 0;
    defer_seen = 0;
    defer_expected = 1;
    if (!gb_defer_current() &&
        gb_defer_slots_free() == GB_DEFER_QUEUE_CAPACITY)
        defer_tests |= DEFER_TEST_CONTEXT;
    if (info->size == sizeof(gb_sysinfo_t) && info->version == 4 &&
        info->message_queue_capacity == GB_DEFER_QUEUE_CAPACITY &&
        info->message_inline_bytes == GB_DEFER_INLINE_BYTES &&
        info->message_api_version == GB_DEFER_API_VERSION &&
        (info->capabilities & GB_CAP_DEFERRED_MSG) != 0 &&
        gb_defer_register(defer_handler) == GB_DEFER_OK)
        defer_tests |= DEFER_TEST_REGISTER;

    message.receiver = owner;
    message.type = 0;
    message.p0 = message.p1 = message.p2 = 0;
    if (gb_defer_send(&message) == GB_DEFER_ERR_BADARG)
        defer_tests |= DEFER_TEST_BADARG;
    message.type = DEFER_TEST_TYPE;
    for (i = 1; i <= GB_DEFER_QUEUE_CAPACITY; i++) {
        message.p0 = i;
        if (gb_defer_send(&message) != GB_DEFER_OK) break;
    }
    if (i == GB_DEFER_QUEUE_CAPACITY + 1 && !defer_seen &&
        gb_defer_slots_free() == 0 &&
        gb_defer_send(&message) == GB_DEFER_ERR_FULL)
        defer_tests |= DEFER_TEST_FULL;
    if (gb_defer_cancel_all() == GB_DEFER_QUEUE_CAPACITY &&
        gb_defer_slots_free() == GB_DEFER_QUEUE_CAPACITY)
        defer_tests |= DEFER_TEST_CANCEL;
    for (i = 1; i <= GB_DEFER_QUEUE_CAPACITY; i++) {
        message.p0 = i;
        (void)gb_defer_send(&message);
    }

    defer_heartbeat.receiver = owner;
    defer_heartbeat.type = DEFER_HEARTBEAT;
    defer_heartbeat.p0 = defer_heartbeat.p1 = defer_heartbeat.p2 = 0;
}
#endif

#ifdef GB_FILESYSTEM_CONTEXTS
static const char fsctx_name[11] = {
    'G','B','F','S','T','E','S','T','T','M','P'
};

static void test_filesystem_contexts(void)
{
    const gb_sysinfo_t *info = gb_sysinfo();
    gb_fsctx_t context[GB_FSCTX_CAPACITY];
    gb_fsctx_t stale, replacement;
    char first[2], second[2];
    static const char payload[2] = { 'M', '4' };
    unsigned char i, allocated = 0;

    fsctx_tests = 0;
    if (info->size == sizeof(gb_sysinfo_t) && info->version == 4 &&
        info->filesystem_contexts == GB_FSCTX_CAPACITY &&
        info->filesystem_transfer_bytes == GB_FSCTX_TRANSFER_MAX &&
        info->filesystem_api_version == GB_FSCTX_API_VERSION &&
        (info->capabilities & GB_CAP_FS_CONTEXTS))
        fsctx_tests |= FSCTX_TEST_SYSINFO;

    for (i = 0; i < GB_FSCTX_CAPACITY; i++) {
        context[i] = gb_fsctx_open(0);
        if (context[i]) allocated++;
    }
    /* File Manager owns one context while it launches this diagnostic.  Three
     * free slots therefore proves the advertised four-slot global pool; a
     * leaked context from the previous launch would reduce this to two. */
    if (allocated >= GB_FSCTX_CAPACITY - 1 && !gb_fsctx_open(0) &&
        gb_fsctx_status() == GB_FSCTX_ERR_FULL)
        fsctx_tests |= FSCTX_TEST_FULL;

    if (context[0] && context[1] &&
        gb_fsctx_set_name(context[0], fsctx_name) == GB_FSCTX_OK &&
        gb_fsctx_set_name(context[1], fsctx_name) == GB_FSCTX_OK &&
        gb_fsctx_write(context[0], payload, 2) == GB_FSCTX_OK &&
        gb_fsctx_rewind(context[0]) == GB_FSCTX_OK &&
        gb_fsctx_read(context[0], first, 1) == 1 && first[0] == 'M' &&
        gb_fsctx_read(context[1], second, 1) == 1 && second[0] == 'M') {
        fsctx_tests |= FSCTX_TEST_OFFSET | FSCTX_TEST_RW;
    }

    stale = context[0];
    if (stale && gb_fsctx_close(stale) == GB_FSCTX_OK &&
        gb_fsctx_set_path(stale, "") == GB_FSCTX_ERR_STALE)
        fsctx_tests |= FSCTX_TEST_STALE;
    replacement = gb_fsctx_open(0);
    if (replacement && replacement != stale)
        fsctx_tests |= FSCTX_TEST_REUSE;
    context[0] = replacement;

    if (context[1]) {
        (void)gb_fsctx_activate(context[1]);
        (void)gb_file_delete(fsctx_name);
    }
    for (i = 0; i < GB_FSCTX_CAPACITY; i++)
        if (context[i]) (void)gb_fsctx_close(context[i]);
    if (gb_fsctx_open(0)) {
        /* Leave one live context intentionally. Owner teardown must reclaim it,
         * and the second launch's free-pool probe proves the cleanup. */
        fsctx_tests |= FSCTX_TEST_CLEAN;
    }
    if (fsctx_tests == FSCTX_TEST_ALL)
        tests |= TEST_FSCTX | TEST_FSCTX_STALE;
}
#endif

static const gb_win_t probe_window = {
    100, 36, 18, 28, probe_frame, probe_repaint, probe_event, 0
};

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

static void test_application(void)
{
    const gb_sysinfo_t *info = gb_sysinfo();
    unsigned char count = gb_app_window_count();
    unsigned char free_slots = gb_window_slots_free();
    gb_window_t primary = gb_window_current();
    gb_window_t probe;

    if (info->size == sizeof(gb_sysinfo_t) && info->version == 4 &&
        info->max_applications == 8 &&
        info->application_record_version == 1 &&
        info->max_windows_per_application == 8 &&
        (info->capabilities & (GB_CAP_APPLICATIONS | GB_CAP_MULTI_WINDOW)) ==
            (GB_CAP_APPLICATIONS | GB_CAP_MULTI_WINDOW))
        tests |= TEST_SYSINFO_V2;
    if (count == 1 && primary && gb_window_check(primary) == GB_APP_OK &&
        gb_app_publish() == GB_APP_OK && gb_window_drag() == GB_APP_OK)
        tests |= TEST_APP_API;

    gb_wm_add(&probe_window);
    probe = gb_window_current();
    if (probe && probe != primary && gb_window_check(probe) == GB_APP_OK &&
        gb_app_window_count() == 2 &&
        gb_window_slots_free() == (unsigned char)(free_slots - 1))
        tests |= TEST_WIN_ADD;
    if (probe && gb_window_close(probe) == GB_APP_OK &&
        gb_window_check(probe) == GB_APP_ERR_STALE &&
        gb_app_window_count() == 1 && gb_window_current() == primary &&
        gb_window_slots_free() == free_slots)
        tests |= TEST_WIN_CLOSE;
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
    gb_textbw(x, y, "GB_SYSINFO v4   MSX Screen");
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
    draw_result(x, (unsigned char)(y + 120), "Owner/windows/fsctx",
                TEST_FOREIGN|TEST_LEGACY|TEST_EXHAUST|TEST_SYSINFO_V2|
                TEST_WIN_ADD|TEST_WIN_CLOSE|TEST_APP_API|TEST_FSCTX|TEST_FSCTX_STALE);
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
    test_application();
#ifdef GB_FILESYSTEM_CONTEXTS
    test_filesystem_contexts();
#endif
#ifdef GB_DEFER_MESSAGES
    test_deferred_messages();
#endif
    gb_restore_parent();
}
