/* kcfg.h - GEOBENCH config parser (first C kernel module).
 *
 * Pure logic, no I/O: the asm nucleus loads GEOBENCH.CFG off disk and owns the
 * memory; this module just walks the text. See kcfg.c for the semantics it
 * mirrors from the original lib/config.asm.
 */
#ifndef GB_KCFG_H
#define GB_KCFG_H

/* Filename-stem cap for a parsed value (8.3 -> 8 chars), matching the asm. */
#define GB_CFG_VAL_MAX 8

/* gb_cfg_parse: walk `len` bytes of KEY=VALUE text at `buf`. For each known key
 * found at the start of a line, copy its value (up to GB_CFG_VAL_MAX chars,
 * NUL-terminated) into the matching output buffer. Outputs are left untouched
 * when their key is absent, so the caller seeds them with defaults first.
 *
 *   icons_out  <- ICONS=   (>= GB_CFG_VAL_MAX+1 bytes)
 *   font_out   <- FONT=    (>= GB_CFG_VAL_MAX+1 bytes)
 *   cursor_out <- CURSOR=  (>= GB_CFG_VAL_MAX+1 bytes)
 *   inks_out   <- INKS=    (5 bytes: the 4 Mode-1 pens + the border, CPC hardware
 *                           inks 0-26, comma-separated "d,l,k,a,b"; a missing field
 *                           keeps the seeded default for that pen)
 *
 * '#' at the start of a line is a comment; CR (13) and LF (10) end lines.
 */
void gb_cfg_parse(const char *buf, unsigned int len,
                  char *icons_out, char *font_out, char *cursor_out,
                  unsigned char *inks_out);

/* gb_make_83: write an 11-byte AMSDOS 8.3 name into dst (8 chars space-padded +
 * the 3-char extension) from a NUL-terminated stem (<=8 chars used) and ext.
 * e.g. stem "CLASSIC", ext "FNT" -> "CLASSIC FNT". This moves the filename
 * building off the (full) resident kernel and into the paged C module. */
void gb_make_83(const char *stem, const char *ext, char *dst);

/* gb_fmt_mem: write the decimal representation of `kb` followed by 'K' and a NUL
 * into dst (>= 7 bytes); no leading zeros (0 -> "0K"). Mirrors the old asm
 * fmt_mem; division-free, so no SDCC runtime is pulled into the module. */
void gb_fmt_mem(unsigned int kb, char *dst);

#endif /* GB_KCFG_H */
