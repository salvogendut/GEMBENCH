/* kcfg.c - GEOBENCH config parser, the first kernel subsystem ported to C.
 *
 * This is a faithful translation of lib/config.asm's cfg_parse/cfg_keymatch/
 * cfg_copyval. The asm nucleus still does the I/O (fs_load_file of GEOBENCH.CFG)
 * and seeds the defaults; this module is the branchy text-walking logic, which
 * is exactly the kind of code that is clearer and safer in C.
 *
 * Semantics preserved from the asm, exactly:
 *   - Lines are separated by CR (13) or LF (10); blank/extra terminators eaten.
 *   - A '#' at the start of a line is a comment -> the whole line is skipped.
 *   - A key only matches at the start of a line; the match is case-sensitive and
 *     includes the '=' ("ICONS=", "FONT="). The value follows immediately.
 *   - A value is copied up to GB_CFG_VAL_MAX chars, stopping at CR/LF/NUL, and is
 *     NUL-terminated. Unknown lines are skipped. Absent keys leave the output as
 *     the caller seeded it (the default).
 *
 * No libc, no globals: builds the same for the host test harness (gcc) and for
 * the CPC (SDCC -mz80).
 */
#include "kcfg.h"

static char is_eol(char c)
{
    return c == 13 || c == 10;
}

/* match_key: if the line at [p,e) starts with the NUL-terminated `key`, return a
 * pointer to the value (just past the key); otherwise return 0. */
static const char *match_key(const char *p, const char *e, const char *key)
{
    while (*key) {
        if (p >= e || *p != *key)
            return 0;
        ++p;
        ++key;
    }
    return p;
}

/* copy_val: copy the value at [p,e) into dst (max chars), stopping at CR/LF/NUL,
 * then NUL-terminate dst. */
static void copy_val(const char *p, const char *e, char *dst, unsigned char max)
{
    unsigned char n = 0;
    while (n < max && p < e) {
        char c = *p;
        if (c == 0 || is_eol(c))
            break;
        dst[n++] = c;
        ++p;
    }
    dst[n] = 0;
}

/* parse_inks: read up to 5 comma-separated decimal ink numbers (0-26) from the value
 * at [p,e) into out[0..4] (the 4 Mode-1 pens + the border), clamping each to 26. A
 * missing field keeps out's seeded default, so a short "INKS=2" only changes pen 0.
 * Stops at CR/LF/NUL. */
static void parse_inks(const char *p, const char *e, unsigned char *out)
{
    unsigned char i;
    for (i = 0; i < 5; ++i) {
        unsigned int v = 0;
        unsigned char got = 0;
        while (p < e && *p >= '0' && *p <= '9') {
            v = v * 10 + (unsigned int)(*p - '0');
            got = 1;
            ++p;
        }
        if (got)
            out[i] = (unsigned char)(v > 26 ? 26 : v);
        if (p >= e || is_eol(*p))
            break;
        if (*p == ',')
            ++p;
    }
}

void gb_make_83(const char *stem, const char *ext, char *dst)
{
    unsigned char i = 0;
    while (i < 8 && stem[i]) {       /* copy the stem, up to 8 chars */
        dst[i] = stem[i];
        ++i;
    }
    while (i < 8)                     /* space-pad the name field */
        dst[i++] = ' ';
    dst[8]  = ext[0];                 /* 3-char extension */
    dst[9]  = ext[1];
    dst[10] = ext[2];
}

void gb_fmt_mem(unsigned int kb, char *dst)
{
    static const unsigned int pow10[5] = { 10000, 1000, 100, 10, 1 };
    unsigned char i, di = 0, lead = 0;

    for (i = 0; i < 5; ++i) {         /* division-free: repeated subtraction */
        unsigned char d = 0;
        while (kb >= pow10[i]) {
            kb -= pow10[i];
            ++d;
        }
        if (d || lead || i == 4) {    /* suppress leading zeros; always emit units */
            dst[di++] = (char)('0' + d);
            lead = 1;
        }
    }
    dst[di++] = 'K';
    dst[di] = 0;
}

void gb_cfg_parse(const char *buf, unsigned int len,
                  char *icons_out, char *font_out, char *cursor_out,
                  unsigned char *inks_out)
{
    const char *p = buf;
    const char *e = buf + len;
    const char *v;

    while (p < e) {
        char c = *p;
        if (is_eol(c)) {            /* eat line terminators / blank lines */
            ++p;
            continue;
        }
        if (c == '#') {             /* comment: skip the whole line */
            while (p < e && !is_eol(*p))
                ++p;
            continue;
        }

        if ((v = match_key(p, e, "ICONS=")) != 0)
            copy_val(v, e, icons_out, GB_CFG_VAL_MAX);
        else if ((v = match_key(p, e, "FONT=")) != 0)
            copy_val(v, e, font_out, GB_CFG_VAL_MAX);
        else if ((v = match_key(p, e, "CURSOR=")) != 0)
            copy_val(v, e, cursor_out, GB_CFG_VAL_MAX);
        else if ((v = match_key(p, e, "INKS=")) != 0)
            parse_inks(v, e, inks_out);

        while (p < e && !is_eol(*p))  /* advance to the end of this line */
            ++p;
    }
}
