/* BROWSER.APP - bounded, text-first streaming HTTP browser for GEOBENCH.
 *
 * Pages are parsed directly into fixed-width rendered lines in one borrowed
 * 16K page. No DOM is retained; a bounded raw-source copy supports offline
 * Save. CPC uses GBNET, MSX uses TCP/IP UNAPI, and PCW uses PerryNet. */
#include "gb.h"

#define URL_MAX        95
#define HOST_MAX       63
#define PATH_MAX       95
#define REQUEST_MAX   240
#define HEADER_MAX    111
/* Increase request length for explicit headers; keep parser headers compact. */
#ifdef GB_PCW
#define NETBUF_SIZE    64
#else
#define NETBUF_SIZE   128
#endif
#define TITLE_MAX      31
#define LINK_MAX       47
#define ALT_MAX        23
#define MAX_REDIRECTS   4
#define LINK_MARK       1
#define FORM_MARK       2
#define FORM_CONT_MARK  3
#define IMAGE_MARK      4
#define IMAGE_CONT_MARK 5
#define LINK_RAW_MARK   6
#define INVALID_OFFSET  0xFFFF

#define ST_IDLE       0
#define ST_INIT       1
#define ST_RESOLVE    2
#define ST_CONNECT    3
#define ST_SEND       4
#define ST_RECV       5
#define ST_FILE       6

#define URL_Y         26
#define URL_H         13
#define URL_FIELD_W   (GB_COLS - 24)
#define GO_X          (GB_COLS - 21)
#define GO_W           8
#define BACK_X        (GB_COLS - 12)
#define BACK_W        10
#define FORM_BUTTON_W 14
#define FORM_BUTTON_X (GB_COLS - FORM_BUTTON_W)
#define FORM_FIELD_W  (FORM_BUTTON_X - TEXT_X - 1)
#define FORM_H         16
#define STATUS_Y      42
#define TITLE_Y       51
#define CONTENT_Y     62
#define TEXT_X         5
#define SCROLL_X       1
#define SCROLL_W       3
#ifdef GB_PCW
#define TEXT_COLS     55
#else
#define TEXT_COLS     48
#endif
#define LINE_SIZE     (TEXT_COLS + 1)
#define VIEW_ROWS     ((GB_LINES - CONTENT_Y - 2) / 8)
#ifdef GB_PCW
#define CACHE_LINES   182
#else
#define CACHE_LINES   208
#endif
#define FALLBACK_LINES 7
#define CACHE_DATA_END 0x27D0
#define IMAGE_SLOT_OFS 0x30F2
#define IMAGE_SLOT_SIZE 3854
#define IMAGE_ROWS      12

/* The cooperative app-page pool is always mapped below #4000. Browser claims
 * one otherwise-free page for rendered lines and returns it through the normal
 * picture-bank close service. GB_PICEDIT moves short records while that page is
 * mapped, so no pointer into the Browser's own page crosses a bank switch. */
#define APP_NPAGES    (*(volatile unsigned char *)0x1437)
#define APP_PAGES     ((volatile unsigned char *)0x1438)
#define APP_BUSY      ((volatile unsigned char *)0x1440)
#define PIC_PAGE_K    (*(volatile unsigned char *)0x130B)
#define PIC_PAGE2_K   (*(volatile unsigned char *)0x1348)
#define FS_SAVE_LEN_K (*(volatile unsigned int  *)0x14FD)
#define FS_LOAD_OFS   ((volatile unsigned char *)0x144C)
#define FS_XFLAGS     (*(volatile unsigned char *)0x144F)

/* Browser/GBUI/GBWEB transfer area. The PCW transport already uses the bottom
 * of gb_copybuf; these blocks sit above it and remain visible while a paged
 * helper temporarily replaces the Browser app bank. */
#define BUI_LOCAL_BUF ((unsigned char *)0x2900)
#define BUI_URL_BASE   ((char *)0x2900)
#define BUI_URL_LINK   ((char *)0x2960)
#define BUI_URL_RESULT ((char *)0x29C0)
#define BUI_STAGE     ((char *)0x2B00)
/* Divides a 16K page exactly, so a flush never straddles borrowed banks. */
#define BUI_STAGE_CAP 0x0800
#define BUI_PAGES     ((volatile unsigned char *)0x3900)
#define BUI_NPAGES    (*(volatile unsigned char *)0x3904)
#define BUI_TAIL      (*(volatile unsigned int  *)0x3905)
#define BUI_STAGE_LEN (*(volatile unsigned int  *)0x3907)
#define BUI_FLAGS     (*(volatile unsigned char *)0x3909)
#define BUI_LOCAL_LEN (*(volatile unsigned int  *)0x390A)
#define BUI_LOCAL_POS (*(volatile unsigned int  *)0x390C)
#define BUI_LOCAL_OFS ((volatile unsigned char *)0x390E)
#define BUI_CTRL      (*(volatile unsigned char *)0x3911)
#define BUI_WANT_MENU (*(volatile unsigned char *)0x3912)
#define BUI_SAVE_RESULT (*(volatile unsigned char *)0x3913)
#define BUI_MODNAME   ((char *)0x3914)
#define BUI_PROXY     ((char *)0x3920)
#define BUI_PROXY_HOST ((char *)0x3980)
#define BUI_PROXY_PORT (*(volatile unsigned int *)0x39C0)
#define BUI_FORM_VALUE  ((char *)0x3A18)
#define BUI_FORM_URL    ((char *)0x3A48)
#define BUI_FORM_ROW    (*(volatile unsigned char *)0x3AA9)
#define BUI_REQ_PORT    (*(volatile unsigned int  *)0x3AAA)
#define BUI_REQ_ERROR   (*(volatile unsigned char *)0x3AAC)
#define BUI_RESOURCE_TAIL (*(volatile unsigned int *)0x3AAD)
#define BUI_LINK_OFFSET (*(volatile unsigned int  *)0x3AAF)
#define BUI_LINK_ACTIVE (*(volatile unsigned char *)0x3AB1)
#define BUI_LINK_IMAGE  (*(volatile unsigned char *)0x3AB2)
#define BUI_IMAGE_URL   (*(volatile unsigned int  *)0x3AB3)
#define BUI_IMAGE_REL   (*(volatile unsigned char *)0x3AB5)
#define BUI_IMAGE_LEN   (*(volatile unsigned int  *)0x3AB6)
#define BUI_IMAGE_WB    (*(volatile unsigned char *)0x3AB9)
#define BUI_IMAGE_H     (*(volatile unsigned char *)0x3ABA)
#define BUI_IMAGE_READY (*(volatile unsigned char *)0x3ABB)
#define BUI_IMAGE_REQUEST (*(volatile unsigned char *)0x3ABC)
#define BUI_IMAGE_FAILED (*(volatile unsigned int *)0x3ABD)
#define BUI_CACHE_PAGE  (*(volatile unsigned char *)0x3ABF)
#define BUI_HIST_COUNT  (*(volatile unsigned char *)0x3AC0)
#define BUI_VIEW_TOP    (*(volatile unsigned char *)0x3AC1)
#define BUI_LINE_SIZE   (*(volatile unsigned char *)0x3AC2)
#define BUI_VIEW_ROWS   (*(volatile unsigned char *)0x3AC3)
#define BUI_TEXT_X      (*(volatile unsigned char *)0x3AC4)
#define BUI_CONTENT_Y   (*(volatile unsigned char *)0x3AC5)
#define BUI_SCREEN_COLS (*(volatile unsigned char *)0x3AC6)
#define BUI_IMAGE_SCAN  (*(volatile unsigned char *)0x3AC7)
#define BUI_REQ_TEXT     ((char *)0x3AC8)
#define BUI_FORM_VALUE_MAX 47
#define BUI_SOURCE_FULL 0x01
#define BUI_CAPTURE_ALL 0x01
#define BUI_SAVE_PENDING 0x02
#define BUI_LOCAL_PAGE 0x04
#define BUI_PROXY_ON 0x08
#define BUI_SAVE_WORKER 0x10
#define RECEIVE_PAUSE_FLOW 0x01
#define RECEIVE_PAUSE_FLUSH 0x02

#define UI_OP         (*(volatile unsigned char *)0x1700)
#define UI_N          (*(volatile unsigned char *)0x1703)
#define UI_RES        (*(volatile unsigned char *)0x1704)
#define UI_MODAL      (*(volatile unsigned char *)0x1705)
#define UI_NAME       ((char *)0x1708)
#define BUI_ACT_LOAD   1
#define BUI_ACT_SAVE   2
#define BUI_ACT_PROXY  3
#define BUI_ACT_SAVETO 4
extern unsigned char gb_ui(void);

static unsigned char web_call(void) __naked
{
__asm
    ld a,#0x80
    call #0x80AE
    xor a
    ld (#0x1705),a
    ld a,c
    ret
__endasm;
}

/* GBNET transfers at most 1024 bytes through #2200. The common transient area
 * above it is also free on PCW, whose direct PerryNet frame remains at #2200. */
#define request     ((char *)0x3300)          /* 241 bytes */
#define header_line ((char *)0x3400)          /* 112 bytes */
#define netbuf      ((unsigned char *)0x3470) /* 128 bytes */
#define link_url    ((char *)0x34F0)          /* 48 bytes */
#define alt_text    ((char *)0x3520)          /* 24 bytes */
#define entity_text ((char *)0x3538)          /* 10 bytes */
#define url         ((char *)0x3542)          /* 96 bytes */
#define host        ((char *)0x35A2)          /* 64 bytes */
#define path        ((char *)0x35E2)          /* 96 bytes */
#ifdef GB_PCW
#define BROWSER_PCW_FRAME_BUFFER ((unsigned char *)gb_copybuf)
#endif
#define title       ((char *)0x3642) /* 32 bytes */
#define back_url    ((char *)0x3662) /* 96 bytes */
#define pending     ((char *)0x36C2) /* 49 bytes */
#define fallback    ((char *)0x3700) /* 343 bytes, ends at #3856 */
/* Drawing runs after each receive burst, so the consumed network buffer can
 * double as the short URL viewport and borrowed-bank line staging area without
 * increasing app RAM. */
#define url_view ((char *)netbuf)
#define line_buf ((char *)netbuf)
#define cache_page BUI_CACHE_PAGE
#define hist_count BUI_HIST_COUNT
#define view_top BUI_VIEW_TOP

static const char *status_text;
static unsigned int idle_frames;
static unsigned long bytes_done;
static unsigned char state, editing, url_len, title_len;
static unsigned char header_done, line_overflow, socket_open;
static unsigned char transport_rx_status, redirect_count;
static unsigned char hist_start, pending_len;
static unsigned char dirty, caret_tick, caret_on, redraw_div;
static unsigned char have_page, have_back, edit_changed;
static unsigned char cache_full;
static unsigned char rx_len, rx_pos, receive_paused, line_budget;

#ifdef GB_PCW
static unsigned char read_down_key(void) __naked
{
__asm
    ld a,#0x83
    out (0xF3),a
    ld a,(0xFFFA)
    and #0x40
    ret
__endasm;
}
#elif defined(GB_MSX2)
static unsigned char read_down_key(void) __naked
{
__asm
    xor a
    ret
__endasm;
}
#else
static unsigned char read_down_key(void) __naked
{
__asm
    ld a,#2
    call #0xBB1E
    jr z,1$
    ld a,#1
    ret
1$:
    xor a
    ret
__endasm;
}
#endif

/* caret_tick is idle while no field is being edited, so it also provides the
 * Browser-local initial delay and held-key repeat without growing BSS. */
static unsigned char down_key_event(void)
{
    if (!read_down_key()) {
        caret_tick = 0;
        return 0;
    }
    if (!caret_tick) {
        caret_tick = 12;
        return 1;
    }
    if (!--caret_tick) {
        caret_tick = 4;
        return 1;
    }
    return 0;
}

#ifndef GB_PCW
static const unsigned char netcfg[22] = {
    192,168,99,50, 255,255,255,0, 192,168,99,1, 8,8,8,8,
    0xDE,0xAD,0xBE,0xEF,0x00,0xFF
};
#endif

static const unsigned char browser_menu_def[] = {
    2,
    10, 'F','i','l','e',0,0,0,0,
    17, 'S','e','t','t','i','n','g','s'
};

static unsigned char lower(unsigned char c)
{
    if (c >= 'A' && c <= 'Z') c = (unsigned char)(c + ('a' - 'A'));
    return c;
}

static unsigned char ci_prefix(const char *s, const char *p)
{
    while (*p) {
        if (!*s || lower((unsigned char)*s++) != lower((unsigned char)*p++)) return 0;
    }
    return 1;
}

static unsigned int text_len(const char *s)
{
    unsigned int n = 0;
    while (s[n]) n++;
    return n;
}

static unsigned char current_url_len(void)
{
    unsigned char n = 0;
    while (n < URL_MAX && url[n]) n++;
    url[n] = 0;
    return n;
}

static void copy_url(char *dst, const char *src)
{
    unsigned char n = 0;
    while (src[n] && n < URL_MAX) { dst[n] = src[n]; n++; }
    dst[n] = 0;
}

static void set_status(const char *s)
{
    status_text = s;
    dirty = 1;
}

static void reset_resources(void)
{
    BUI_RESOURCE_TAIL = CACHE_DATA_END;
    BUI_LINK_OFFSET = INVALID_OFFSET;
    BUI_LINK_ACTIVE = BUI_LINK_IMAGE = 0;
    BUI_IMAGE_URL = BUI_IMAGE_FAILED = INVALID_OFFSET;
    BUI_IMAGE_LEN = 0;
    BUI_IMAGE_WB = BUI_IMAGE_H = 0;
    BUI_IMAGE_READY = BUI_IMAGE_REQUEST = 0;
    BUI_IMAGE_SCAN = 0;
}

static unsigned char web_op(unsigned char op)
{
    UI_OP = op;
    UI_RES = 0;
    return web_call();
}

static unsigned char image_op(unsigned char op)
{
    unsigned char result;
    BUI_MODNAME[2] = 'I'; BUI_MODNAME[3] = 'M'; BUI_MODNAME[4] = 'G';
    UI_OP = op; UI_RES = 0;
    result = web_call();
    BUI_MODNAME[2] = 'W'; BUI_MODNAME[3] = 'E'; BUI_MODNAME[4] = 'B';
    return result;
}

static void source_reset(void)
{
    (void)web_op(7);
    BUI_LOCAL_LEN = BUI_LOCAL_POS = 0;
    BUI_LOCAL_OFS[0] = BUI_LOCAL_OFS[1] = BUI_LOCAL_OFS[2] = 0;
}

static void source_byte(unsigned char c)
{
    if (BUI_FLAGS & BUI_SOURCE_FULL) return;
    if (BUI_STAGE_LEN >= BUI_STAGE_CAP) {
        receive_paused |= RECEIVE_PAUSE_FLUSH;
        return;
    }
    BUI_STAGE[BUI_STAGE_LEN++] = (char)c;
    if (BUI_STAGE_LEN == BUI_STAGE_CAP) receive_paused |= RECEIVE_PAUSE_FLUSH;
}

static unsigned char ring_index(unsigned char start, unsigned char rel)
{
    unsigned char n = (unsigned char)(start + rel);
    if (n >= FALLBACK_LINES) n = (unsigned char)(n - FALLBACK_LINES);
    return n;
}

static unsigned char alloc_cache_page(void)
{
    unsigned char i;
    for (i = 0; i < APP_NPAGES; i++) {
        if (!APP_BUSY[i]) {
            APP_BUSY[i] = 1;
            return APP_PAGES[i];
        }
    }
    return 0;
}

static void source_flush(void)
{
    if (BUI_STAGE_LEN) (void)web_op(6);
}

static unsigned int store_resource(const char *text)
{
    unsigned char n = 0;
    unsigned int off = BUI_RESOURCE_TAIL;
    if (!cache_page) return INVALID_OFFSET;
    while (text[n] && n < LINK_MAX) n++;
    if (!n || off + n + 1 > IMAGE_SLOT_OFS) return INVALID_OFFSET;
    PIC_PAGE_K = cache_page;
    PIC_PAGE2_K = 0;
    gb_pic_edit_buf = (unsigned int)text;
    gb_pic_edit_off = off;
    FS_SAVE_LEN_K = (unsigned int)(n + 1);
    if (!gb_pic_edit(GB_PICEDIT_WRITE)) return INVALID_OFFSET;
    BUI_RESOURCE_TAIL = (unsigned int)(off + n + 1);
    return off;
}

static unsigned char load_resource(unsigned int off)
{
    if (!cache_page || off < CACHE_DATA_END || off >= BUI_RESOURCE_TAIL)
        return 0;
    PIC_PAGE_K = cache_page;
    PIC_PAGE2_K = 0;
    gb_pic_edit_buf = (unsigned int)link_url;
    gb_pic_edit_off = off;
    FS_SAVE_LEN_K = LINK_MAX + 1;
    if (!gb_pic_edit(GB_PICEDIT_CHUNK)) return 0;
    link_url[LINK_MAX] = 0;
    return 1;
}

static char *history_line(unsigned char rel)
{
    unsigned char i;
    if (!cache_page)
        return &fallback[(unsigned int)ring_index(hist_start, rel) * LINE_SIZE];
    PIC_PAGE_K = cache_page;
    PIC_PAGE2_K = 0;
    gb_pic_edit_buf = (unsigned int)gb_copybuf;
    gb_pic_edit_off = (unsigned int)rel * LINE_SIZE;
    FS_SAVE_LEN_K = LINE_SIZE;
    if (!gb_pic_edit(GB_PICEDIT_CHUNK)) { line_buf[0] = 0; return line_buf; }
    for (i = 0; i < LINE_SIZE; i++) line_buf[i] = gb_copybuf[i];
    return line_buf;
}

static void scroll_bottom(void)
{
    view_top = hist_count > VIEW_ROWS ? (unsigned char)(hist_count - VIEW_ROWS) : 0;
}

static void add_line(void)
{
    unsigned char slot, i;
    if (cache_page) {
        if (hist_count < CACHE_LINES) {
            for (i = 0; i < pending_len; i++) gb_copybuf[i] = pending[i];
            gb_copybuf[pending_len] = 0;
            PIC_PAGE_K = cache_page;
            PIC_PAGE2_K = 0;
            gb_pic_edit_buf = (unsigned int)gb_copybuf;
            gb_pic_edit_off = (unsigned int)hist_count * LINE_SIZE;
            FS_SAVE_LEN_K = (unsigned int)(pending_len + 1);
            if (gb_pic_edit(GB_PICEDIT_WRITE)) hist_count++;
            else cache_full = 1;
        } else cache_full = 1;
    } else {
        if (hist_count < FALLBACK_LINES) slot = ring_index(hist_start, hist_count++);
        else {
            slot = hist_start;
            hist_start = ring_index(hist_start, 1);
            if (view_top) view_top--;
        }
        for (i = 0; i < pending_len; i++)
            fallback[(unsigned int)slot * LINE_SIZE + i] = pending[i];
        fallback[(unsigned int)slot * LINE_SIZE + pending_len] = 0;
        scroll_bottom();
    }
    pending_len = 0;
}

static void output_char(unsigned char c)
{
    if (c < 32 || c >= 127) c = '?';
    if (BUI_LINK_ACTIVE) {
        if (pending_len < TEXT_COLS - 3) pending[pending_len++] = (char)c;
        return;
    }
    pending[pending_len++] = (char)c;
    if (pending_len >= TEXT_COLS) add_line();
}

static void output_break(unsigned char kind)
{
    if (BUI_LINK_ACTIVE) {
        if (pending_len && pending[pending_len - 1] != ' ' &&
            pending_len < TEXT_COLS - 3) pending[pending_len++] = ' ';
        return;
    }
    if (pending_len) add_line();
    else if (kind == 2 && hist_count && history_line((unsigned char)(hist_count - 1))[0]) add_line();
}

static void output_text(const char *s)
{
    while (*s) output_char((unsigned char)*s++);
}

static void title_char(unsigned char c)
{
    if (title_len < TITLE_MAX && c >= 32 && c < 127) {
        title[title_len++] = (char)c;
        title[title_len] = 0;
    }
}

static void emit_link_line(void)
{
    unsigned char i;
    if (!pending_len && BUI_LINK_IMAGE) return;
    if (!pending_len) {
        pending[0] = 'L'; pending[1] = 'i'; pending[2] = 'n'; pending[3] = 'k';
        pending_len = 4;
    }
    if (BUI_LINK_OFFSET != INVALID_OFFSET) {
        i = pending_len;
        while (i) { i--; pending[i + 3] = pending[i]; }
        pending[0] = LINK_MARK;
        pending[1] = (char)BUI_LINK_OFFSET;
        pending[2] = (char)(BUI_LINK_OFFSET >> 8);
        pending_len = (unsigned char)(pending_len + 3);
    }
    add_line();
}

static void link_begin(const char *href)
{
    output_break(1);
    if (!cache_page) {
        pending[0] = LINK_RAW_MARK;
        pending_len = 1;
        output_text(href);
        if (pending_len) add_line();
        return;
    }
    BUI_LINK_OFFSET = store_resource(href);
    BUI_LINK_ACTIVE = 1;
    BUI_LINK_IMAGE = 0;
    pending_len = 0;
}

static void link_end(void)
{
    if (BUI_LINK_ACTIVE) {
        emit_link_line();
        BUI_LINK_ACTIVE = 0;
        BUI_LINK_IMAGE = 0;
    } else output_break(1);
}

static void image_tag(const char *src, const char *alt)
{
    unsigned int image_off;
    unsigned char i, parent;
    if (!*src) { output_text(alt); return; }
    if (BUI_LINK_ACTIVE) {
        if (!pending_len) output_text(*alt ? alt : "Image");
        emit_link_line();
        BUI_LINK_IMAGE = 1;
    } else output_break(1);
    image_off = store_resource(src);
    if (image_off == INVALID_OFFSET) { output_text(alt); return; }
    parent = hist_count;
    pending[0] = IMAGE_MARK;
    pending[1] = (char)image_off;
    pending[2] = (char)(image_off >> 8);
    i = 0;
    while (alt[i] && i < LINE_SIZE - 4) { pending[i + 3] = alt[i]; i++; }
    pending_len = (unsigned char)(i + 3);
    add_line();
    for (i = 1; i < IMAGE_ROWS && !cache_full; i++) {
        pending[0] = IMAGE_CONT_MARK;
        pending[1] = (char)parent;
        pending_len = 2;
        add_line();
    }
}

static void form_tag(unsigned char kind, unsigned char attr_start)
{
    UI_N = kind;
    *(const char **)UI_NAME = header_line + attr_start;
    if (web_op(14)) {
        output_break(1);
        pending[0] = FORM_MARK;
        pending_len = 1;
        add_line();
        pending[0] = FORM_CONT_MARK;
        pending_len = 1;
        add_line();
    }
}

#define GB_HTML_TAG_MAX          HEADER_MAX
#define GB_HTML_URL_MAX          LINK_MAX
#define GB_HTML_ALT_MAX          ALT_MAX
#define GB_HTML_EXTERNAL_STORAGE 1
#define GB_HTML_TAG_BUFFER       header_line
#define GB_HTML_URL_BUFFER       link_url
#define GB_HTML_ALT_BUFFER       alt_text
#define GB_HTML_ENTITY_BUFFER    entity_text
#define GB_HTML_RAW_ATTRS        1
#define GB_HTML_NO_FORM_CLOSE    1
#define GB_HTML_NAMED_ENTITIES_ONLY 1
#define GB_HTML_EMIT_TEXT(c)     output_char(c)
#define GB_HTML_EMIT_TITLE(c)    title_char(c)
#define GB_HTML_EMIT_BREAK(k)    output_break(k)
#define GB_HTML_LINK_BEGIN(u)    link_begin(u)
#define GB_HTML_LINK_END()       link_end()
#define GB_HTML_IMAGE(s, a)      image_tag(s, a)
#define GB_HTML_FORM_TAG(k, a)   form_tag(k, a)
#include "gbhtml.h"

static void finish_page(void);
static void fail_page(const char *s);

static unsigned char body_write(const unsigned char *buf, unsigned int len)
{
    unsigned int i;
    if (BUI_IMAGE_REQUEST) {
        for (i = 0; i < len; i++) {
            BUI_STAGE[BUI_STAGE_LEN++] = (char)buf[i];
            if (BUI_STAGE_LEN == BUI_STAGE_CAP && !image_op(20)) {
                fail_page("Image too large");
                return 0;
            }
        }
        bytes_done += len;
        return 1;
    }
    for (i = 0; i < len; i++) source_byte(buf[i]);
    gb_html_feed(buf, len);
    bytes_done += len;
    return 1;
}

#define GB_HTTP_HEADER_LINE       header_line
#define GB_HTTP_LOCATION          request
#define GB_HTTP_LOCATION_MAX      URL_MAX
#define GB_HTTP_TRAILER_MAX       HEADER_MAX
#define GB_HTTP_INVALID_RESPONSE() fail_page("Bad HTTP response")
#define GB_HTTP_INVALID_STATUS()   fail_page("Bad HTTP status")
#define GB_HTTP_BODY_WRITE(b, n)   body_write((b), (n))
#define GB_HTTP_FINISH()           finish_page()
#define GB_HTTP_BAD_CHUNK()        fail_page("Bad chunk")
#define GB_HTTP_BAD_CHUNK_SIZE()   fail_page("Bad chunk size")
#define GB_HTTP_CHUNK_TOO_LARGE()  fail_page("Chunk too large")
#include "gbhttp.h"

#define BROWSER_TR_HOST ((BUI_CTRL & BUI_PROXY_ON) ? BUI_PROXY_HOST : host)
#define BROWSER_TR_PORT ((BUI_CTRL & BUI_PROXY_ON) ? BUI_PROXY_PORT : BUI_REQ_PORT)
#include "transport.h"

static unsigned char prepare_request(unsigned char linked)
{
    UI_N = linked;
    if (web_op(19)) return 1;
    set_status(BUI_REQ_TEXT);
    return 0;
}

static unsigned char resolve_redirect(const char *location)
{
    copy_url(BUI_URL_BASE, url);
    copy_url(BUI_URL_LINK, location);
    if (!web_op(18)) return 0;
    copy_url(url, BUI_URL_RESULT);
    url_len = current_url_len();
    return prepare_request(0);
}

static void reset_response(void)
{
    gb_http_response_init();
    bytes_done = 0; idle_frames = 0;
    rx_len = rx_pos = 0;
    header_done = line_overflow = socket_open = 0;
}

static void finish_page(void)
{
    if (socket_open) tr_close();
    state = ST_IDLE;
    receive_paused = 0;
    if (BUI_IMAGE_REQUEST) {
        BUI_IMAGE_REQUEST = 0;
        if (image_op(21)) {
            BUI_IMAGE_READY = 1;
            BUI_IMAGE_FAILED = INVALID_OFFSET;
            set_status("Page complete");
        } else {
            BUI_IMAGE_READY = 0;
            BUI_IMAGE_FAILED = BUI_IMAGE_URL;
            BUI_STAGE_LEN = 0;
            BUI_IMAGE_SCAN = 1;
            set_status("Image unavailable");
        }
        return;
    }
    gb_html_end();
    if (pending_len) add_line();
    if (view_top && view_top + VIEW_ROWS > hist_count) view_top--;
    have_page = 1;
    BUI_IMAGE_SCAN = 1;
    if (BUI_FLAGS & BUI_SOURCE_FULL) set_status("Source cache full");
    else if (cache_full) set_status("Page cache full");
    else if (!cache_page && hist_start) set_status("Last lines only");
    else set_status("Page complete");
}

static void fail_page(const char *s)
{
    if (socket_open) tr_close();
    state = ST_IDLE;
    receive_paused = 0;
    if (BUI_IMAGE_REQUEST) {
        BUI_IMAGE_REQUEST = BUI_IMAGE_READY = 0;
        BUI_IMAGE_FAILED = BUI_IMAGE_URL;
        BUI_STAGE_LEN = 0;
        BUI_IMAGE_SCAN = 1;
    }
    set_status(s);
}

static void headers_complete(void)
{
    unsigned char redirect = (unsigned char)(gb_http_status_code == 301 ||
        gb_http_status_code == 302 || gb_http_status_code == 303 ||
        gb_http_status_code == 307 || gb_http_status_code == 308);
    header_done = 1;
    if (redirect) {
        const char *redir_err = 0;
        const char *prev_status = status_text;
        if (BUI_IMAGE_REQUEST) { fail_page("Image redirect"); return; }
        if (gb_http_have_location != 1) {
            fail_page(gb_http_have_location == 2 ? "Redirect too long" :
                                                  "Redirect missing");
            return;
        }
        if (redirect_count >= MAX_REDIRECTS) { fail_page("Redirect limit"); return; }
        tr_close();
        hist_start = hist_count = view_top = pending_len = cache_full = 0;
        reset_resources();
        have_page = 0;
        receive_paused = 0;
        line_budget = cache_page ? 0 : FALLBACK_LINES;
        title_len = 0; title[0] = 0;
        if (!resolve_redirect(request)) redir_err = (status_text != prev_status ? status_text : "Bad redirect");
        if (redir_err) {
            fail_page(redir_err);
            return;
        }
        redirect_count++;
        reset_response();
        state = ST_INIT;
        set_status("Redirecting...");
        return;
    }
    if (gb_http_status_code < 200 || gb_http_status_code >= 300) {
        fail_page("HTTP failed"); return;
    }
    if (gb_http_chunked) {
        gb_http_have_length = 0;
        gb_http_chunk_state = 0;
        gb_http_chunk_left = 0;
        gb_http_chunk_have_digit = 0;
    }
    set_status(BUI_IMAGE_REQUEST ? "Receiving image..." : "Receiving page...");
    if (BUI_IMAGE_REQUEST && gb_http_have_length &&
        gb_http_content_length > IMAGE_SLOT_SIZE) {
        fail_page("Image too large"); return;
    }
    if (gb_http_have_length && !gb_http_content_length) finish_page();
}

static void process_rx(void)
{
    unsigned char c;
    while (rx_pos < rx_len && state == ST_RECV && !receive_paused) {
        if (!header_done) {
            c = netbuf[rx_pos++];
            if (c == '\r') continue;
            if (c == '\n') {
                if (line_overflow) {
                    line_overflow = 0;
                    gb_http_line_len = 0;
                    continue;
                }
                if (!gb_http_line_len) { headers_complete(); continue; }
                gb_http_process_header_line();
                gb_http_line_len = 0;
                if (state != ST_RECV) return;
            } else if (gb_http_line_len < HEADER_MAX)
                header_line[gb_http_line_len++] = (char)c;
            else line_overflow = 1;
            continue;
        }
        if (gb_http_chunked) {
            if (!gb_http_chunk_byte(netbuf[rx_pos++])) return;
            continue;
        }
        c = netbuf[rx_pos++];
        if (!body_write(&c, 1)) return;
        if (gb_http_have_length && bytes_done >= gb_http_content_length) {
            finish_page(); return;
        }
    }
    if (rx_pos >= rx_len) rx_pos = rx_len = 0;
}

static void start_page(void)
{
    if (!url[0]) { set_status("Enter URL"); return; }
    if (!prepare_request(0)) return;
    source_reset();
    BUI_CTRL &= BUI_PROXY_ON;
    hist_start = hist_count = view_top = pending_len = cache_full = 0;
    reset_resources();
    receive_paused = 0;
    line_budget = cache_page ? 0 : FALLBACK_LINES;
    title_len = 0; title[0] = 0;
    gb_html_reset();
    reset_response();
    redirect_count = 0;
    editing = caret_on = edit_changed = have_page = 0;
    state = ST_INIT;
    set_status("Network init...");
}

static void go_back(void)
{
    if (state != ST_IDLE || !have_back) return;
    copy_url(url, back_url);
    url_len = current_url_len();
    have_back = 0;
    start_page();
}

static void open_link(const char *href)
{
    if (state != ST_IDLE) return;
    if (ci_prefix(href, "https://")) { set_status("HTTPS unsupported"); return; }
    if ((BUI_CTRL & BUI_LOCAL_PAGE) && !ci_prefix(href, "http://")) {
        set_status("No local link"); return;
    }
    copy_url(back_url, url);
    if (!resolve_redirect(href)) {
        copy_url(url, back_url);
        url_len = current_url_len();
        set_status("Invalid link URL");
        return;
    }
    have_back = 1;
    start_page();
}

static void submit_form(void)
{
    if (state != ST_IDLE) return;
    editing = caret_on = 0;
    if (web_op(15)) open_link(BUI_FORM_URL);
}

static void start_local(void)
{
    unsigned char i, n = 0;
    if (have_page) { copy_url(back_url, url); have_back = 1; }
    source_reset();
    BUI_CTRL = BUI_LOCAL_PAGE;
    gb_set_name(UI_NAME);
    for (i = 0; i < 8 && UI_NAME[i] != ' '; i++) url[n++] = UI_NAME[i];
    if (UI_NAME[8] != ' ') {
        url[n++] = '.';
        for (i = 8; i < 11 && UI_NAME[i] != ' '; i++) url[n++] = UI_NAME[i];
    }
    url[n] = 0; url_len = n;
    hist_start = hist_count = view_top = pending_len = cache_full = 0;
    reset_resources();
    receive_paused = 0;
    line_budget = cache_page ? 0 : FALLBACK_LINES;
    title_len = 0; title[0] = 0;
    bytes_done = 0;
    gb_html_reset();
    editing = caret_on = edit_changed = have_page = 0;
    state = ST_FILE;
    set_status("Loading .HTM...");
}

static void local_tick(void)
{
    unsigned char c;
    if (state != ST_FILE || receive_paused) return;
    while (BUI_LOCAL_POS < BUI_LOCAL_LEN && !receive_paused) {
        c = BUI_LOCAL_BUF[BUI_LOCAL_POS++];
        body_write(&c, 1);
    }
    if (receive_paused || BUI_LOCAL_POS < BUI_LOCAL_LEN) return;
    if (!web_op(10)) finish_page();
}

static void start_visible_image(void)
{
    if (!BUI_IMAGE_SCAN || !cache_page || !have_page || state != ST_IDLE) return;
    BUI_IMAGE_SCAN = 0;
    source_flush();
    if (!image_op(22)) return;
    if (!prepare_request(1)) {
        BUI_IMAGE_FAILED = BUI_IMAGE_URL;
        set_status("Image unavailable");
        return;
    }
    BUI_IMAGE_REQUEST = 1;
    reset_response();
    redirect_count = 0;
    state = ST_INIT;
    set_status("Loading image...");
}

static void network_tick(void)
{
    unsigned int n = 0;
    unsigned char burst;
    if (state == ST_FILE) { local_tick(); return; }
    if (state == ST_INIT) {
        if (!tr_init()) { fail_page("No network"); return; }
        state = ST_RESOLVE; set_status("Resolving..."); return;
    }
    if (state == ST_RESOLVE) {
        if (!tr_resolve()) { fail_page("DNS failed"); return; }
        state = ST_CONNECT; set_status("Connecting..."); return;
    }
    if (state == ST_CONNECT) {
        if (!tr_connect()) { fail_page("Connect failed"); return; }
        socket_open = 1; state = ST_SEND; set_status("Sending..."); return;
    }
    if (state == ST_SEND) {
        if (!tr_send((const unsigned char *)request, text_len(request))) {
            fail_page("Send failed"); return;
        }
        state = ST_RECV; idle_frames = 0; set_status("Waiting..."); return;
    }
    if (state != ST_RECV) return;
    if (receive_paused) return;
    if (rx_pos < rx_len) {
        process_rx();
        if (state != ST_RECV || receive_paused) return;
    }
#ifdef GB_PCW
    burst = 4;
#else
    burst = 2;
#endif
    while (burst-- && state == ST_RECV) {
        n = tr_recv(netbuf, NETBUF_SIZE);
        if (!n) break;
        idle_frames = 0;
        rx_len = (unsigned char)n;
        rx_pos = 0;
        process_rx();
        if (receive_paused) return;
    }
    if (state != ST_RECV || n) return;
    if (transport_rx_status == GB_NET_RX_CLOSED) {
        if (!header_done) fail_page("Closed early");
        else if (gb_http_chunked) fail_page("Incomplete chunk");
        else if (gb_http_have_length && bytes_done != gb_http_content_length)
            fail_page("Incomplete page");
        else finish_page();
    } else if (transport_rx_status == GB_NET_RX_ERROR) fail_page("Receive failed");
    else if (++idle_frames > 900) fail_page(transport_rx_status == GB_NET_RX_TIMEOUT ?
                                            "Transport timeout" : "Network timeout");
}

static void save_source(void)
{
    unsigned char action;
    source_flush();
    BUI_CTRL &= (unsigned char)~BUI_SAVE_PENDING;
    if ((BUI_FLAGS & BUI_SOURCE_FULL) || !BUI_NPAGES) {
        set_status("Source cache full"); return;
    }
    UI_OP = 8; UI_RES = 0;
    action = gb_ui();
    UI_MODAL = 0;
    if (action != BUI_ACT_SAVETO) { dirty = 1; return; }
    BUI_SAVE_RESULT = 0;
    BUI_CTRL |= BUI_SAVE_WORKER;
    set_status("Saving...");
    gb_wm_open("BRSAVE  APP");
}

static void run_menu(void)
{
    unsigned char action;
    if (!BUI_WANT_MENU) return;
    editing = caret_on = 0;
    caret_tick = 0;
    UI_OP = 5; UI_N = BUI_WANT_MENU; UI_RES = 0;
    BUI_WANT_MENU = 0;
    action = gb_ui();
    UI_MODAL = 0;
    if (action == BUI_ACT_LOAD) {
        if (socket_open) tr_close();
        state = ST_IDLE; receive_paused = 0;
        start_local();
    } else if (action == BUI_ACT_SAVE) {
        if (state == ST_RECV || state == ST_FILE) {
            BUI_CTRL |= BUI_CAPTURE_ALL | BUI_SAVE_PENDING;
            receive_paused = 0; line_budget = 0;
            set_status("Completing...");
        } else if (have_page) save_source();
        else set_status("No page to save");
    } else if (action == BUI_ACT_PROXY) {
        if (web_op(11)) {
            if (web_op(9))
                set_status(BUI_PROXY[0] ? "HTTP proxy enabled" : "Direct enabled");
            else set_status("Save failed");
        } else set_status("Invalid proxy");
    }
    BUI_IMAGE_SCAN = 1;
    dirty = 1;
}

static void make_url_view(void)
{
    unsigned char max = (unsigned char)(((URL_FIELD_W - 4) * 2) / 3);
    unsigned char start = 0, i = 0;
    if (url_len > max) start = (unsigned char)(url_len - max);
    while (url[start] && i < max) url_view[i++] = url[start++];
    url_view[i] = 0;
}

static void draw_url(void)
{
    make_url_view();
    gb_fill(2, URL_Y, URL_FIELD_W, URL_H, 1);
    gb_frame(2, URL_Y, URL_FIELD_W, URL_H, editing == 1 ? 3 : 2);
    gb_textbw(4, (unsigned char)(URL_Y + 2), url_view);
    if (editing == 1 && caret_on)
        gb_fill((unsigned char)(4 + ((unsigned int)text_len(url_view) * 3) / 2),
                (unsigned char)(URL_Y + 10), 2, 1, 3);
    gb_fill(GO_X, URL_Y, GO_W, URL_H, 1);
    gb_frame(GO_X, URL_Y, GO_W, URL_H, 2);
    gb_textbw((unsigned char)(GO_X + 2), (unsigned char)(URL_Y + 2), "Go");
    gb_fill(BACK_X, URL_Y, BACK_W, URL_H, 1);
    gb_frame(BACK_X, URL_Y, BACK_W, URL_H, 2);
    gb_textbw((unsigned char)(BACK_X + 2), (unsigned char)(URL_Y + 2), "Back");
}

static void redraw_url(void)
{
    gb_curhide();
    draw_url();
    gb_curshow();
}

static void redraw_caret(void)
{
    make_url_view();
    gb_curhide();
    gb_fill((unsigned char)(4 + ((unsigned int)text_len(url_view) * 3) / 2),
            (unsigned char)(URL_Y + 10), 2, 1, caret_on ? 3 : 1);
    gb_curshow();
}

static void draw_form(unsigned char y)
{
    char *text = BUI_FORM_VALUE;
    unsigned char len = (unsigned char)text_len(text);
    unsigned char max = (unsigned char)(((FORM_FIELD_W - 4) * 2) / 3);
    unsigned char bottom = (unsigned char)(CONTENT_Y + VIEW_ROWS * 8);
    unsigned char h = y + FORM_H <= bottom ? FORM_H : (unsigned char)(bottom - y);
    unsigned char text_y = h == FORM_H ? (unsigned char)(y + 4) : y;
    if (len > max) text += len - max;
    gb_fill(TEXT_X, y, FORM_FIELD_W, h, 1);
    gb_frame(TEXT_X, y, FORM_FIELD_W, h, editing == 2 ? 3 : 2);
    gb_textbw((unsigned char)(TEXT_X + 2), text_y, text);
    if (editing == 2 && caret_on)
        gb_fill((unsigned char)(TEXT_X + 2 + ((unsigned int)text_len(text) * 3) / 2),
                (unsigned char)(text_y + 1), 1, 6, 3);
    gb_fill(FORM_BUTTON_X, y, FORM_BUTTON_W, h, 0);
    gb_textrev((unsigned char)(FORM_BUTTON_X + 2), text_y, "Search");
}

static void redraw_form(void)
{
    gb_curhide();
    draw_form(BUI_FORM_ROW);
    gb_curshow();
}

static void draw_scrollbar(void)
{
    unsigned char area = (unsigned char)(VIEW_ROWS * 8), th, ty, total = hist_count;
    if ((receive_paused & RECEIVE_PAUSE_FLOW) && !cache_full && total < CACHE_LINES - VIEW_ROWS)
        total = (unsigned char)(total + VIEW_ROWS);
    gb_fill(SCROLL_X, CONTENT_Y, SCROLL_W, area, 1);
    if (total <= VIEW_ROWS) { th = area; ty = CONTENT_Y; }
    else {
        th = (unsigned char)(((unsigned int)area * VIEW_ROWS) / total);
        if (th < 6) th = 6;
        ty = (unsigned char)(CONTENT_Y +
             ((unsigned int)(area - th) * view_top) / (total - VIEW_ROWS));
    }
    if (th > 2) gb_fill((unsigned char)(SCROLL_X + 1), (unsigned char)(ty + 1),
                        1, (unsigned char)(th - 2), 3);
}

static void draw_page(void)
{
    unsigned char row, rel, y, w, mark;
    char *line;
    gb_fill(0, 24, GB_COLS, (unsigned char)(GB_LINES - 24), 0);
    draw_url();
    gb_text(2, STATUS_Y, status_text);
    if (title[0]) gb_text(2, TITLE_Y, title);
    gb_fill((unsigned char)(TEXT_X - 1), CONTENT_Y,
            (unsigned char)(GB_COLS - TEXT_X), (unsigned char)(VIEW_ROWS * 8), 1);
    draw_scrollbar();
    for (row = 0; row < VIEW_ROWS; row++) {
        rel = (unsigned char)(view_top + row);
        if (rel >= hist_count) break;
        y = (unsigned char)(CONTENT_Y + row * 8);
        line = history_line(rel);
        mark = (unsigned char)line[0];
        if (mark == IMAGE_MARK) {
            if (!BUI_IMAGE_READY ||
                (unsigned char)line[1] != (unsigned char)BUI_IMAGE_URL ||
                (unsigned char)line[2] != (unsigned char)(BUI_IMAGE_URL >> 8))
                gb_textbw(TEXT_X, y, line[3] ? line + 3 : "[Image]");
        } else if (mark == IMAGE_CONT_MARK) {
            /* Reserved vertical space for the image above. */
        } else if (mark == FORM_MARK) {
            if (editing == 2) BUI_FORM_ROW = y;
            draw_form(y);
        } else if (mark == FORM_CONT_MARK) {
            /* The second row is reserved by the form above it. */
        } else if (mark == LINK_MARK || mark == LINK_RAW_MARK) {
            line += mark == LINK_MARK ? 3 : 1;
            w = (unsigned char)(((unsigned int)text_len(line) * 3 + 1) / 2);
            if (w > GB_COLS - TEXT_X) w = (unsigned char)(GB_COLS - TEXT_X);
            gb_fill(TEXT_X, y, w, 8, 0);
            gb_text(TEXT_X, y, line);
            gb_fill(TEXT_X, (unsigned char)(y + 7), w, 1, 3);
        } else gb_textbw(TEXT_X, y, line);
    }
    if (BUI_IMAGE_READY) (void)image_op(23);
    dirty = 0; redraw_div = 0;
}

static void scroll_page(unsigned char down)
{
    unsigned char max_top;
    if (down) {
        if (view_top + VIEW_ROWS < hist_count) {
            max_top = (unsigned char)(hist_count - VIEW_ROWS);
            view_top = (unsigned char)(max_top - view_top > 3 ? view_top + 3 : max_top);
        }
        else if ((state == ST_RECV || state == ST_FILE) &&
                 (receive_paused & RECEIVE_PAUSE_FLOW) && !cache_full) {
            view_top = (unsigned char)(view_top + 3);
            line_budget = 3;
            receive_paused &= (unsigned char)~RECEIVE_PAUSE_FLOW;
            set_status("Receiving page...");
            return;
        }
    } else if (view_top) view_top = (unsigned char)(view_top > 3 ? view_top - 3 : 0);
    BUI_IMAGE_SCAN = 1;
    dirty = 1;
}

static void begin_url_edit(void)
{
    if (state != ST_IDLE) fail_page("Cancelled");
    url_len = current_url_len();
    editing = 1;
    caret_on = 1;
    caret_tick = 0;
    redraw_url();
}

static void handle_click(void)
{
    unsigned char x = gb_mx(), y = gb_my();
    unsigned char mark, form_y;
    char *line;
    if (y >= URL_Y && y < URL_Y + URL_H) {
        if (x >= BACK_X) go_back();
        else if (x >= GO_X) { if (state == ST_IDLE) start_page(); }
        else if (x < 2 + URL_FIELD_W) {
            begin_url_edit();
        }
        return;
    }
    if (x < SCROLL_X + SCROLL_W && y >= CONTENT_Y &&
        y < CONTENT_Y + VIEW_ROWS * 8) {
        scroll_page((unsigned char)(y >= CONTENT_Y + (VIEW_ROWS * 4)));
        return;
    }
    if (y >= CONTENT_Y && y < CONTENT_Y + VIEW_ROWS * 8) {
        unsigned char rel = (unsigned char)(view_top + (y - CONTENT_Y) / 8);
        if (rel < hist_count) {
            form_y = (unsigned char)(CONTENT_Y + ((y - CONTENT_Y) / 8) * 8);
            line = history_line(rel);
            mark = (unsigned char)line[0];
            if (mark == FORM_CONT_MARK && rel > view_top) {
                line = history_line((unsigned char)(rel - 1));
                if ((unsigned char)line[0] == FORM_MARK) {
                    mark = FORM_MARK;
                    form_y = (unsigned char)(form_y - 8);
                }
            }
            if (mark == FORM_MARK) {
                if (x >= TEXT_X && x < FORM_BUTTON_X - 1) {
                    editing = 2; caret_on = 1; caret_tick = 0;
                    BUI_FORM_ROW = form_y;
                    dirty = 1; redraw_form();
                } else if (x >= FORM_BUTTON_X) submit_form();
            } else if (mark == LINK_MARK) {
                unsigned int off = (unsigned char)line[1] |
                                   ((unsigned int)(unsigned char)line[2] << 8);
                if (load_resource(off)) open_link(link_url);
            } else if (mark == LINK_RAW_MARK) open_link(line + 1);
        }
    }
}

static void handle_keys(void)
{
    unsigned char c, count = 8, changed = 0, n;
    if (editing == 1) url_len = current_url_len();
    if (!editing && down_key_event() &&
        (state == ST_IDLE || BUI_IMAGE_REQUEST ||
         (receive_paused & RECEIVE_PAUSE_FLOW)))
        scroll_page(1);
    while (count-- && (c = gb_getkey()) != 0) {
        if (state != ST_IDLE) {
            if (c == 'g' || c == 'G') {
                begin_url_edit();
                continue;
            }
            if (c == 0x1B) fail_page("Cancelled");
            else if (BUI_IMAGE_REQUEST && c == 0x10) scroll_page(0);
            else if (BUI_IMAGE_REQUEST && c == 0x0E) scroll_page(1);
            else if ((receive_paused & RECEIVE_PAUSE_FLOW) && c == 0x10) scroll_page(0);
            else if ((receive_paused & RECEIVE_PAUSE_FLOW) && c == 0x0E) scroll_page(1);
            continue;
        }
        if (!editing) {
            if (c == 'g' || c == 'G') {
                begin_url_edit();
            }
            else if (c == 'b' || c == 'B') { go_back(); return; }
            else if (c == 0x10) scroll_page(0);
            else if (c == 0x0E) scroll_page(1);
            continue;
        }
        if (editing == 2) {
            if (c == 0x0D) { submit_form(); return; }
            if (c == 0x1B) {
                editing = caret_on = 0; caret_tick = 0; redraw_form(); return;
            }
            n = (unsigned char)text_len(BUI_FORM_VALUE);
            if ((c == 8 || c == 0x7F) && n) {
                BUI_FORM_VALUE[n - 1] = 0; changed = 1;
            } else if (c >= 32 && c < 127 && n < BUI_FORM_VALUE_MAX) {
                BUI_FORM_VALUE[n++] = (char)c; BUI_FORM_VALUE[n] = 0; changed = 1;
            }
            continue;
        }
        if (c == 0x0D) { start_page(); return; }
        if (c == 0x1B) {
            editing = 0; caret_on = 0; caret_tick = 0; redraw_url(); return;
        }
        if ((c == 8 || c == 0x7F) && url_len) {
            if (!edit_changed) {
                if (have_page) { copy_url(back_url, url); have_back = 1; }
                edit_changed = 1;
            }
            url[--url_len] = 0; changed = 1;
        } else if (c >= 32 && c < 127 && url_len < URL_MAX) {
            if (!edit_changed) {
                if (have_page) { copy_url(back_url, url); have_back = 1; }
                edit_changed = 1;
            }
            url[url_len++] = (char)c; url[url_len] = 0; changed = 1;
        }
    }
    if (changed) {
        caret_tick = 0; caret_on = 1;
        if (editing == 2) redraw_form(); else redraw_url();
    }
    else if (editing && ++caret_tick >= 18) {
        caret_tick = 0; caret_on ^= 1;
        if (editing == 2) redraw_form(); else redraw_caret();
    }
}

static void frame_tick(void)
{
    if (receive_paused & RECEIVE_PAUSE_FLUSH) {
        source_flush();
        receive_paused &= (unsigned char)~RECEIVE_PAUSE_FLUSH;
    }
    if ((BUI_CTRL & BUI_SAVE_WORKER) && BUI_SAVE_RESULT) {
        BUI_CTRL &= (unsigned char)~BUI_SAVE_WORKER;
        set_status(BUI_SAVE_RESULT == 1 ? "Page saved" : "Save failed");
    }
    run_menu();
    handle_keys();
    network_tick();
    if (state == ST_IDLE && (BUI_CTRL & BUI_SAVE_PENDING)) save_source();
    if (state == ST_IDLE && !editing && !(BUI_CTRL & BUI_SAVE_PENDING))
        start_visible_image();
    if (!editing && dirty &&
        (state == ST_IDLE || (receive_paused & RECEIVE_PAUSE_FLOW) || ++redraw_div >= 6)) {
        gb_curhide(); draw_page(); gb_curshow();
    }
}

static void browser_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  draw_page(); break;
        case GB_MSG_FRAME: frame_tick(); break;
        case GB_MSG_CLICK: handle_click(); break;
        case GB_MSG_MENU:
            if (gb_msg.p0 >= 10 && gb_msg.p0 < 17) BUI_WANT_MENU = 1;
            else if (gb_msg.p0 >= 17 && gb_msg.p0 < 30) BUI_WANT_MENU = 2;
            break;
        case GB_MSG_CLOSE:
            if (socket_open) tr_close();
            (void)web_op(7);
            if (cache_page) {
                PIC_PAGE_K = cache_page;
                PIC_PAGE2_K = 0;
                gb_pic_close();
                cache_page = 0;
            }
            gb_wm_close();
            break;
        case GB_MSG_DRAG: break;
    }
}

static const gb_mwin_t browser_window = {
    0, 8, GB_COLS, (GB_LINES - 8), 0, 0, browser_proc, "Browser"
};

void main(void)
{
    BUI_NPAGES = 0; BUI_TAIL = BUI_STAGE_LEN = 0; BUI_FLAGS = 0;
    BUI_CTRL = BUI_WANT_MENU = 0;
    BUI_LINE_SIZE = LINE_SIZE; BUI_VIEW_ROWS = VIEW_ROWS;
    BUI_TEXT_X = TEXT_X; BUI_CONTENT_Y = CONTENT_Y; BUI_SCREEN_COLS = GB_COLS;
    copy_url(BUI_MODNAME, "GBWEB   MOD");
    (void)web_op(12);
    url[0] = 0;
    title[0] = pending[0] = 0;
    url_len = title_len = 0;
    hist_start = hist_count = view_top = pending_len = cache_full = 0;
    cache_page = alloc_cache_page();
    reset_resources();
    status_text = cache_page ? "" : "Limited page cache";
    editing = dirty = 1;
    gb_wm_managed(&browser_window);
    if (web_op(13)) start_local();
    gb_menu(browser_menu_def);
    gb_restore_parent();
}
