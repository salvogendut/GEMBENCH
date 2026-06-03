/* gb.h - minimal C bindings for the GEOBENCH kernel API (the libgb spike).
 *
 * Each function below is a thin asm trampoline (apps/chello/gblib.s) over a
 * fixed entry in the kernel jump table (lib/gbapp.inc). A C app includes this,
 * is compiled by SDCC to run in an expansion bank at #4000, and reaches the
 * resident kernel through these calls. Grows one entry per kernel service as
 * C apps need them. */
#ifndef GB_H
#define GB_H

/* poll flag bits (the D byte from GB_POLL) */
#define GB_CLICK 0x01 /* fresh press this frame */
#define GB_QUIT  0x02 /* ESC pressed */
#define GB_FIRE  0x04 /* fire held */

void gb_cls(void);                                       /* clear screen + home */
void gb_text(unsigned char col, unsigned char line,      /* 6x8 text, white on   */
             const char *s);                             /* the blue backdrop    */
unsigned char gb_poll(void);                             /* frame poll -> flags  */

#endif /* GB_H */
