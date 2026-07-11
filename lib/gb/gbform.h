#ifndef GBFORM_H
#define GBFORM_H

/* Bounded GET-form attribute handling. The Browser forwards raw form/input
 * attributes to GBWEB.MOD so this parsing does not consume its app bank. */
#define GB_FORM_CLOSE 0
#define GB_FORM_OPEN  1
#define GB_FORM_INPUT 2

#ifndef GB_FORM_ACTION_MAX
#define GB_FORM_ACTION_MAX 47
#endif
#ifndef GB_FORM_NAME_MAX
#define GB_FORM_NAME_MAX 23
#endif
#ifndef GB_FORM_VALUE_MAX
#define GB_FORM_VALUE_MAX 47
#endif
#ifndef GB_FORM_URL_MAX
#define GB_FORM_URL_MAX 95
#endif

#ifndef GB_FORM_EXTERNAL_STORAGE
static char gb_form_action_storage[GB_FORM_ACTION_MAX + 1];
static char gb_form_name_storage[GB_FORM_NAME_MAX + 1];
static char gb_form_value_storage[GB_FORM_VALUE_MAX + 1];
static char gb_form_url_storage[GB_FORM_URL_MAX + 1];
static unsigned char gb_form_active_storage;
#define GB_FORM_ACTION gb_form_action_storage
#define GB_FORM_NAME   gb_form_name_storage
#define GB_FORM_VALUE  gb_form_value_storage
#define GB_FORM_URL    gb_form_url_storage
#define GB_FORM_ACTIVE gb_form_active_storage
#endif

static unsigned char gb_form_lower(unsigned char c)
{
    if (c >= 'A' && c <= 'Z') c = (unsigned char)(c + ('a' - 'A'));
    return c;
}

static unsigned char gb_form_space(unsigned char c)
{
    return (unsigned char)(c == ' ' || c == '\t' || c == '\r' ||
                           c == '\n' || c == '\f');
}

static unsigned char gb_form_name_char(unsigned char c)
{
    return (unsigned char)((c >= 'a' && c <= 'z') ||
                           (c >= 'A' && c <= 'Z') ||
                           (c >= '0' && c <= '9') || c == '-' ||
                           c == '_' || c == ':');
}

static unsigned char gb_form_equal(const char *s, unsigned char len,
                                   const char *word)
{
    unsigned char i = 0;
    while (word[i]) {
        if (i >= len || gb_form_lower((unsigned char)s[i]) !=
                        (unsigned char)word[i]) return 0;
        i++;
    }
    return (unsigned char)(i == len);
}

static unsigned char gb_form_equal_z(const char *s, const char *word)
{
    unsigned char i = 0;
    while (s[i] && word[i]) {
        if (gb_form_lower((unsigned char)s[i]) != (unsigned char)word[i]) return 0;
        i++;
    }
    return (unsigned char)(!s[i] && !word[i]);
}

/* Return 0 for absent, 1 for copied, or 2 for an oversized value. */
static unsigned char gb_form_attr(const char *p, const char *wanted,
                                  char *out, unsigned char max)
{
    const char *name, *value;
    unsigned char name_len, len, quote, match;
    while (*p) {
        while (*p && (gb_form_space((unsigned char)*p) || *p == '/')) p++;
        if (!*p) break;
        name = p;
        while (gb_form_name_char((unsigned char)*p)) p++;
        name_len = (unsigned char)(p - name);
        if (!name_len) { p++; continue; }
        match = gb_form_equal(name, name_len, wanted);
        while (gb_form_space((unsigned char)*p)) p++;
        if (*p != '=') {
            if (match) return 0;
            continue;
        }
        p++;
        while (gb_form_space((unsigned char)*p)) p++;
        quote = 0;
        if (*p == '\'' || *p == '"') quote = (unsigned char)*p++;
        value = p;
        if (quote) while (*p && (unsigned char)*p != quote) p++;
        else while (*p && !gb_form_space((unsigned char)*p)) p++;
        len = (unsigned char)(p - value);
        if (!quote && len && value[len - 1] == '/') len--;
        if (quote && *p) p++;
        if (match) {
            char *dst = out;
            if (len > max) return 2;
            while (len--) *dst++ = *value++;
            *dst = 0;
            return 1;
        }
    }
    return 0;
}

/* Return 1 only when a usable single-line text input was captured. */
static unsigned char gb_form_process(unsigned char kind, const char *attrs)
{
    unsigned char found;
    if (kind == GB_FORM_CLOSE) {
        GB_FORM_ACTIVE = 0;
        return 0;
    }
    if (kind == GB_FORM_OPEN) {
        GB_FORM_ACTIVE = 0;
        found = gb_form_attr(attrs, "method", GB_FORM_URL, GB_FORM_URL_MAX);
        if (found && (found != 1 || !gb_form_equal_z(GB_FORM_URL, "get"))) return 0;
        found = gb_form_attr(attrs, "action", GB_FORM_ACTION, GB_FORM_ACTION_MAX);
        if (found == 2) return 0;
        if (!found) GB_FORM_ACTION[0] = 0;
        GB_FORM_ACTIVE = 1;
        return 0;
    }
    if (kind != GB_FORM_INPUT || !GB_FORM_ACTIVE) return 0;
    found = gb_form_attr(attrs, "type", GB_FORM_URL, GB_FORM_URL_MAX);
    if (found && (found != 1 || !gb_form_equal_z(GB_FORM_URL, "text"))) {
        if (found == 1 && gb_form_equal_z(GB_FORM_URL, "submit"))
            GB_FORM_ACTIVE = 0;
        return 0;
    }
    if (gb_form_attr(attrs, "name", GB_FORM_NAME, GB_FORM_NAME_MAX) != 1) return 0;
    if (gb_form_attr(attrs, "value", GB_FORM_VALUE, GB_FORM_VALUE_MAX) != 1)
        GB_FORM_VALUE[0] = 0;
    return 1;
}

static unsigned char gb_form_hex(unsigned char n)
{
    n &= 15;
    return (unsigned char)(n < 10 ? '0' + n : 'A' + n - 10);
}

static unsigned char gb_form_build_url(void)
{
    const char *src;
    unsigned char c, n = 0, sep = '?';
#define GB_FORM_PUT(v) do { \
    if (n >= GB_FORM_URL_MAX) { GB_FORM_URL[0] = 0; return 0; } \
    GB_FORM_URL[n++] = (char)(v); \
} while (0)
    if (!GB_FORM_NAME[0]) return 0;
    src = GB_FORM_ACTION;
    while ((c = (unsigned char)*src++) != 0) {
        if (c == '?') sep = '&';
        GB_FORM_PUT(c);
    }
    if (!n || (GB_FORM_URL[n - 1] != '?' && GB_FORM_URL[n - 1] != '&'))
        GB_FORM_PUT(sep);
    src = GB_FORM_NAME;
    while ((c = (unsigned char)*src++) != 0) GB_FORM_PUT(c);
    GB_FORM_PUT('=');
    src = GB_FORM_VALUE;
    while ((c = (unsigned char)*src++) != 0) {
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~')
            GB_FORM_PUT(c);
        else if (c == ' ') GB_FORM_PUT('+');
        else {
            GB_FORM_PUT('%');
            GB_FORM_PUT(gb_form_hex(c >> 4));
            GB_FORM_PUT(gb_form_hex(c));
        }
    }
    GB_FORM_URL[n] = 0;
    return 1;
#undef GB_FORM_PUT
}

#endif
