/* gbwin.c - libgb window helpers, shared by the C apps.
 *
 * Pure C over the kernel pointer/draw API (gb_poll/gb_frame/gb_cur*), linked
 * into each app, so window dragging costs no resident kernel space.
 */
#include "gb.h"

/* gb_drag_window: the caller detected a title-bar press; run a drag. While fire
 * is held, an outline follows the pointer. The window is only lifted (erased to
 * the backdrop) and the outline shown once the pointer ACTUALLY moves, so a plain
 * title-bar click costs nothing - no flash, no redraw. On release, updates *x,*y
 * to the dropped position (clamped on screen, clear of the top bar) and returns
 * 1; returns 0 if the window never moved (caller then leaves its window as-is).
 *
 * Mirrors the desktop's icon-drag: the outline erases against the solid backdrop
 * pen (no save-under); the cursor is lifted around each outline edit. */
unsigned char gb_drag_window(unsigned char *x, unsigned char *y,
                             unsigned char w, unsigned char h)
{
    unsigned char ox = *x, oy = *y;
    unsigned char gdx = (unsigned char)(gb_mx() - ox);   /* grab offset in window */
    unsigned char gdy = (unsigned char)(gb_my() - oy);
    unsigned char xmax = (unsigned char)(80 - w);        /* screen = 80 x 200 */
    unsigned char ymax = (unsigned char)(200 - h);
    unsigned char nx, ny, mx, my, f, lifted = 0;

    for (;;) {
        f = gb_poll();
        if (!(f & GB_FIRE))                     /* released -> drop */
            break;
        mx = gb_mx();
        my = gb_my();
        nx = (mx >= gdx) ? (unsigned char)(mx - gdx) : 0;
        ny = (my >= gdy) ? (unsigned char)(my - gdy) : 0;
        if (nx > xmax) nx = xmax;
        if (ny < 8)    ny = 8;                  /* keep clear of the top bar */
        if (ny > ymax) ny = ymax;
        if (nx == ox && ny == oy)
            continue;                           /* not moved yet */
        gb_curhide();
        if (!lifted) {                          /* first move: lift window -> backdrop */
            gb_fill(ox, oy, w, h, 0);
            lifted = 1;
        } else {
            gb_frame(ox, oy, w, h, 0);          /* erase old outline */
        }
        ox = nx;
        oy = ny;
        gb_frame(ox, oy, w, h, 3);              /* outline at the new position */
        gb_curshow();
    }

    if (!lifted)
        return 0;                               /* a plain click, never dragged */
    gb_curhide();
    gb_frame(ox, oy, w, h, 0);                  /* erase the final outline */
    gb_curshow();
    *x = ox;
    *y = oy;
    return 1;
}
