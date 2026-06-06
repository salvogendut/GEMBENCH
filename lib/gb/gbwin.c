/* gbwin.c - libgb window helpers, shared by the C apps.
 *
 * Pure C over the kernel pointer/draw API (gb_poll/gb_frame/gb_cur*), linked
 * into each app, so window dragging costs no resident kernel space.
 */
#include "gb.h"

/* gb_drag_window: drag a w x h outline (the caller has already lifted its window
 * to the backdrop) starting from the window at (*x,*y), following the pointer
 * until fire is released. Updates *x,*y to the dropped position, clamped on
 * screen below the top bar. Returns 1 if the window moved, else 0. The caller
 * redraws its window at (*x,*y) afterwards.
 *
 * Mirrors the desktop's icon-drag: an outline tracks the pointer and erases
 * against the solid backdrop pen (no save-under). The cursor is lifted around
 * each outline edit so its save-under stays intact. */
unsigned char gb_drag_window(unsigned char *x, unsigned char *y,
                             unsigned char w, unsigned char h)
{
    unsigned char ox = *x, oy = *y;
    unsigned char gdx = (unsigned char)(gb_mx() - ox);   /* grab offset in window */
    unsigned char gdy = (unsigned char)(gb_my() - oy);
    unsigned char xmax = (unsigned char)(80 - w);        /* screen = 80 x 200 */
    unsigned char ymax = (unsigned char)(200 - h);
    unsigned char nx, ny, mx, my, f;

    gb_curhide();
    gb_frame(ox, oy, w, h, 3);                  /* outline at the start position */
    gb_curshow();

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
            continue;
        gb_curhide();
        gb_frame(ox, oy, w, h, 0);              /* erase old outline (backdrop) */
        ox = nx;
        oy = ny;
        gb_frame(ox, oy, w, h, 3);              /* draw new outline */
        gb_curshow();
    }

    gb_curhide();
    gb_frame(ox, oy, w, h, 0);                  /* erase the final outline */
    gb_curshow();

    if (ox == *x && oy == *y)
        return 0;
    *x = ox;
    *y = oy;
    return 1;
}
