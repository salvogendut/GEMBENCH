/* BROWSER.APP - bounded, text-first streaming HTTP browser for GEOBENCH.
 *
 * Pages are parsed directly into fixed-width rendered lines in one borrowed
 * 16K page. No DOM is retained; a bounded raw-source copy supports offline
 * Save. CPC uses GBNET, while PCW uses PerryNet. */
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
#define CACHE_LINES   255
#define FALLBACK_LINES 7

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
    ld a,c
    ret
__endasm;
}

#ifdef GB_PCW
#define PCW_STAGE_BYTES LINE_SIZE
#define PCW_BACK_OFS    PCW_STAGE_BYTES
#define PCW_FRAME_OFS   (PCW_BACK_OFS + URL_MAX + 1)
#define PCW_LINK_OFS    (PCW_FRAME_OFS + 264)
#define PCW_ALT_OFS     (PCW_LINK_OFS + LINK_MAX + 1)
#define PCW_ENTITY_OFS  (PCW_ALT_OFS + ALT_MAX + 1)
#define PCW_HEADER_OFS  (PCW_ENTITY_OFS + 10)
#define PCW_NETBUF_OFS  (PCW_HEADER_OFS + HEADER_MAX + 1)
#define PCW_REQUEST_OFS (PCW_NETBUF_OFS + NETBUF_SIZE)
#define PCW_FALLBACK_OFS (PCW_REQUEST_OFS + REQUEST_MAX + 1)
#define PCW_TITLE_OFS   (PCW_FALLBACK_OFS + FALLBACK_LINES * LINE_SIZE)
#define PCW_URL_OFS     (PCW_TITLE_OFS + TITLE_MAX + 1)
#define PCW_HOST_OFS    (PCW_URL_OFS + URL_MAX + 1)
#define PCW_PATH_OFS    (PCW_HOST_OFS + HOST_MAX + 1)
#define PCW_PENDING_OFS (PCW_PATH_OFS + PATH_MAX + 1)
#define request     ((char *)&gb_copybuf[PCW_REQUEST_OFS])
#define header_line ((char *)&gb_copybuf[PCW_HEADER_OFS])
#define netbuf      ((unsigned char *)&gb_copybuf[PCW_NETBUF_OFS])
#define link_url    ((char *)&gb_copybuf[PCW_LINK_OFS])
#define alt_text    ((char *)&gb_copybuf[PCW_ALT_OFS])
#define entity_text ((char *)&gb_copybuf[PCW_ENTITY_OFS])
#define fallback    (&gb_copybuf[PCW_FALLBACK_OFS])
#define title       (&gb_copybuf[PCW_TITLE_OFS])
#define url         (&gb_copybuf[PCW_URL_OFS])
#define host        (&gb_copybuf[PCW_HOST_OFS])
#define path        (&gb_copybuf[PCW_PATH_OFS])
#define pending     (&gb_copybuf[PCW_PENDING_OFS])
#else
static char url[URL_MAX + 1];
static char host[HOST_MAX + 1];
static char path[PATH_MAX + 1];
static char request[REQUEST_MAX + 1];
static char header_line[HEADER_MAX + 1];
static unsigned char netbuf[NETBUF_SIZE];
static char link_url[LINK_MAX + 1];
static char alt_text[ALT_MAX + 1];
static char entity_text[10];
#endif
#ifdef GB_PCW
/* PCW networking is direct serial I/O, so transient protocol state and the
 * no-spare-bank fallback can live above the bank service's short #2200 staging
 * record. CPC GBNET owns that area, so its fallback remains app-local. */
#define back_url (&gb_copybuf[PCW_BACK_OFS])
#define BROWSER_PCW_FRAME_BUFFER ((unsigned char *)&gb_copybuf[PCW_FRAME_OFS])
#else
static char title[TITLE_MAX + 1];
static char fallback[FALLBACK_LINES * LINE_SIZE];
static char back_url[URL_MAX + 1];
static char pending[LINE_SIZE];
#endif
/* Drawing runs after each receive burst, so the consumed network buffer can
 * double as the short URL viewport and borrowed-bank line staging area without
 * increasing app RAM. */
#define url_view ((char *)netbuf)
#define line_buf ((char *)netbuf)

static const char *status_text;
static unsigned int port;
static const char *parsed_p;
static char *parsed_dst;
static unsigned int parsed_port;
static unsigned int idle_frames;
static unsigned long bytes_done;
static unsigned char state, editing, url_len, title_len;
static unsigned char header_done, line_overflow, socket_open;
static unsigned char transport_rx_status, redirect_count;
static unsigned char hist_start, hist_count, view_top, pending_len;
static unsigned char dirty, caret_tick, caret_on, redraw_div;
static unsigned char parsed_len, parsed_digit;
static unsigned char have_page, have_back, edit_changed;
static unsigned char cache_page, cache_full;
static unsigned char rx_len, rx_pos, receive_paused, line_budget;

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

static unsigned char web_op(unsigned char op)
{
    UI_OP = op;
    UI_RES = 0;
    return web_call();
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

static void persist_proxy(void)
{
    unsigned char i, d = gb_drives();
    (void)web_op(9);                         /* update the live KCFG text */
    gb_set_drive((d & GB_DRV_C) ? GB_DRIVE_C : GB_DRIVE_A);
    for (i = 0; i < 4; i++) gb_back();
    gb_set_name("GEOBENCHCFG");
    gb_fs_save((char *)0x1000, *(volatile unsigned int *)0x1200);
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
    pending[pending_len++] = (char)c;
    if (pending_len >= TEXT_COLS) add_line();
}

static void output_break(unsigned char kind)
{
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

static void link_begin(const char *href)
{
    output_break(1);
    pending[0] = LINK_MARK;
    pending_len = 1;
    output_text(href);
    if (pending_len) add_line();
}

static void link_end(void) { output_break(1); }

static void image_alt(const char *alt)
{
    output_char('['); output_text(alt); output_char(']');
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
#define GB_HTML_NO_IMAGE_ALT     1
#define GB_HTML_NAMED_ENTITIES_ONLY 1
#define GB_HTML_EMIT_TEXT(c)     output_char(c)
#define GB_HTML_EMIT_TITLE(c)    title_char(c)
#define GB_HTML_EMIT_BREAK(k)    output_break(k)
#define GB_HTML_LINK_BEGIN(u)    link_begin(u)
#define GB_HTML_LINK_END()       link_end()
#define GB_HTML_IMAGE_ALT(a)     image_alt(a)
#include "gbhtml.h"

static unsigned char body_write(const unsigned char *buf, unsigned int len)
{
    unsigned int i;
    for (i = 0; i < len; i++) source_byte(buf[i]);
    gb_html_feed(buf, len);
    bytes_done += len;
    return 1;
}

static void finish_page(void);
static void fail_page(const char *s);

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
#define BROWSER_TR_PORT ((BUI_CTRL & BUI_PROXY_ON) ? BUI_PROXY_PORT : port)
#include "transport.h"

static char *put_dec(char *p, unsigned int v)
{
    unsigned int d = 10000;
    unsigned char started = 0, n;
    while (d) {
        n = 0;
        while (v >= d) { v -= d; n++; }
        if (n || started || d == 1) { *p++ = (char)('0' + n); started = 1; }
        d /= 10;
    }
    *p = 0;
    return p;
}

static unsigned char compose_url(void)
{
    const char *s;
    unsigned char n = 0;
#define APPEND_TEXT(t) do { s = (t); while (*s) { if (n >= URL_MAX) return 0; url[n++] = *s++; } } while (0)
    APPEND_TEXT("http://");
    APPEND_TEXT(host);
    if (port != 80) {
        if (n >= URL_MAX) return 0;
        url[n++] = ':';
        put_dec(alt_text, port);
        APPEND_TEXT(alt_text);
    }
    APPEND_TEXT(path);
    url[n] = 0;
    url_len = n;
    return 1;
#undef APPEND_TEXT
}

static unsigned char parse_url(void)
{
    parsed_p = url;
    if (ci_prefix(parsed_p, "https://")) { set_status("HTTPS unsupported"); return 0; }
    if (!ci_prefix(parsed_p, "http://")) { set_status("Use http://"); return 0; }
    parsed_p += 7;
    parsed_dst = host;
    parsed_len = 0;
    while (*parsed_p && *parsed_p != '/' && *parsed_p != ':' &&
           *parsed_p != '?' && *parsed_p != '#' && parsed_len < HOST_MAX) {
        *parsed_dst++ = *parsed_p++;
        parsed_len++;
    }
    *parsed_dst = 0;
    if (!parsed_len || (*parsed_p && *parsed_p != '/' && *parsed_p != ':' &&
                        *parsed_p != '?' && *parsed_p != '#')) {
        set_status("Host too long"); return 0;
    }
    port = 80;
    if (*parsed_p == ':') {
        parsed_p++;
        if (*parsed_p < '0' || *parsed_p > '9') { set_status("Invalid port number"); return 0; }
        parsed_port = 0;
        while (*parsed_p >= '0' && *parsed_p <= '9') {
            parsed_digit = (unsigned char)(*parsed_p++ - '0');
            if (parsed_port > 6553 || (parsed_port == 6553 && parsed_digit > 5)) {
                set_status("Invalid port number"); return 0;
            }
            parsed_port = (unsigned int)(parsed_port * 10 + parsed_digit);
        }
        if (!parsed_port) { set_status("Invalid port number"); return 0; }
        port = parsed_port;
    }
    if (*parsed_p && *parsed_p != '/' && *parsed_p != '?' && *parsed_p != '#') {
        set_status("Invalid URL"); return 0;
    }
    parsed_dst = path;
    parsed_len = 0;
    if (!*parsed_p || *parsed_p == '#') {
        *parsed_dst++ = '/';
        parsed_len = 1;
    }
    else {
        if (*parsed_p == '?') {
            *parsed_dst++ = '/';
            parsed_len = 1;
        }
        while (*parsed_p && *parsed_p != '#' && parsed_len < PATH_MAX) {
            *parsed_dst++ = *parsed_p++;
            parsed_len++;
        }
    }
    *parsed_dst = 0;
    if (*parsed_p && *parsed_p != '#') { set_status("Path too long"); return 0; }
    return 1;
}

/* build_request has already consumed the destination host/path when this runs,
 * so host/port can become the proxy endpoint used by the transport. */
static unsigned char apply_proxy(void)
{
    if (web_op(11)) return 1;
    set_status("Invalid proxy");
    return 0;
}

static unsigned char copy_redirect(char *dst, const char *src, unsigned char max)
{
    unsigned char n = 0;
    while (*src && *src != '#') {
        if (n >= max) return 0;
        dst[n++] = *src++;
    }
    dst[n] = 0;
    return 1;
}

static unsigned char resolve_redirect(void)
{
    const char *loc = request;
    const char *p, *base_end = path;
    unsigned char n = 0;
    header_line[0] = 0;
    if (!*loc) return 0;
    if (ci_prefix(loc, "http://") || ci_prefix(loc, "https://")) {
        if (!copy_redirect(url, loc, URL_MAX)) return 0;
        url_len = (unsigned char)text_len(url);
        return parse_url();
    }
    if (loc[0] == '/' && loc[1] == '/') {
        url[0] = 'h'; url[1] = 't'; url[2] = 't'; url[3] = 'p'; url[4] = ':';
        if (!copy_redirect(url + 5, loc, URL_MAX - 5)) return 0;
        url_len = (unsigned char)text_len(url);
        return parse_url();
    }
    if (*loc == '/') {
        if (!copy_redirect(header_line, loc, PATH_MAX)) return 0;
    } else if (*loc == '?') {
        p = path;
        while (*p && *p != '?') {
            if (n >= PATH_MAX) return 0;
            header_line[n++] = *p++;
        }
        header_line[n] = 0;
        if (!copy_redirect(header_line + n, loc, PATH_MAX - n)) return 0;
    } else {
        p = path;
        while (*p && *p != '?') { if (*p == '/') base_end = p + 1; p++; }
        for (p = path; p < base_end; p++) {
            if (n >= PATH_MAX) return 0;
            header_line[n++] = *p;
        }
        header_line[n] = 0;
        if (!copy_redirect(header_line + n, loc, PATH_MAX - n)) return 0;
    }
    for (n = 0; header_line[n]; n++) path[n] = header_line[n];
    path[n] = 0;
    return compose_url();
}

static unsigned char build_request(void)
{
    char *p = request, *limit = request + REQUEST_MAX;
    const char *s;
#define ADD_TEXT(t) do { s = (t); while (*s && p < limit) *p++ = *s++; } while (0)
    ADD_TEXT("GET "); ADD_TEXT(BUI_PROXY[0] ? url : path);
    ADD_TEXT(" HTTP/1.0\r\nHost: "); ADD_TEXT(host);
    if (port != 80) { if (p < limit) *p++ = ':'; p = put_dec(p, port); }
    ADD_TEXT("\r\nUser-Agent: GB/1\r\nConnection: close\r\n\r\n");
    if (p >= limit) { request[REQUEST_MAX] = 0; return 0; }
    *p = 0;
    return 1;
#undef ADD_TEXT
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
    gb_html_end();
    if (pending_len) add_line();
    if (view_top && view_top + VIEW_ROWS > hist_count) view_top--;
    have_page = 1;
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
        if (gb_http_have_location != 1) {
            fail_page(gb_http_have_location == 2 ? "Redirect too long" :
                                                  "Redirect missing");
            return;
        }
        if (redirect_count >= MAX_REDIRECTS) { fail_page("Redirect limit"); return; }
        tr_close();
        if ((BUI_CTRL & BUI_PROXY_ON) && !parse_url()) {
            fail_page("Bad redirect base"); return;
        }
        hist_start = hist_count = view_top = pending_len = cache_full = 0;
        have_page = 0;
        receive_paused = 0;
        line_budget = cache_page ? 0 : FALLBACK_LINES;
        title_len = 0; title[0] = 0;
        if (!resolve_redirect()) redir_err = (status_text != prev_status ? status_text : "Bad redirect");
        else if (!build_request()) redir_err = "Bad redirect";
        else if (!apply_proxy()) redir_err = "Bad redirect";
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
    set_status("Receiving page...");
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
    if (!parse_url() || !build_request() || !apply_proxy()) return;
    source_reset();
    BUI_CTRL &= BUI_PROXY_ON;
    hist_start = hist_count = view_top = pending_len = cache_full = 0;
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
    url_len = (unsigned char)text_len(url);
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
    if (!copy_redirect(request, href, URL_MAX) || !resolve_redirect()) {
        copy_url(url, back_url);
        url_len = (unsigned char)text_len(url);
        parse_url();
        set_status("Invalid link URL");
        return;
    }
    have_back = 1;
    start_page();
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
    source_flush();
    BUI_CTRL &= (unsigned char)~BUI_SAVE_PENDING;
    if ((BUI_FLAGS & BUI_SOURCE_FULL) || !BUI_NPAGES) {
        set_status("Source cache full"); return;
    }
    UI_OP = 8; UI_RES = 0;
    if (gb_ui() != BUI_ACT_SAVETO) { dirty = 1; return; }
    BUI_SAVE_RESULT = 0;
    BUI_CTRL |= BUI_SAVE_WORKER;
    set_status("Saving...");
    gb_wm_open("BRSAVE  APP");
}

static void run_menu(void)
{
    unsigned char action;
    if (!BUI_WANT_MENU) return;
    UI_OP = 5; UI_N = BUI_WANT_MENU; UI_RES = 0;
    BUI_WANT_MENU = 0;
    action = gb_ui();
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
        persist_proxy();
        set_status(BUI_PROXY[0] ? "HTTP proxy enabled" : "Direct enabled");
    }
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
    gb_frame(2, URL_Y, URL_FIELD_W, URL_H, editing ? 3 : 2);
    gb_textbw(4, (unsigned char)(URL_Y + 2), url_view);
    if (editing && caret_on)
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
    unsigned char row, rel, y, w;
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
        if ((unsigned char)line[0] == LINK_MARK) {
            line++;
            w = (unsigned char)(((unsigned int)text_len(line) * 3 + 1) / 2);
            if (w > GB_COLS - TEXT_X) w = (unsigned char)(GB_COLS - TEXT_X);
            gb_fill(TEXT_X, y, w, 8, 0);
            gb_text(TEXT_X, y, line);
            gb_fill(TEXT_X, (unsigned char)(y + 7), w, 1, 3);
        } else gb_textbw(TEXT_X, y, line);
    }
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
    dirty = 1;
}

static void handle_click(void)
{
    unsigned char x = gb_mx(), y = gb_my();
    if (y >= URL_Y && y < URL_Y + URL_H) {
        if (x >= BACK_X) go_back();
        else if (x >= GO_X) { if (state == ST_IDLE) start_page(); }
        else if (x < 2 + URL_FIELD_W) {
            if (state != ST_IDLE) fail_page("Cancelled");
            editing = 1; caret_on = 1; caret_tick = 0; redraw_url();
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
        if (rel < hist_count && (unsigned char)history_line(rel)[0] == LINK_MARK) {
            open_link(history_line(rel) + 1);
        }
    }
}

static void handle_keys(void)
{
    unsigned char c, count = 8, changed = 0;
    while (count-- && (c = gb_getkey()) != 0) {
        if (state != ST_IDLE) {
            if (c == 'g' || c == 'G') {
                fail_page("Cancelled");
                editing = 1; caret_on = 1; caret_tick = 0; redraw_url();
                continue;
            }
            if (c == 0x1B) fail_page("Cancelled");
            else if ((receive_paused & RECEIVE_PAUSE_FLOW) && c == 0x10) scroll_page(0);
            else if ((receive_paused & RECEIVE_PAUSE_FLOW) && c == 0x0E) scroll_page(1);
            continue;
        }
        if (!editing) {
            if (c == 'g' || c == 'G') {
                editing = 1; caret_on = 1; caret_tick = 0; redraw_url();
            }
            else if (c == 'b' || c == 'B') { go_back(); return; }
            else if (c == 0x10) scroll_page(0);
            else if (c == 0x0E) scroll_page(1);
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
    if (changed) { caret_tick = 0; caret_on = 1; redraw_url(); }
    else if (editing && ++caret_tick >= 18) {
        caret_tick = 0; caret_on ^= 1; redraw_caret();
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
    if (dirty && (state == ST_IDLE || (receive_paused & RECEIVE_PAUSE_FLOW) || ++redraw_div >= 6)) {
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
    copy_url(BUI_MODNAME, "GBWEB   MOD");
    (void)web_op(12);
    url[url_len] = 0;
    cache_page = alloc_cache_page();
    status_text = cache_page ? "Ready" : "Ready: limited page cache";
    editing = dirty = 1;
    gb_wm_managed(&browser_window);
    if (web_op(13)) start_local();
    gb_menu(browser_menu_def);
    gb_restore_parent();
}
