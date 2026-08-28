/* apps/savdraw.h - MSX2 drawing primitives for the #C000 screensavers (#287).
 *
 * The savers were written for the CPC's memory-mapped #C000 Mode-1 screen
 * (vram_pixel / vram_line). MSX2 Screen 6 has no such screen, so on MSX these
 * draw through the V9938 hardware LINE command (GB_LINE #8009 - the path the
 * clock uses): a pixel is a zero-length line (a V9938 point), a line is a
 * hardware line. The saver's 320x200 coordinate space is scaled to fill the
 * 512x212 screen (both are 4:3 displays, so proportions are preserved).
 *
 * Include this after gb.h, then wrap each saver's own CPC vram_pixel/vram_line
 * in `#ifndef GB_MSX2 ... #endif` so the CPC build stays byte-identical (its
 * pixel clipping / overflow guards are load-bearing) and MSX picks these up. */
#ifndef SAVDRAW_H
#define SAVDRAW_H

#ifdef GB_MSX2
#define GLINE_X0  (*(volatile unsigned int  *)0xC030)
#define GLINE_Y0  (*(volatile unsigned int  *)0xC032)
#define GLINE_X1  (*(volatile unsigned int  *)0xC034)
#define GLINE_Y1  (*(volatile unsigned int  *)0xC036)
#define GLINE_PEN (*(volatile unsigned char *)0xC038)
static void sav_fw_line(void) __naked
{
__asm
    call 0x8009
    ret
__endasm;
}
static int sav_sclx(int v) { v = v * 8 / 5;   return v < 0 ? 0 : v > GB_XPIX - 1  ? GB_XPIX - 1  : v; }
static int sav_scly(int v) { v = v * 53 / 50; return v < 0 ? 0 : v > GB_LINES - 1 ? GB_LINES - 1 : v; }
static void vram_line(int x0, int y0, int x1, int y1, unsigned char ink)
{
    GLINE_X0 = (unsigned int)sav_sclx(x0); GLINE_Y0 = (unsigned int)sav_scly(y0);
    GLINE_X1 = (unsigned int)sav_sclx(x1); GLINE_Y1 = (unsigned int)sav_scly(y1);
    GLINE_PEN = ink; sav_fw_line();
}
static void vram_pixel(int x, int y, unsigned char ink) { vram_line(x, y, x, y, ink); }
#endif  /* GB_MSX2 */

#endif  /* SAVDRAW_H */
