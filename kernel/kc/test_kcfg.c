/* test_kcfg.c - host (gcc) parity tests for the C config parser.
 *
 * Every case here encodes a behavior of the original lib/config.asm so we can be
 * sure the C port is byte-for-byte equivalent before the asm is retired. Build
 * and run with kernel/kc/run_tests.sh.
 */
#include <stdio.h>
#include <string.h>
#include "kcfg.h"

static int failures = 0;

/* Seed defaults like the asm cfg_load does, parse, and check both outputs. */
static void check(const char *name, const char *cfg, unsigned int len,
                  const char *want_icons, const char *want_font)
{
    char icons[GB_CFG_VAL_MAX + 1];
    char font[GB_CFG_VAL_MAX + 1];
    strcpy(icons, "DEFAULT");
    strcpy(font, "DEFAULT");

    gb_cfg_parse(cfg, len, icons, font);

    if (strcmp(icons, want_icons) != 0 || strcmp(font, want_font) != 0) {
        printf("FAIL %-28s icons=\"%s\" (want \"%s\")  font=\"%s\" (want \"%s\")\n",
               name, icons, want_icons, font, want_font);
        ++failures;
    } else {
        printf("ok   %-28s icons=\"%s\" font=\"%s\"\n", name, icons, font);
    }
}

#define CHECK(name, lit, wi, wf) check((name), (lit), (unsigned)sizeof(lit) - 1, (wi), (wf))

/* gb_make_83 builds an 11-byte 8.3 name; compare against an explicit literal
 * (which includes the space padding). */
static void check83(const char *name, const char *stem, const char *ext,
                    const char *want11)
{
    char dst[11];
    gb_make_83(stem, ext, dst);
    if (memcmp(dst, want11, 11) != 0) {
        printf("FAIL %-28s got=\"%.11s\" want=\"%.11s\"\n", name, dst, want11);
        ++failures;
    } else {
        printf("ok   %-28s \"%.11s\"\n", name, dst);
    }
}

int main(void)
{
    CHECK("empty",                 "",                              "DEFAULT", "DEFAULT");
    CHECK("comment only",          "# just a comment\r\n",          "DEFAULT", "DEFAULT");
    CHECK("both keys crlf",        "ICONS=CLASSIC\r\nFONT=BIG\r\n", "CLASSIC", "BIG");
    CHECK("lf only endings",       "ICONS=MONO\nFONT=TINY\n",       "MONO",    "TINY");
    CHECK("no trailing newline",   "ICONS=MONO",                    "MONO",    "DEFAULT");
    CHECK("8 char cap",            "ICONS=ABCDEFGHIJK\r\n",         "ABCDEFGH","DEFAULT");
    CHECK("comment then key",      "# hi\r\nFONT=TINY\r\n",         "DEFAULT", "TINY");
    CHECK("unknown key ignored",   "FOO=BAR\r\nICONS=X\r\n",        "X",       "DEFAULT");
    CHECK("key not at line start", "X ICONS=NO\r\n",                "DEFAULT", "DEFAULT");
    CHECK("empty value",           "ICONS=\r\n",                    "",        "DEFAULT");
    CHECK("blank lines",           "\r\n\r\nFONT=Z\r\n",            "DEFAULT", "Z");
    CHECK("repeated key last wins","ICONS=A\r\nICONS=B\r\n",        "B",       "DEFAULT");
    CHECK("font then icons",       "FONT=F1\r\nICONS=I1\r\n",       "I1",      "F1");
    CHECK("crlf mixed with lf",    "ICONS=AA\nFONT=BB\r\n",         "AA",      "BB");

    check83("make83 default",  "DEFAULT", "FNT", "DEFAULT FNT");
    check83("make83 short",    "AA",      "IST", "AA      IST");
    check83("make83 full 8",   "ABCDEFGH","FNT", "ABCDEFGHFNT");
    check83("make83 empty",    "",        "IST", "        IST");

    if (failures) {
        printf("\n%d test(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall tests passed\n");
    return 0;
}
