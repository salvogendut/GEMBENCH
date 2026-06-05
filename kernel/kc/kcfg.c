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

void gb_cfg_parse(const char *buf, unsigned int len,
                  char *icons_out, char *font_out)
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

        while (p < e && !is_eol(*p))  /* advance to the end of this line */
            ++p;
    }
}
