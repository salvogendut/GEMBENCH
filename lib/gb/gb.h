/* gb.h - shared C bindings for the GEOBENCH kernel API.
 *
 * The one libgb every GEOBENCH C app uses. Each function is a thin asm
 * trampoline (gblib.s) over a fixed entry in the kernel jump table
 * (lib/gbapp.inc). Apps are compiled by SDCC to run in an expansion bank at
 * #4000 and reach the resident kernel only through these calls. */
#ifndef GB_H
#define GB_H

/* poll flag bits (the D byte from GB_POLL) */
#define GB_CLICK 0x01 /* fresh press this frame */
#define GB_QUIT  0x02 /* ESC pressed */
#define GB_FIRE  0x04 /* fire held */

void gb_cls(void);                                       /* clear screen + home  */
void gb_text(unsigned char col, unsigned char line,      /* 6x8 text, white      */
             const char *s);
void gb_window(unsigned char col, unsigned char line,    /* window: pos + size   */
               unsigned char w, unsigned char h, const char *title);
/* gb_drag_window: drag a w x h outline from (*x,*y) by the pointer until release;
 * updates *x,*y to the dropped position (clamped on screen). Caller lifts its
 * window to the backdrop first and redraws at (*x,*y) after. Returns 1 if moved.
 * (lib/gb/gbwin.c) */
unsigned char gb_drag_window(unsigned char *x, unsigned char *y,
                             unsigned char w, unsigned char h);
void gb_fill(unsigned char col, unsigned char line,      /* filled rectangle     */
             unsigned char w, unsigned char h, unsigned char pen);
void gb_frame(unsigned char col, unsigned char line,     /* rectangle outline    */
              unsigned char w, unsigned char h, unsigned char pen);
void gb_icon(unsigned char slot, unsigned char col,      /* full icon blit       */
             unsigned char line);
void gb_blite(unsigned char col, unsigned char line);    /* current entry's icon */
void gb_curshow(void);                                   /* draw the pointer     */
void gb_curhide(void);                                   /* lift the pointer     */
unsigned char gb_poll(void);          /* frame poll -> flags; caches cursor pos   */
unsigned char gb_mx(void);            /* last poll's cursor byte column           */
unsigned char gb_my(void);            /* last poll's cursor line                  */
unsigned char gb_flags(void);         /* last poll's flags (for gb_wm_run apps)   */
char *gb_dir1(void);                  /* first dir entry -> "NAME.EXT", 0 at end  */
char *gb_dirn(void);                  /* next dir entry  -> "NAME.EXT", 0 at end  */
void gb_launch(void);                 /* launch the current dir entry             */
void gb_run(const char *name);        /* run a named app, return when it quits    */
unsigned int gb_fs_load(char *buf, unsigned int max);    /* load opened file ->   */
                                                         /* byte count            */
unsigned char gb_fs_save(char *buf, unsigned int len);   /* save opened file ->   */
                                                         /* 1 ok / 0 fail         */
unsigned char gb_getkey(void);        /* typed char from the keyboard, 0 if none  */
unsigned char gb_vsync(void);         /* wait one frame -> 1 if ESC held, else 0  */

/* Event callback (issue #32): the kernel calls a registered handler when an
 * event it owns occurs - currently a click in the top bar (GB_MSG_MENU). The
 * handler is invoked during gb_poll (so call gb_poll in your loop), reads the
 * message from gb_msg, and must return promptly (do not call gb_poll from it).
 * The message lives at a fixed low-RAM address shared with the kernel. */
typedef struct {
    unsigned char type;   /* GB_MSG_* */
    unsigned char p0;     /* menu: clicked byte column */
    unsigned char p1;
    unsigned char p2;
} gb_msg_t;
#define GB_MSG_MENU 1
/* GB_MSG_DROP (#62): a file was dropped on this window via drag-and-drop. The
 * dragged item's 11-byte 8.3 name is at gb_dragname; the drop position is the
 * current gb_mx()/gb_my(). Delivered to the *target* window's on_event handler. */
#define GB_MSG_DROP 2
#define gb_dragname ((const char *)0x13BB)
#define gb_msg (*(volatile gb_msg_t *)0x1302)
void gb_on_event(void (*handler)(void));   /* register handler, 0 to clear */

/* Top-bar menu (issue #34). The app registers menu titles the kernel draws in
 * the bar (persisting across clock ticks); a click on the bar arrives via the
 * gb_on_event callback as GB_MSG_MENU with p0 = the clicked byte column, so the
 * app maps the column to its title and draws its own dropdown. def layout:
 *   byte 0: title count (<=4)
 *   then per title: byte col, then an 8-byte NUL/space-padded label
 * Cleared automatically when the app launches a child or quits. */
void gb_menu(const void *def);

/* gb_set_name: set the current file (an 11-byte 8.3 name, space-padded, no dot,
 * e.g. "NOTES   TXT") so a later gb_fs_load/gb_fs_save targets it - how an app
 * does New / Save As / open a file chosen from a picker. */
void gb_set_name(const char *name11);

/* Draggable-window background repaint (issue #43). An app registers a full-repaint
 * handler (redraws its whole window/desktop, no input) with gb_on_repaint; when a
 * child app moves a window, it calls gb_restore_parent first, and the kernel runs
 * every ancestor's handler bottom-up to repaint what the window vacated, then the
 * child redraws its window on top. */
void gb_on_repaint(void (*handler)(void));   /* register full-repaint handler */
void gb_restore_parent(void);                /* repaint ancestor apps behind us */

/* Cooperative window manager (issue #45). Instead of owning a for(;;) loop, an
 * app fills a gb_win_t and registers a window: the KERNEL runs the master loop,
 * calls the focused window's on_frame every frame (read input with gb_flags/
 * gb_mx/gb_my - do NOT call gb_poll inside it), and on a click hit-tests the
 * rects to switch focus. on_repaint redraws the whole window with no input;
 * on_event handles a top-bar click (0 = none). The rect (x,y,w,h) is the
 * window's screen area used for click-to-focus.
 *
 *   gb_wm_run   - the ROOT window (desktop): register + enter the loop (no return).
 *   gb_wm_open  - open an app as a new co-resident window on top (non-blocking).
 *   gb_wm_add   - register the calling window (an app's main() does this when it
 *                 was started by gb_wm_open), then return to the opener.
 *   gb_wm_close - close the calling window; return from on_frame right after. */
typedef struct {
    unsigned char x, y, w, h;       /* window rect (byte col, line, size)  */
    void (*on_frame)(void);         /* called each frame when focused       */
    void (*on_repaint)(void);       /* redraw the whole window, no input    */
    void (*on_event)(void);         /* top-bar click handler, or 0          */
    const void *menu;               /* top-bar menu def (gb_menu fmt), or 0 */
} gb_win_t;
void gb_wm_run(const gb_win_t *desc);
void gb_wm_add(const gb_win_t *desc);
void gb_wm_open(const char *name);
void gb_wm_close(void);
void gb_wm_setpos(unsigned char x, unsigned char y);  /* move our hit rect (drag) */
void gb_wm_launch(void);              /* open current dir entry co-resident (+ arg) */

/* Directory navigation (issue #54). gb_isdir reports whether the entry just
 * returned by gb_dir1/gb_dirn is a directory; gb_chdir descends into the
 * positioned entry (re-list afterwards to show it in the same window); gb_back
 * returns to the parent directory (no-op at the top). */
unsigned char gb_isdir(void);
void gb_chdir(void);
void gb_back(void);
char *gb_entname(void);  /* current entry's raw 11-byte 8.3 name (with extension) */

/* Drag-and-drop (issue #62). gb_drag_start begins dragging the named item (an
 * 11-byte 8.3 name); it blocks, following the pointer until the button is
 * released. Returns 1 if it was dropped on another window (that window's
 * on_event got a GB_MSG_DROP and handled it), or 0 if it was just a click (no
 * movement / no target) so the caller should treat it as a normal selection. */
unsigned char gb_drag_start(const char *name);

/* gb_file_delete: delete a file (11-byte 8.3 name) from the current directory -
 * frees its clusters and clears its directory entry. Returns 1 if deleted, 0 on
 * failure (not found, a directory, or unsupported backend). Used by the desktop
 * Trash drop handler (#62). */
unsigned char gb_file_delete(const char *name);

/* gb_drives: probe the drives GEOBENCH can reach. Returns a bitmask (#65):
 *   GB_DRV_A (floppy A), GB_DRV_B (floppy B), GB_DRV_C (IDE / Disk C).
 * Floppy probing spins the drive motor, so call at boot and on demand. */
#define GB_DRV_A 0x01
#define GB_DRV_B 0x02
#define GB_DRV_C 0x04
unsigned char gb_drives(void);

/* Multi-drive (#65). gb_set_drive selects which drive subsequent FS calls target
 * (0 = IDE / Disk C, 1 = floppy A, 2 = floppy B); gb_get_drive returns the current
 * one. A File Manager window reads gb_get_drive at startup (the drive the desktop
 * opened it on) and re-asserts gb_set_drive before its FS ops, so each window
 * browses its own drive. */
#define GB_DRIVE_C 0
#define GB_DRIVE_A 1
#define GB_DRIVE_B 2
void gb_set_drive(unsigned char d);
unsigned char gb_get_drive(void);

/* gb_file_copy: copy the file currently being dragged (its name + source drive and
 * directory were captured by gb_drag_start) into the *current* drive's root. Called
 * by a drop-target window's on_event on GB_MSG_DROP to receive a cross-drive
 * drag-and-drop. Returns 1 if copied, 0 on failure (#65 phase 3). */
unsigned char gb_file_copy(void);
#endif /* GB_H */
