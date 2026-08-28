/* gbsavercfg.h - low-RAM contract for per-screensaver configuration modules.
 *
 * Settings derives <stem>.MOD from SAVER=<stem>.SAV and invokes it through the
 * existing arbitrary GB_UI module path. The app page is swapped out while the
 * module runs, so inputs and results live in the resident UI transfer block.
 *
 * A module reads KCFG_TEXT/KCFG_LEN, sets GB_SSCFG_RESULT to CANCEL or SAVE,
 * and, on SAVE, emits NUL-separated key/value pairs followed by an empty key:
 *
 *   "KEY1=\0value\0KEY2=\0value\0\0"
 *
 * Settings copies this block back into its app page before writing the config;
 * file-save modules are allowed to reuse the low-RAM UI area. */
#ifndef GBSAVERCFG_H
#define GBSAVERCFG_H

#define GB_SSCFG_OP       (*(volatile unsigned char *)0x1700)
#define GB_SSCFG_RESULT   (*(volatile unsigned char *)0x1704)
#define GB_SSCFG_MODAL    (*(volatile unsigned char *)0x1705)
#define GB_SSCFG_TEXT     ((char *)0x1718)
/* Three current numeric settings occupy 54 bytes including both terminators.
 * Keep the transfer bounded and small enough for Settings' tight app page. */
#define GB_SSCFG_TEXT_CAP 64
#define GB_SSCFG_MODNAME  ((char *)0x3914)

#define GB_SSCFG_CONFIG   ((const char *)0x1000)
#define GB_SSCFG_CFGLEN   (*(volatile unsigned int *)0x1200)

#define GB_SSCFG_OP_CONFIG 26
#define GB_SSCFG_CANCEL     0
#define GB_SSCFG_SAVE       1
#define GB_SSCFG_MISSING    0xFF

static char *gb_sscfg_emit_u8(char *dst, const char *key, unsigned char value)
{
    while (*key) *dst++ = *key++;
    *dst++ = 0;
    if (value >= 100) {
        *dst++ = (char)('0' + value / 100);
        value %= 100;
        *dst++ = (char)('0' + value / 10);
    } else if (value >= 10) {
        *dst++ = (char)('0' + value / 10);
    }
    *dst++ = (char)('0' + value % 10);
    *dst++ = 0;
    return dst;
}

#endif
