/* gb.h - C bindings for the GEOBENCH kernel API used by FILEMGR.
 *
 * Thin asm trampolines (gblib.s) over the kernel jump table (lib/gbapp.inc).
 * FILEMGR is compiled by SDCC to run in an expansion bank at #4000 and reaches
 * the resident kernel only through these calls. */
#ifndef GB_H
#define GB_H

/* poll flag bits (the D byte from GB_POLL) */
#define GB_CLICK 0x01 /* fresh press this frame */
#define GB_QUIT  0x02 /* ESC pressed */
#define GB_FIRE  0x04 /* fire held */

void gb_window(unsigned char col, unsigned char line,
               unsigned char w, unsigned char h, const char *title);
void gb_text(unsigned char col, unsigned char line, const char *s);
void gb_curshow(void);
void gb_curhide(void);
unsigned char gb_poll(void);          /* -> flags; caches cursor col/line */
unsigned char gb_mx(void);            /* last poll's cursor byte column   */
unsigned char gb_my(void);            /* last poll's cursor line          */
char *gb_dir1(void);                  /* first dir entry -> "NAME.EXT", 0 at end */
char *gb_dirn(void);                  /* next dir entry  -> "NAME.EXT", 0 at end */
void gb_blite(unsigned char col, unsigned char line); /* current entry's icon */
void gb_frame(unsigned char col, unsigned char line,
              unsigned char w, unsigned char h, unsigned char pen);
void gb_launch(void);                 /* launch the current dir entry */

#endif /* GB_H */
