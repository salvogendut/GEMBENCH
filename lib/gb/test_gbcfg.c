#include <stdio.h>
#include <string.h>

#define GBCFG_HOST_TEST
#include "gbcfg.h"

static int failures;

static void check(const char *name, const char *cfg, const char *key,
                  unsigned char defval, unsigned char minval,
                  unsigned char maxval, unsigned char expected)
{
    unsigned char got = gbcfg_u8_from(cfg, (unsigned int)strlen(cfg), key,
                                      defval, minval, maxval);
    if (got != expected) {
        printf("FAIL %-30s got %u expected %u\n", name, got, expected);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

int main(void)
{
    check("missing key", "SAVER=STARFLD\r\n", "STARFLD_SPEED=", 4, 1, 8, 4);
    check("valid value", "STARFLD_SPEED=7\r\n", "STARFLD_SPEED=", 4, 1, 8, 7);
    check("line start required", "XSTARFLD_SPEED=2\r\n", "STARFLD_SPEED=", 4, 1, 8, 4);
    check("empty value", "STARFLD_SPEED=\r\n", "STARFLD_SPEED=", 4, 1, 8, 4);
    check("trailing garbage", "STARFLD_SPEED=6X\r\n", "STARFLD_SPEED=", 4, 1, 8, 4);
    check("below range", "STARFLD_SPEED=0\r\n", "STARFLD_SPEED=", 4, 1, 8, 4);
    check("above range", "STARFLD_SPEED=9\r\n", "STARFLD_SPEED=", 4, 1, 8, 4);
    check("byte overflow", "STARFLD_SPEED=260\r\n", "STARFLD_SPEED=", 4, 1, 8, 4);
    check("last repeated value wins",
          "STARFLD_SPEED=2\r\nSTARFLD_SPEED=8\r\n",
          "STARFLD_SPEED=", 4, 1, 8, 8);
    check("last invalid value defaults",
          "STARFLD_SPEED=2\r\nSTARFLD_SPEED=99\r\n",
          "STARFLD_SPEED=", 4, 1, 8, 4);
    check("star count", "STARFLD_STARS=96\n", "STARFLD_STARS=", 64, 16, 96, 96);

    if (failures) return 1;
    puts("\nall app config tests passed");
    return 0;
}
