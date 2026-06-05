/* kcfg_mod.c - loadable wrapper that runs the config parser as a kernel module.
 *
 * The kernel loads this image into a bank page at #4000 (like an app) and CALLs
 * it through crt0's _start. It is the concrete realisation of the asm-nucleus +
 * paged-C-module design (issue #30): the parser logic runs paged-in, while all
 * I/O is through a fixed transfer area in low RAM that stays main RAM under
 * banking (so it is reachable while this code is paged into the window).
 *
 * The kernel fills the area before the call and reads it after:
 *   #1000  cfg text (<=512 bytes, the GEOBENCH.CFG contents)
 *   #1200  length   (word: number of cfg-text bytes; 0 = no file)
 *   #1202  ICONS out (9 bytes, seeded with the default, NUL-terminated)
 *   #120C  FONT  out (9 bytes, seeded with the default, NUL-terminated)
 *
 * Using fixed addresses (not function args) means crt0 can enter with a plain
 * `call _main` - no inter-bank argument-passing ABI to hand-roll in asm.
 */
#include "kcfg.h"

#define KCFG_TEXT   ((const char *)0x1000)
#define KCFG_LEN    (*(unsigned int *)0x1200)
#define KCFG_ICONS  ((char *)0x1202)
#define KCFG_FONT   ((char *)0x120C)

void main(void)
{
    gb_cfg_parse(KCFG_TEXT, KCFG_LEN, KCFG_ICONS, KCFG_FONT);
}
