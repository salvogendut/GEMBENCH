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
    unsigned char xmax = (unsigned char)(GB_COLS - w);    /* screen extents (#287) */
    unsigned char ymax = (unsigned char)(GB_LINES - h);
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

/* gb_draw_grip: the resize grip in a window's bottom-right corner (#81) - a small
 * white box with a black edge. Apps that resize draw it in their frame. */
void gb_draw_grip(unsigned char x, unsigned char y, unsigned char w, unsigned char h)
{
    unsigned char gx = (unsigned char)(x + w - GRIP_W);
    unsigned char gy = (unsigned char)(y + h - GRIP_H);
    gb_fill(gx, gy, GRIP_W, GRIP_H, 1);
    gb_frame(gx, gy, GRIP_W, GRIP_H, 2);
}

/* gb_in_grip: is (mx,my) on the grip? The hit area is a touch larger than the glyph,
 * so it's easy to grab with the joystick pointer. */
unsigned char gb_in_grip(unsigned char x, unsigned char y, unsigned char w,
                         unsigned char h, unsigned char mx, unsigned char my)
{
    return (unsigned char)(mx >= (unsigned char)(x + w - GRIP_W - 1) && mx < x + w &&
                           my >= (unsigned char)(y + h - GRIP_H - 1) && my < y + h);
}

/* gb_drag_resize: the caller detected a press on the resize grip; run a resize drag.
 * Top-left (x,y) stays put; the bottom-right corner follows the pointer, clamped to
 * [minw..]/[minh..] and the screen. Like gb_drag_window, the window is lifted and an
 * outline shown only once the pointer moves; on release *w,*h get the new size and it
 * returns 1 (0 if it never resized). (#81) */
unsigned char gb_drag_resize(unsigned char x, unsigned char y,
                             unsigned char *w, unsigned char *h,
                             unsigned char minw, unsigned char minh)
{
    unsigned char ow = *w, oh = *h, nw, nh, mx, my, f, lifted = 0;
    unsigned char wmax = (unsigned char)(GB_COLS - x);
    unsigned char hmax = (unsigned char)(GB_LINES - y);

    for (;;) {
        f = gb_poll();
        if (!(f & GB_FIRE))
            break;
        mx = gb_mx();
        my = gb_my();
        nw = (mx >= x) ? (unsigned char)(mx - x + 1) : minw;
        nh = (my >= y) ? (unsigned char)(my - y + 1) : minh;
        if (nw < minw) nw = minw;
        if (nh < minh) nh = minh;
        if (nw > wmax) nw = wmax;
        if (nh > hmax) nh = hmax;
        if (nw == ow && nh == oh)
            continue;
        gb_curhide();
        if (!lifted) { gb_fill(x, y, *w, *h, 0); lifted = 1; }   /* lift the window */
        else gb_frame(x, y, ow, oh, 0);                          /* erase old outline */
        ow = nw;
        oh = nh;
        gb_frame(x, y, ow, oh, 3);                               /* outline at new size */
        gb_curshow();
    }

    if (!lifted)
        return 0;
    gb_curhide();
    gb_frame(x, y, ow, oh, 0);
    gb_curshow();
    *w = ow;
    *h = oh;
    return 1;
}
