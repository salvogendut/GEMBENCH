/* gb.h - C bindings for the GEOBENCH kernel API used by VIEWER.
 *
 * Thin asm trampolines (gblib.s) over the kernel jump table (lib/gbapp.inc).
 * VIEWER is compiled by SDCC to run in an expansion bank at #4000 and reaches
 * the resident kernel only through these calls. */
#ifndef GB_H
#define GB_H

/* poll flag bits (the D byte from GB_POLL) */
#define GB_CLICK 0x01 /* fresh press this frame */
#define GB_QUIT  0x02 /* ESC pressed */
#define GB_FIRE  0x04 /* fire held */

void gb_window(unsigned char col, unsigned char line,    /* draw a window: pos +  */
               unsigned char w, unsigned char h,         /* size (byte cols /     */
               const char *title);                       /* lines) + title        */
void gb_text(unsigned char col, unsigned char line,      /* 6x8 text, white on    */
             const char *s);                             /* the window            */
void gb_curshow(void);                                   /* draw the pointer      */
unsigned char gb_poll(void);                             /* frame poll -> flags   */
unsigned int gb_fs_load(char *buf);                      /* load the opened file  */
                                                         /* -> byte count         */
#endif /* GB_H */
