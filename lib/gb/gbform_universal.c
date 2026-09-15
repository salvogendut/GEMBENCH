/* Address-free modal lifecycle for compile-once applications.
 *
 * The calling application owns this synchronous loop. Root dispatch is paused
 * until it returns, so no native shared low-RAM modal latch is required.
 */
#include "gb.h"

static void modal_draw(const gb_form_modal_t *modal)
{
    gb_curhide();
    gb_window(modal->x, modal->y, modal->w, modal->h, modal->title);
    if (modal->on_draw) modal->on_draw();
    gb_curshow();
}

unsigned char gb_form_modal_run(const gb_form_modal_t *modal)
{
    unsigned char flags, key, result = GB_FORM_STAY, done = 0;
    while (gb_poll() & GB_FIRE) while (gb_getkey()) ;
    while (gb_getkey()) ;
    modal_draw(modal);

    while (!done) {
        flags = gb_poll();
        if (flags & GB_QUIT) {
            result = GB_FORM_CANCEL;
            break;
        }
        while ((key = gb_getkey()) != 0) {
            if (!modal->on_key) continue;
            result = modal->on_key(key);
            if (result == GB_FORM_REDRAW) {
                modal_draw(modal);
                result = GB_FORM_STAY;
            } else if (result == GB_FORM_ACCEPT || result == GB_FORM_CANCEL) {
                done = 1;
                break;
            }
        }
        if (done || !(flags & GB_CLICK)) continue;
        {
            unsigned char mx = gb_mx(), my = gb_my();
            if (my >= (unsigned char)(modal->y + 2) &&
                my <  (unsigned char)(modal->y + 12) &&
                mx >= (unsigned char)(modal->x + 1) &&
                mx <  (unsigned char)(modal->x + 3)) {
                result = GB_FORM_CANCEL;
                break;
            }
            if ((modal->flags & GB_FORM_CLICK_AWAY) &&
                (mx < modal->x || mx >= (unsigned char)(modal->x + modal->w) ||
                 my < modal->y || my >= (unsigned char)(modal->y + modal->h))) {
                result = GB_FORM_CANCEL;
                break;
            }
            if (!modal->on_click) continue;
            result = modal->on_click(mx, my);
            if (result == GB_FORM_REDRAW) {
                modal_draw(modal);
                result = GB_FORM_STAY;
            } else if (result == GB_FORM_ACCEPT || result == GB_FORM_CANCEL) {
                done = 1;
            }
        }
    }

    while (gb_poll() & (GB_QUIT | GB_CLICK | GB_FIRE)) while (gb_getkey()) ;
    gb_restore_parent();
    return result;
}
