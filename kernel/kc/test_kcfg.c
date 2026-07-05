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
    char cursor[GB_CFG_VAL_MAX + 1];
    char backdrop[GB_CFG_VAL_MAX + 1];
    unsigned char inks[5] = { 1, 26, 0, 6, 1 };
    strcpy(icons, "DEFAULT");
    strcpy(font, "DEFAULT");
    strcpy(cursor, "DEFAULT");
    strcpy(backdrop, "SOLID");

    gb_cfg_parse(cfg, len, icons, font, cursor, backdrop, 0, inks, 0);

    if (strcmp(icons, want_icons) != 0 || strcmp(font, want_font) != 0) {
        printf("FAIL %-28s icons=\"%s\" (want \"%s\")  font=\"%s\" (want \"%s\")\n",
               name, icons, want_icons, font, want_font);
        ++failures;
    } else {
        printf("ok   %-28s icons=\"%s\" font=\"%s\"\n", name, icons, font);
    }
}

#define CHECK(name, lit, wi, wf) check((name), (lit), (unsigned)sizeof(lit) - 1, (wi), (wf))

/* Parse and check the CURSOR= value (defaults to "DEFAULT" when absent). */
static void checkcur(const char *name, const char *cfg, unsigned int len,
                     const char *want_cursor)
{
    char icons[GB_CFG_VAL_MAX + 1], font[GB_CFG_VAL_MAX + 1], cursor[GB_CFG_VAL_MAX + 1];
    char backdrop[GB_CFG_VAL_MAX + 1];
    unsigned char inks[5] = { 1, 26, 0, 6, 1 };
    strcpy(icons, "DEFAULT"); strcpy(font, "DEFAULT"); strcpy(cursor, "DEFAULT"); strcpy(backdrop, "SOLID");
    gb_cfg_parse(cfg, len, icons, font, cursor, backdrop, 0, inks, 0);
    if (strcmp(cursor, want_cursor) != 0) {
        printf("FAIL %-28s cursor=\"%s\" (want \"%s\")\n", name, cursor, want_cursor);
        ++failures;
    } else {
        printf("ok   %-28s cursor=\"%s\"\n", name, cursor);
    }
}
#define CHECKCUR(name, lit, wc) checkcur((name), (lit), (unsigned)sizeof(lit) - 1, (wc))

/* Parse and check the BACKDROP= value (defaults to "SOLID" when absent). */
static void checkbd(const char *name, const char *cfg, unsigned int len, const char *want)
{
    char icons[GB_CFG_VAL_MAX + 1], font[GB_CFG_VAL_MAX + 1], cursor[GB_CFG_VAL_MAX + 1];
    char backdrop[GB_CFG_VAL_MAX + 1];
    unsigned char inks[5] = { 1, 26, 0, 6, 1 };
    strcpy(icons, "DEFAULT"); strcpy(font, "DEFAULT"); strcpy(cursor, "DEFAULT"); strcpy(backdrop, "SOLID");
    gb_cfg_parse(cfg, len, icons, font, cursor, backdrop, 0, inks, 0);
    if (strcmp(backdrop, want) != 0) {
        printf("FAIL %-28s backdrop=\"%s\" (want \"%s\")\n", name, backdrop, want);
        ++failures;
    } else {
        printf("ok   %-28s backdrop=\"%s\"\n", name, backdrop);
    }
}
#define CHECKBD(name, lit, w) checkbd((name), (lit), (unsigned)sizeof(lit) - 1, (w))

static void checkbdpath(const char *name, const char *cfg, unsigned int len,
                        const char *want, unsigned char want_drive)
{
    char icons[GB_CFG_VAL_MAX + 1], font[GB_CFG_VAL_MAX + 1], cursor[GB_CFG_VAL_MAX + 1];
    char backdrop[GB_CFG_VAL_MAX + 1];
    unsigned char drive = GB_CFG_DRIVE_NONE;
    unsigned char inks[5] = { 1, 26, 0, 6, 1 };
    strcpy(icons, "DEFAULT"); strcpy(font, "DEFAULT"); strcpy(cursor, "DEFAULT"); strcpy(backdrop, "SOLID");
    gb_cfg_parse(cfg, len, icons, font, cursor, backdrop, &drive, inks, 0);
    if (strcmp(backdrop, want) != 0 || drive != want_drive) {
        printf("FAIL %-28s backdrop=\"%s\" drive=%u (want \"%s\" drive=%u)\n",
               name, backdrop, drive, want, want_drive);
        ++failures;
    } else {
        printf("ok   %-28s backdrop=\"%s\" drive=%u\n", name, backdrop, drive);
    }
}
#define CHECKBDPATH(name, lit, w, d) checkbdpath((name), (lit), (unsigned)sizeof(lit) - 1, (w), (d))

/* Parse and check the 5 INKS= values (4 pens + border; seeded to 1,26,0,6,1 when
 * absent). */
static void checkinks(const char *name, const char *cfg, unsigned int len,
                      unsigned char d, unsigned char l, unsigned char k,
                      unsigned char a, unsigned char b)
{
    char icons[GB_CFG_VAL_MAX + 1], font[GB_CFG_VAL_MAX + 1], cursor[GB_CFG_VAL_MAX + 1];
    char backdrop[GB_CFG_VAL_MAX + 1];
    unsigned char inks[5] = { 1, 26, 0, 6, 1 };
    strcpy(icons, "DEFAULT"); strcpy(font, "DEFAULT"); strcpy(cursor, "DEFAULT"); strcpy(backdrop, "SOLID");
    gb_cfg_parse(cfg, len, icons, font, cursor, backdrop, 0, inks, 0);
    if (inks[0] != d || inks[1] != l || inks[2] != k || inks[3] != a || inks[4] != b) {
        printf("FAIL %-28s inks=%u,%u,%u,%u,%u (want %u,%u,%u,%u,%u)\n", name,
               inks[0], inks[1], inks[2], inks[3], inks[4], d, l, k, a, b);
        ++failures;
    } else {
        printf("ok   %-28s inks=%u,%u,%u,%u,%u\n", name,
               inks[0], inks[1], inks[2], inks[3], inks[4]);
    }
}
#define CHECKINKS(name, lit, d, l, k, a, b) checkinks((name), (lit), (unsigned)sizeof(lit) - 1, (d), (l), (k), (a), (b))

/* Parse and check DEBUG=TRUE. Only the exact uppercase TRUE value enables it. */
static void checkdebug(const char *name, const char *cfg, unsigned int len,
                       unsigned char want)
{
    char icons[GB_CFG_VAL_MAX + 1], font[GB_CFG_VAL_MAX + 1], cursor[GB_CFG_VAL_MAX + 1];
    char backdrop[GB_CFG_VAL_MAX + 1];
    unsigned char inks[5] = { 1, 26, 0, 6, 1 };
    unsigned char debug = 0;
    strcpy(icons, "DEFAULT"); strcpy(font, "DEFAULT"); strcpy(cursor, "DEFAULT"); strcpy(backdrop, "SOLID");
    gb_cfg_parse(cfg, len, icons, font, cursor, backdrop, 0, inks, &debug);
    if (debug != want) {
        printf("FAIL %-28s debug=%u (want %u)\n", name, debug, want);
        ++failures;
    } else {
        printf("ok   %-28s debug=%u\n", name, debug);
    }
}
#define CHECKDEBUG(name, lit, w) checkdebug((name), (lit), (unsigned)sizeof(lit) - 1, (w))

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

/* gb_fmt_mem formats a KB count as "<decimal>K". */
static void checkmem(const char *name, unsigned int kb, const char *want)
{
    char dst[8];
    gb_fmt_mem(kb, dst);
    if (strcmp(dst, want) != 0) {
        printf("FAIL %-28s got=\"%s\" want=\"%s\"\n", name, dst, want);
        ++failures;
    } else {
        printf("ok   %-28s \"%s\"\n", name, dst);
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

    CHECKCUR("cursor absent",      "ICONS=X\r\n",                   "DEFAULT");
    CHECKCUR("cursor set",         "CURSOR=FANCY\r\n",              "FANCY");
    CHECKCUR("cursor with others", "FONT=F\r\nCURSOR=ARROW\r\nICONS=I\r\n", "ARROW");

    CHECKINKS("inks absent",       "ICONS=X\r\n",                   1, 26, 0, 6, 1);
    CHECKINKS("inks all five",     "INKS=2,13,7,24,5\r\n",          2, 13, 7, 24, 5);
    CHECKINKS("inks clamp >26",    "INKS=99,40,3,27,30\r\n",        26, 26, 3, 26, 26);
    CHECKINKS("inks partial",      "INKS=5\r\n",                    5, 26, 0, 6, 1);
    CHECKINKS("inks four fields",  "INKS=9,11,2,3\r\n",             9, 11, 2, 3, 1);
    CHECKINKS("inks with others",  "FONT=F\r\nINKS=1,2,3,4,7\r\nICONS=I\r\n", 1, 2, 3, 4, 7);

    CHECKDEBUG("debug absent",     "ICONS=X\r\n",                   0);
    CHECKDEBUG("debug true",       "DEBUG=TRUE\r\n",                1);
    CHECKDEBUG("debug false",      "DEBUG=FALSE\r\n",               0);
    CHECKDEBUG("debug exact true", "DEBUG=TRUEISH\r\n",             0);

    CHECKBD("backdrop absent",     "ICONS=X\r\n",                   "SOLID");
    CHECKBD("backdrop set",        "BACKDROP=WAVES\r\n",            "WAVES");
    CHECKBD("backdrop with others","FONT=F\r\nBACKDROP=DOTS\r\nINKS=1,2,3,4,5\r\n", "DOTS");
    CHECKBDPATH("backdrop bare ext", "BACKDROP=WAVES.BDP\r\n",       "WAVES", GB_CFG_DRIVE_NONE);
    CHECKBDPATH("backdrop drive",   "BACKDROP=A:WAVES\r\n",          "WAVES", 1);
    CHECKBDPATH("backdrop drive ext","BACKDROP=A:WAVES.BDP\r\n",      "WAVES", 1);
    CHECKBDPATH("backdrop solid",   "BACKDROP=SOLID\r\n",            "SOLID", GB_CFG_DRIVE_NONE);

    check83("make83 default",  "DEFAULT", "FNT", "DEFAULT FNT");
    check83("make83 cursor",   "FANCY",   "SPR", "FANCY   SPR");
    check83("make83 short",    "AA",      "IST", "AA      IST");
    check83("make83 full 8",   "ABCDEFGH","FNT", "ABCDEFGHFNT");
    check83("make83 empty",    "",        "IST", "        IST");

    checkmem("mem 0",      0,     "0K");
    checkmem("mem 64",     64,    "64K");
    checkmem("mem 128",    128,   "128K");
    checkmem("mem 256",    256,   "256K");
    checkmem("mem 576",    576,   "576K");
    checkmem("mem 1024",   1024,  "1024K");
    checkmem("mem 9",      9,     "9K");
    checkmem("mem 10000",  10000, "10000K");

    if (failures) {
        printf("\n%d test(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall tests passed\n");
    return 0;
}
