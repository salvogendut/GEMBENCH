#ifndef GBHTTP_H
#define GBHTTP_H

/* Bounded HTTP/1.x response parsing for banked GEOBENCH applications.
 *
 * By default the component keeps one small app-local scalar state set.  A
 * tightly packed app can define GB_HTTP_EXTERNAL_STATE and bind the names to
 * an existing layout.  The caller also binds bounded header/Location buffers
 * and compile-time callbacks; response bodies are never retained here.  Define
 * GB_HTTP_ENABLE_RANGE when Content-Range metadata is needed.
 */

#ifndef GB_HTTP_INVALID_RESPONSE
#define GB_HTTP_INVALID_RESPONSE() ((void)0)
#endif
#ifndef GB_HTTP_INVALID_STATUS
#define GB_HTTP_INVALID_STATUS() ((void)0)
#endif
#ifndef GB_HTTP_BODY_WRITE
#define GB_HTTP_BODY_WRITE(buf, len) 1
#endif
#ifndef GB_HTTP_FINISH
#define GB_HTTP_FINISH() ((void)0)
#endif
#ifndef GB_HTTP_BAD_CHUNK
#define GB_HTTP_BAD_CHUNK() ((void)0)
#endif
#ifndef GB_HTTP_BAD_CHUNK_SIZE
#define GB_HTTP_BAD_CHUNK_SIZE() ((void)0)
#endif
#ifndef GB_HTTP_CHUNK_TOO_LARGE
#define GB_HTTP_CHUNK_TOO_LARGE() ((void)0)
#endif
#ifndef GB_HTTP_HEADER_LINE
#error "GB_HTTP_HEADER_LINE must name the bounded header-line buffer"
#endif
#ifndef GB_HTTP_LOCATION
#error "GB_HTTP_LOCATION must name the bounded Location buffer"
#endif
#ifndef GB_HTTP_LOCATION_MAX
#error "GB_HTTP_LOCATION_MAX must be the Location capacity excluding NUL"
#endif
#ifndef GB_HTTP_TRAILER_MAX
#define GB_HTTP_TRAILER_MAX 255
#endif

/* Scalar state is intentional: SDCC's Z80 backend emits substantially smaller
 * absolute accesses for these than for fields reached through a struct. */
#ifndef GB_HTTP_EXTERNAL_STATE
static unsigned long gb_http_content_length;
static unsigned long gb_http_chunk_left;
#ifdef GB_HTTP_ENABLE_RANGE
static unsigned long gb_http_range_start;
static unsigned long gb_http_range_total;
#endif
static unsigned int gb_http_status_code;
static unsigned char gb_http_line_len;
static unsigned char gb_http_first_header;
static unsigned char gb_http_have_length;
static unsigned char gb_http_chunked;
static unsigned char gb_http_chunk_state;
static unsigned char gb_http_chunk_have_digit;
static unsigned char gb_http_have_location;
#ifdef GB_HTTP_ENABLE_RANGE
static unsigned char gb_http_have_content_range;
static unsigned char gb_http_range_total_known;
static unsigned char gb_http_range_unsatisfied;
#endif
#endif

#ifndef GB_HTTP_EXTERNAL_HELPERS
static unsigned char gb_http_lower(unsigned char c)
{
    if (c >= 'A' && c <= 'Z') c = (unsigned char)(c + ('a' - 'A'));
    return c;
}

static unsigned char gb_http_ci_prefix(const char *s, const char *p)
{
    while (*p) {
        if (!*s) return 0;
        if (gb_http_lower((unsigned char)*s++) !=
            gb_http_lower((unsigned char)*p++)) return 0;
    }
    return 1;
}

static unsigned char gb_http_ci_contains(const char *s, const char *word)
{
    while (*s) {
        if (gb_http_ci_prefix(s, word)) return 1;
        s++;
    }
    return 0;
}
#endif

static unsigned char gb_http_parse_number(const char **text,
                                          unsigned long *out)
{
    const char *s = *text;
    unsigned long v = 0;
    unsigned char digit;
    if (*s < '0' || *s > '9') return 0;
    while (*s >= '0' && *s <= '9') {
        digit = (unsigned char)(*s++ - '0');
        if (v > 1677721UL || (v == 1677721UL && digit > 5)) return 0;
        v = v * 10UL + digit;
    }
    *text = s;
    *out = v;
    return 1;
}

static unsigned char gb_http_parse_length(const char *s, unsigned long *out)
{
    while (*s == ' ' || *s == '\t') s++;
    if (!gb_http_parse_number(&s, out)) return 0;
    while (*s == ' ' || *s == '\t') s++;
    return (unsigned char)(*s == 0);
}

#ifdef GB_HTTP_ENABLE_RANGE
static unsigned char gb_http_parse_content_range(const char *s)
{
    while (*s == ' ' || *s == '\t') s++;
    if (!gb_http_ci_prefix(s, "bytes")) return 0;
    s += 5;
    while (*s == ' ' || *s == '\t') s++;
    gb_http_range_unsatisfied = 0;
    gb_http_range_total_known = 0;
    if (*s == '*') {
        gb_http_range_unsatisfied = 1;
        s++;
    } else {
        if (!gb_http_parse_number(&s, &gb_http_range_start) || *s++ != '-' ||
            !gb_http_parse_number(&s, &gb_http_range_total)) return 0;
    }
    if (*s++ != '/') return 0;
    if (*s == '*') s++;
    else {
        if (!gb_http_parse_number(&s, &gb_http_range_total)) return 0;
        gb_http_range_total_known = 1;
    }
    while (*s == ' ' || *s == '\t') s++;
    return (unsigned char)(*s == 0);
}
#endif

#ifdef GB_HTTP_ENABLE_RANGE
#define GB_HTTP_RANGE_INIT() do { \
    gb_http_range_start = gb_http_range_total = 0; \
    gb_http_have_content_range = 0; \
    gb_http_range_total_known = 0; \
    gb_http_range_unsatisfied = 0; \
} while (0)
#else
#define GB_HTTP_RANGE_INIT() ((void)0)
#endif

/* Keep reset inline for stack-constrained banked applications. */
#define gb_http_response_init() do { \
    gb_http_content_length = 0; \
    gb_http_chunk_left = 0; \
    gb_http_status_code = 0; \
    gb_http_line_len = 0; \
    gb_http_first_header = 1; \
    gb_http_have_length = 0; \
    gb_http_chunked = 0; \
    gb_http_chunk_state = 0; \
    gb_http_chunk_have_digit = 0; \
    gb_http_have_location = 0; \
    GB_HTTP_RANGE_INIT(); \
} while (0)

static void gb_http_process_header_line(void)
{
    char *p = GB_HTTP_HEADER_LINE;
    GB_HTTP_HEADER_LINE[gb_http_line_len] = 0;
    if (gb_http_first_header) {
        gb_http_first_header = 0;
        if (!gb_http_ci_prefix(p, "HTTP/")) {
            GB_HTTP_INVALID_RESPONSE();
            return;
        }
        while (*p && *p != ' ') p++;
        while (*p == ' ') p++;
        if (p[0] < '0' || p[0] > '9' || p[1] < '0' || p[1] > '9' ||
            p[2] < '0' || p[2] > '9') {
            GB_HTTP_INVALID_STATUS();
            return;
        }
        gb_http_status_code = (unsigned int)(p[0] - '0') * 100 +
                              (unsigned int)(p[1] - '0') * 10 +
                              (unsigned int)(p[2] - '0');
    } else if (gb_http_ci_prefix(p, "Content-Length:")) {
        if (gb_http_parse_length(p + 15, &gb_http_content_length))
            gb_http_have_length = 1;
    } else if (gb_http_ci_prefix(p, "Transfer-Encoding:") &&
               gb_http_ci_contains(p + 18, "chunked")) {
        gb_http_chunked = 1;
    } else if (gb_http_ci_prefix(p, "Location:")) {
        unsigned char n = 0;
        p += 9;
        while (*p == ' ' || *p == '\t') p++;
        while (p[n] && n <= GB_HTTP_LOCATION_MAX) n++;
        while (n && (p[n - 1] == ' ' || p[n - 1] == '\t')) n--;
        if (!n) gb_http_have_location = 0;
        else if (n > GB_HTTP_LOCATION_MAX) gb_http_have_location = 2;
        else {
            unsigned char i;
            for (i = 0; i < n; i++) GB_HTTP_LOCATION[i] = p[i];
            GB_HTTP_LOCATION[n] = 0;
            gb_http_have_location = 1;
        }
#ifdef GB_HTTP_ENABLE_RANGE
    } else if (gb_http_ci_prefix(p, "Content-Range:")) {
        gb_http_have_content_range = gb_http_parse_content_range(p + 14);
#endif
    }
}

/* Consume one byte of a chunked body and deliver decoded bytes through the
 * compile-time callbacks above.  A false return means transfer processing
 * completed or failed. */
static unsigned char gb_http_chunk_byte(unsigned char c)
{
    unsigned char v;
    if (gb_http_chunk_state == 0) {
        if (c == '\r') return 1;
        if (c == '\n') {
            if (!gb_http_chunk_have_digit) {
                GB_HTTP_BAD_CHUNK();
                return 0;
            }
            if (!gb_http_chunk_left) {
                gb_http_chunk_state = 3;
                gb_http_line_len = 0;
                return 1;
            }
            gb_http_chunk_state = 1;
            return 1;
        }
        if (c == ';') {
            gb_http_chunk_state = 4;
            return 1;
        }
        if (c >= '0' && c <= '9') v = (unsigned char)(c - '0');
        else if (gb_http_lower(c) >= 'a' && gb_http_lower(c) <= 'f')
            v = (unsigned char)(gb_http_lower(c) - 'a' + 10);
        else {
            GB_HTTP_BAD_CHUNK_SIZE();
            return 0;
        }
        if (gb_http_chunk_left > 0x0FFFFFUL) {
            GB_HTTP_CHUNK_TOO_LARGE();
            return 0;
        }
        gb_http_chunk_left = (gb_http_chunk_left << 4) | v;
        gb_http_chunk_have_digit = 1;
        return 1;
    }
    if (gb_http_chunk_state == 4) {
        if (c == '\n') {
            gb_http_chunk_state = gb_http_chunk_left ? 1 : 3;
            if (!gb_http_chunk_left) gb_http_line_len = 0;
        }
        return 1;
    }
    if (gb_http_chunk_state == 1) {
        if (!GB_HTTP_BODY_WRITE(&c, 1)) return 0;
        if (--gb_http_chunk_left == 0) gb_http_chunk_state = 2;
        return 1;
    }
    if (gb_http_chunk_state == 2) {
        if (c == '\n') {
            gb_http_chunk_state = 0;
            gb_http_chunk_left = 0;
            gb_http_chunk_have_digit = 0;
        }
        return 1;
    }
    if (c == '\r') return 1;
    if (c == '\n') {
        if (!gb_http_line_len) {
            GB_HTTP_FINISH();
            return 0;
        }
        gb_http_line_len = 0;
        return 1;
    }
    if (gb_http_line_len < GB_HTTP_TRAILER_MAX) gb_http_line_len++;
    return 1;
}

#endif
