#ifndef GBHTML_H
#define GBHTML_H

/* Small streaming HTML subset for a text-first GEOBENCH browser.
 *
 * This is a tokenizer/layout front end, not a DOM.  It retains at most one
 * bounded tag, entity, URL and image-alt value and emits content immediately
 * through compile-time callbacks.  Applications may provide their own buffers
 * by defining GB_HTML_EXTERNAL_STORAGE and the four GB_HTML_*_BUFFER names.
 */

#ifndef GB_HTML_TAG_MAX
#define GB_HTML_TAG_MAX 111
#endif
#ifndef GB_HTML_URL_MAX
#define GB_HTML_URL_MAX 95
#endif
#ifndef GB_HTML_ALT_MAX
#define GB_HTML_ALT_MAX 63
#endif
#ifndef GB_HTML_ENTITY_MAX
#define GB_HTML_ENTITY_MAX 9
#endif

#define GB_HTML_BREAK_LINE  1
#define GB_HTML_BREAK_BLOCK 2

#ifndef GB_HTML_EMIT_TEXT
#define GB_HTML_EMIT_TEXT(c) ((void)0)
#endif
#ifndef GB_HTML_EMIT_TITLE
#define GB_HTML_EMIT_TITLE(c) ((void)0)
#endif
#ifndef GB_HTML_EMIT_BREAK
#define GB_HTML_EMIT_BREAK(kind) ((void)0)
#endif
#ifndef GB_HTML_LINK_BEGIN
#define GB_HTML_LINK_BEGIN(url) ((void)0)
#endif
#ifndef GB_HTML_LINK_END
#define GB_HTML_LINK_END() ((void)0)
#endif
#ifndef GB_HTML_IMAGE_ALT
#define GB_HTML_IMAGE_ALT(alt) ((void)0)
#endif

#ifndef GB_HTML_EXTERNAL_STORAGE
static char gb_html_tag_buffer[GB_HTML_TAG_MAX + 1];
static char gb_html_url_buffer[GB_HTML_URL_MAX + 1];
static char gb_html_alt_buffer[GB_HTML_ALT_MAX + 1];
static char gb_html_entity_buffer[GB_HTML_ENTITY_MAX + 1];
#else
#ifndef GB_HTML_TAG_BUFFER
#error "GB_HTML_TAG_BUFFER must name the tag buffer"
#endif
#ifndef GB_HTML_URL_BUFFER
#error "GB_HTML_URL_BUFFER must name the URL buffer"
#endif
#ifndef GB_HTML_ALT_BUFFER
#error "GB_HTML_ALT_BUFFER must name the image-alt buffer"
#endif
#ifndef GB_HTML_ENTITY_BUFFER
#error "GB_HTML_ENTITY_BUFFER must name the entity buffer"
#endif
#define gb_html_tag_buffer GB_HTML_TAG_BUFFER
#define gb_html_url_buffer GB_HTML_URL_BUFFER
#define gb_html_alt_buffer GB_HTML_ALT_BUFFER
#define gb_html_entity_buffer GB_HTML_ENTITY_BUFFER
#endif

#define GB_HTML_ST_TEXT    0
#define GB_HTML_ST_TAG     1
#define GB_HTML_ST_ENTITY  2
#define GB_HTML_ST_COMMENT 3

#define GB_HTML_SKIP_NONE   0
#define GB_HTML_SKIP_SCRIPT 1
#define GB_HTML_SKIP_STYLE  2

static unsigned char gb_html_state;
static unsigned char gb_html_tag_len;
static unsigned char gb_html_tag_overflow;
static unsigned char gb_html_quote;
static unsigned char gb_html_comment_dash;
static unsigned char gb_html_entity_len;
static unsigned char gb_html_pending_space;
static unsigned char gb_html_have_text;
static unsigned char gb_html_last_break;
static unsigned char gb_html_title_pending;
static unsigned char gb_html_title_have;
static unsigned char gb_html_in_title;
static unsigned char gb_html_in_pre;
static unsigned char gb_html_in_link;
static unsigned char gb_html_skip;
static unsigned char gb_html_skip_pos;

static unsigned char gb_html_lower(unsigned char c)
{
    if (c >= 'A' && c <= 'Z') c = (unsigned char)(c + ('a' - 'A'));
    return c;
}

static unsigned char gb_html_space(unsigned char c)
{
    return (unsigned char)(c == ' ' || c == '\t' || c == '\r' ||
                           c == '\n' || c == '\f');
}

static unsigned char gb_html_name_char(unsigned char c)
{
    return (unsigned char)((c >= 'a' && c <= 'z') ||
                           (c >= 'A' && c <= 'Z') ||
                           (c >= '0' && c <= '9') || c == '-' ||
                           c == '_' || c == ':');
}

static unsigned char gb_html_equal(const char *s, unsigned char len,
                                   const char *word)
{
    unsigned char i = 0;
    while (word[i]) {
        if (i >= len || gb_html_lower((unsigned char)s[i]) !=
                        (unsigned char)word[i]) return 0;
        i++;
    }
    return (unsigned char)(i == len);
}

static void gb_html_emit_break(unsigned char kind)
{
    if (gb_html_have_text || !gb_html_last_break) GB_HTML_EMIT_BREAK(kind);
    gb_html_pending_space = 0;
    gb_html_have_text = 0;
    gb_html_last_break = 1;
}

static void gb_html_emit_char(unsigned char c)
{
    if (gb_html_in_title) {
        if (gb_html_space(c)) {
            if (gb_html_title_have) gb_html_title_pending = 1;
            return;
        }
        if (gb_html_title_pending && gb_html_title_have) GB_HTML_EMIT_TITLE(' ');
        gb_html_title_pending = 0;
        gb_html_title_have = 1;
        GB_HTML_EMIT_TITLE(c);
        return;
    }
    if (gb_html_in_pre) {
        if (c == '\r') return;
        if (c == '\n') { gb_html_emit_break(GB_HTML_BREAK_LINE); return; }
        if (c == '\t') c = ' ';
        GB_HTML_EMIT_TEXT(c);
        gb_html_have_text = 1;
        gb_html_last_break = 0;
        return;
    }
    if (gb_html_space(c)) {
        if (gb_html_have_text) gb_html_pending_space = 1;
        return;
    }
    if (gb_html_pending_space && gb_html_have_text) GB_HTML_EMIT_TEXT(' ');
    gb_html_pending_space = 0;
    GB_HTML_EMIT_TEXT(c);
    gb_html_have_text = 1;
    gb_html_last_break = 0;
}

static unsigned char gb_html_entity_value(const char *text, unsigned char len,
                                          unsigned char *value)
{
    unsigned int v = 0;
    unsigned char i = 0, base = 10, digit, have = 0;
    if (gb_html_equal(text, len, "amp")) { *value = '&'; return 1; }
    if (gb_html_equal(text, len, "lt")) { *value = '<'; return 1; }
    if (gb_html_equal(text, len, "gt")) { *value = '>'; return 1; }
    if (gb_html_equal(text, len, "quot")) { *value = '"'; return 1; }
    if (gb_html_equal(text, len, "apos")) { *value = '\''; return 1; }
    if (gb_html_equal(text, len, "nbsp")) { *value = ' '; return 1; }
    if (!len || text[0] != '#') return 0;
    i = 1;
    if (i < len && (text[i] == 'x' || text[i] == 'X')) { base = 16; i++; }
    while (i < len) {
        unsigned char c = (unsigned char)text[i++];
        if (c >= '0' && c <= '9') digit = (unsigned char)(c - '0');
        else if (base == 16 && gb_html_lower(c) >= 'a' &&
                 gb_html_lower(c) <= 'f')
            digit = (unsigned char)(gb_html_lower(c) - 'a' + 10);
        else return 0;
        if (digit >= base) return 0;
        if (base == 16) {
            if (v > 15) return 0;
            v = (unsigned int)((v << 4) + digit);
        } else {
            if (v > 25 || (v == 25 && digit > 5)) return 0;
            v = (unsigned int)(v * 10 + digit);
        }
        have = 1;
    }
    if (!have || !v) return 0;
    *value = (unsigned char)v;
    return 1;
}

static unsigned char gb_html_decode_attr(char *text, unsigned char len)
{
    unsigned char in = 0, out = 0, end, value;
    while (in < len) {
        if (text[in] == '&') {
            end = (unsigned char)(in + 1);
            while (end < len && text[end] != ';' &&
                   (unsigned char)(end - in) <= GB_HTML_ENTITY_MAX) end++;
            if (end < len && text[end] == ';' &&
                gb_html_entity_value(text + in + 1,
                                     (unsigned char)(end - in - 1), &value)) {
                text[out++] = (char)value;
                in = (unsigned char)(end + 1);
                continue;
            }
        }
        text[out++] = text[in++];
    }
    text[out] = 0;
    return out;
}

static unsigned char gb_html_attr(unsigned char start, const char *wanted,
                                  char *out, unsigned char max)
{
    unsigned char i = start, name, name_len, value, len, quote, match;
    while (i < gb_html_tag_len) {
        while (i < gb_html_tag_len &&
               (gb_html_space((unsigned char)gb_html_tag_buffer[i]) ||
                gb_html_tag_buffer[i] == '/')) i++;
        name = i;
        while (i < gb_html_tag_len &&
               gb_html_name_char((unsigned char)gb_html_tag_buffer[i])) i++;
        name_len = (unsigned char)(i - name);
        if (!name_len) { i++; continue; }
        match = gb_html_equal(gb_html_tag_buffer + name, name_len, wanted);
        while (i < gb_html_tag_len &&
               gb_html_space((unsigned char)gb_html_tag_buffer[i])) i++;
        if (i >= gb_html_tag_len || gb_html_tag_buffer[i] != '=') {
            if (match) return 0;
            continue;
        }
        i++;
        while (i < gb_html_tag_len &&
               gb_html_space((unsigned char)gb_html_tag_buffer[i])) i++;
        quote = 0;
        if (i < gb_html_tag_len &&
            (gb_html_tag_buffer[i] == '\'' || gb_html_tag_buffer[i] == '"'))
            quote = (unsigned char)gb_html_tag_buffer[i++];
        value = i;
        if (quote) while (i < gb_html_tag_len &&
                         (unsigned char)gb_html_tag_buffer[i] != quote) i++;
        else while (i < gb_html_tag_len &&
                    !gb_html_space((unsigned char)gb_html_tag_buffer[i])) i++;
        len = (unsigned char)(i - value);
        if (!quote && len && i == gb_html_tag_len &&
            gb_html_tag_buffer[i - 1] == '/') len--;
        if (quote && i < gb_html_tag_len) i++;
        if (match) {
            unsigned char n;
            if (len > max) return 2;
            for (n = 0; n < len; n++) out[n] = gb_html_tag_buffer[value + n];
            out[len] = 0;
            gb_html_decode_attr(out, len);
            return 1;
        }
    }
    return 0;
}

static unsigned char gb_html_block_tag(const char *name, unsigned char len)
{
    if (gb_html_equal(name, len, "p") || gb_html_equal(name, len, "div") ||
        gb_html_equal(name, len, "li") || gb_html_equal(name, len, "ul") ||
        gb_html_equal(name, len, "ol") || gb_html_equal(name, len, "tr")) return 1;
    return (unsigned char)(len == 2 && gb_html_lower((unsigned char)name[0]) == 'h' &&
                           name[1] >= '1' && name[1] <= '6');
}

static void gb_html_emit_alt(const char *value)
{
    if (*value) {
        if (gb_html_pending_space && gb_html_have_text) GB_HTML_EMIT_TEXT(' ');
        GB_HTML_IMAGE_ALT(value);
        gb_html_have_text = 1;
        gb_html_last_break = 0;
        gb_html_pending_space = 0;
    }
}

static void gb_html_process_tag(void)
{
    unsigned char i = 0, end = 0, name, len, self_close = 0, attr;
    while (i < gb_html_tag_len &&
           gb_html_space((unsigned char)gb_html_tag_buffer[i])) i++;
    if (i < gb_html_tag_len && gb_html_tag_buffer[i] == '/') { end = 1; i++; }
    while (i < gb_html_tag_len &&
           gb_html_space((unsigned char)gb_html_tag_buffer[i])) i++;
    name = i;
    while (i < gb_html_tag_len &&
           gb_html_name_char((unsigned char)gb_html_tag_buffer[i])) i++;
    len = (unsigned char)(i - name);
    if (!len || gb_html_tag_buffer[name] == '!') return;
    if (gb_html_tag_len) {
        unsigned char tail = gb_html_tag_len;
        while (tail && gb_html_space((unsigned char)gb_html_tag_buffer[tail - 1])) tail--;
        if (tail && gb_html_tag_buffer[tail - 1] == '/') self_close = 1;
    }

    if (end) {
        if (gb_html_equal(gb_html_tag_buffer + name, len, "a") && gb_html_in_link) {
            GB_HTML_LINK_END();
            gb_html_in_link = 0;
        } else if (gb_html_equal(gb_html_tag_buffer + name, len, "title")) {
            gb_html_in_title = 0;
            gb_html_title_pending = 0;
        } else if (gb_html_equal(gb_html_tag_buffer + name, len, "pre")) {
            gb_html_in_pre = 0;
            gb_html_emit_break(GB_HTML_BREAK_BLOCK);
        } else if (gb_html_block_tag(gb_html_tag_buffer + name, len)) {
            gb_html_emit_break(GB_HTML_BREAK_BLOCK);
        }
        return;
    }

    if (gb_html_equal(gb_html_tag_buffer + name, len, "script")) {
        gb_html_skip = GB_HTML_SKIP_SCRIPT; gb_html_skip_pos = 0; return;
    }
    if (gb_html_equal(gb_html_tag_buffer + name, len, "style")) {
        gb_html_skip = GB_HTML_SKIP_STYLE; gb_html_skip_pos = 0; return;
    }
    if (gb_html_equal(gb_html_tag_buffer + name, len, "title")) {
        gb_html_in_title = 1;
        gb_html_title_pending = gb_html_title_have = 0;
        return;
    }
    if (gb_html_equal(gb_html_tag_buffer + name, len, "br")) {
        gb_html_emit_break(GB_HTML_BREAK_LINE); return;
    }
    if (gb_html_equal(gb_html_tag_buffer + name, len, "pre")) {
        gb_html_emit_break(GB_HTML_BREAK_BLOCK);
        gb_html_in_pre = 1;
        return;
    }
    if (gb_html_equal(gb_html_tag_buffer + name, len, "a")) {
        if (gb_html_in_link) GB_HTML_LINK_END();
        attr = gb_html_attr(i, "href", gb_html_url_buffer, GB_HTML_URL_MAX);
        gb_html_in_link = (unsigned char)(attr == 1);
        if (gb_html_in_link) GB_HTML_LINK_BEGIN(gb_html_url_buffer);
        if (self_close && gb_html_in_link) {
            GB_HTML_LINK_END(); gb_html_in_link = 0;
        }
        return;
    }
    if (gb_html_equal(gb_html_tag_buffer + name, len, "img")) {
        attr = gb_html_attr(i, "alt", gb_html_alt_buffer, GB_HTML_ALT_MAX);
        if (attr == 1) gb_html_emit_alt(gb_html_alt_buffer);
        return;
    }
    if (gb_html_block_tag(gb_html_tag_buffer + name, len)) {
        gb_html_emit_break(GB_HTML_BREAK_BLOCK);
        if (gb_html_equal(gb_html_tag_buffer + name, len, "li")) {
            gb_html_emit_char('*'); gb_html_emit_char(' ');
        }
    }
}

static void gb_html_reset(void)
{
    gb_html_state = GB_HTML_ST_TEXT;
    gb_html_tag_len = gb_html_tag_overflow = gb_html_quote = 0;
    gb_html_comment_dash = gb_html_entity_len = 0;
    gb_html_pending_space = gb_html_have_text = 0;
    gb_html_last_break = 1;
    gb_html_title_pending = gb_html_title_have = gb_html_in_title = 0;
    gb_html_in_pre = gb_html_in_link = 0;
    gb_html_skip = gb_html_skip_pos = 0;
}

static void gb_html_feed_byte(unsigned char c)
{
    unsigned char value, i;
    const char *skip_text;

    if (gb_html_skip) {
        skip_text = gb_html_skip == GB_HTML_SKIP_SCRIPT ? "</script>" : "</style>";
        if (gb_html_lower(c) == (unsigned char)skip_text[gb_html_skip_pos]) {
            gb_html_skip_pos++;
            if (!skip_text[gb_html_skip_pos]) {
                gb_html_skip = gb_html_skip_pos = 0;
            }
        } else gb_html_skip_pos = (unsigned char)(c == '<');
        return;
    }

    if (gb_html_state == GB_HTML_ST_COMMENT) {
        if (c == '-') { if (gb_html_comment_dash < 2) gb_html_comment_dash++; }
        else if (c == '>' && gb_html_comment_dash == 2) {
            gb_html_state = GB_HTML_ST_TEXT;
            gb_html_comment_dash = 0;
        } else gb_html_comment_dash = 0;
        return;
    }

    if (gb_html_state == GB_HTML_ST_TAG) {
        if (gb_html_quote) {
            if (c == gb_html_quote) gb_html_quote = 0;
        } else if (c == '\'' || c == '"') gb_html_quote = c;
        else if (c == '>') {
            if (!gb_html_tag_overflow) {
                gb_html_tag_buffer[gb_html_tag_len] = 0;
                gb_html_process_tag();
            }
            gb_html_state = GB_HTML_ST_TEXT;
            gb_html_tag_len = gb_html_tag_overflow = gb_html_quote = 0;
            return;
        }
        if (gb_html_tag_len < GB_HTML_TAG_MAX)
            gb_html_tag_buffer[gb_html_tag_len++] = (char)c;
        else gb_html_tag_overflow = 1;
        if (!gb_html_quote && gb_html_tag_len == 3 &&
            gb_html_tag_buffer[0] == '!' && gb_html_tag_buffer[1] == '-' &&
            gb_html_tag_buffer[2] == '-') {
            gb_html_state = GB_HTML_ST_COMMENT;
            gb_html_comment_dash = 0;
        }
        return;
    }

    if (gb_html_state == GB_HTML_ST_ENTITY) {
        if (c == ';') {
            if (gb_html_entity_value(gb_html_entity_buffer, gb_html_entity_len,
                                     &value)) gb_html_emit_char(value);
            else {
                gb_html_emit_char('&');
                for (i = 0; i < gb_html_entity_len; i++)
                    gb_html_emit_char((unsigned char)gb_html_entity_buffer[i]);
                gb_html_emit_char(';');
            }
            gb_html_state = GB_HTML_ST_TEXT;
            gb_html_entity_len = 0;
            return;
        }
        if (gb_html_name_char(c) || c == '#') {
            if (gb_html_entity_len < GB_HTML_ENTITY_MAX)
                gb_html_entity_buffer[gb_html_entity_len++] = (char)c;
            else {
                gb_html_emit_char('&');
                for (i = 0; i < gb_html_entity_len; i++)
                    gb_html_emit_char((unsigned char)gb_html_entity_buffer[i]);
                gb_html_emit_char(c);
                gb_html_state = GB_HTML_ST_TEXT;
                gb_html_entity_len = 0;
            }
            return;
        }
        gb_html_emit_char('&');
        for (i = 0; i < gb_html_entity_len; i++)
            gb_html_emit_char((unsigned char)gb_html_entity_buffer[i]);
        gb_html_state = GB_HTML_ST_TEXT;
        gb_html_entity_len = 0;
    }

    if (c == '<') {
        gb_html_state = GB_HTML_ST_TAG;
        gb_html_tag_len = gb_html_tag_overflow = gb_html_quote = 0;
    } else if (c == '&') {
        gb_html_state = GB_HTML_ST_ENTITY;
        gb_html_entity_len = 0;
    } else gb_html_emit_char(c);
}

static void gb_html_feed(const unsigned char *data, unsigned int len)
{
    while (len--) gb_html_feed_byte(*data++);
}

static void gb_html_end(void)
{
    unsigned char i;
    if (gb_html_state == GB_HTML_ST_ENTITY) {
        gb_html_emit_char('&');
        for (i = 0; i < gb_html_entity_len; i++)
            gb_html_emit_char((unsigned char)gb_html_entity_buffer[i]);
    }
    if (gb_html_in_link) GB_HTML_LINK_END();
    gb_html_state = GB_HTML_ST_TEXT;
    gb_html_in_link = gb_html_in_title = 0;
}

#endif
