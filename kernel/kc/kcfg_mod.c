/* kcfg_mod.c - loadable wrapper that runs the config parser as a kernel module.
 *
 * The kernel loads this image into a bank page at #4000 (like an app) and CALLs
 * it through crt0's _start. It is the concrete realisation of the asm-nucleus +
 * paged-C-module design (issue #30): the parser logic runs paged-in, while all
 * I/O is through a fixed transfer area in low RAM that stays main RAM under
 * banking (so it is reachable while this code is paged into the window).
 *
 * The module owns the whole config-to-filename job (defaults, parse, 8.3 build),
 * so the resident kernel only has to `ldir` the finished names. The kernel fills
 * the input before the call and reads the outputs after:
 *   #1000  cfg text (<=512 bytes, the GEOBENCH.CFG contents)
 *   #1200  length   (word: number of cfg-text bytes; 0 = no file)
 *   #1202  ICONS filename out (11-byte 8.3, e.g. "DEFAULT IST")
 *   #120D  FONT  filename out (11-byte 8.3, e.g. "DEFAULT FNT")
 *
 * Using fixed addresses (not function args) means crt0 can enter with a plain
 * `call _main` - no inter-bank argument-passing ABI to hand-roll in asm.
 */
#include "kcfg.h"

#define KCFG_TEXT      ((const char *)0x1000)
#define KCFG_LEN       (*(unsigned int *)0x1200)
#define KCFG_ICONNAME  ((char *)0x1202)
#define KCFG_FONTNAME  ((char *)0x120D)
#define KCFG_MEMKB     (*(unsigned int *)0x1218)   /* in:  total RAM in KB */
#define KCFG_MEMSTR    ((char *)0x121A)            /* out: "<decimal>K" string */
#define KCFG_CURSORNAME ((char *)0x1221)           /* out: CURSOR filename (11-byte 8.3) */
#define KCFG_INKS      ((unsigned char *)0x122C)   /* out: 4 pen inks + border (INKS=) */

static void set_default(char *stem)     /* "DEFAULT" + NUL */
{
    stem[0] = 'D'; stem[1] = 'E'; stem[2] = 'F'; stem[3] = 'A';
    stem[4] = 'U'; stem[5] = 'L'; stem[6] = 'T'; stem[7] = 0;
}

void main(void)
{
    char icons[9];
    char font[9];
    char cursor[9];

    set_default(icons);                 /* absent keys keep the default */
    set_default(font);
    set_default(cursor);
    KCFG_INKS[0] = 1;  KCFG_INKS[1] = 26;   /* default palette: blue/white/black/red, */
    KCFG_INKS[2] = 0;  KCFG_INKS[3] = 6;    /* blue border (matches set_palette's seed) */
    KCFG_INKS[4] = 1;
    gb_cfg_parse(KCFG_TEXT, KCFG_LEN, icons, font, cursor, KCFG_INKS);
    gb_make_83(icons,  "IST", KCFG_ICONNAME);
    gb_make_83(font,   "FNT", KCFG_FONTNAME);
    gb_make_83(cursor, "SPR", KCFG_CURSORNAME);
    gb_fmt_mem(KCFG_MEMKB, KCFG_MEMSTR);    /* top-bar RAM string */
}
