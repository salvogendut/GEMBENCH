/* gbform.c - opt-in form rows, action rows and modal lifecycle.
 *
 * State remains in the application. The modal runner only owns polling,
 * close/click-away cancellation and repaint cleanup while it is active.
 */
#include "gb.h"

#ifdef GB_HOST_TEST
extern unsigned char gb_form_modal_latch;
#define FORM_MODAL_LATCH gb_form_modal_latch
#else
#define FORM_MODAL_LATCH (*(volatile unsigned char *)0x1705)
#endif

static unsigned char label_y(unsigned char y, unsigned char h)
{
    if (h <= 8) return y;
    return (unsigned char)(y + ((h - 8 + 1) >> 1));
}

#ifndef GB_FORM_MODAL_ONLY
void gb_form_label(unsigned char x, unsigned char y, unsigned char h,
                   const char *label)
{
    gb_textbw(x, label_y(y, h), label);
}

void gb_form_field_row(unsigned char x, unsigned char y,
                       unsigned char w, unsigned char h,
                       unsigned char label_w, const char *label,
                       const char *value, unsigned char flags)
{
    gb_form_label(x, y, h, label);
    if (label_w >= w) return;
    gb_field((unsigned char)(x + label_w), y,
             (unsigned char)(w - label_w), h, value, flags);
}

unsigned char gb_form_row_hit(unsigned char x, unsigned char y,
                              unsigned char w, unsigned char h,
                              unsigned char label_w,
                              unsigned char mx, unsigned char my)
{
    if (label_w >= w) return 0;
    return gb_widget_hit((unsigned char)(x + label_w), y,
                         (unsigned char)(w - label_w), h, mx, my);
}

void gb_form_actions(unsigned char x, unsigned char y, unsigned char h,
                     const gb_form_action_t *actions,
                     unsigned char count, unsigned char gap)
{
    unsigned char i;
    for (i = 0; i < count; i++) {
        gb_button(x, y, actions[i].w, h, actions[i].label, actions[i].flags);
        x = (unsigned char)(x + actions[i].w + gap);
    }
}

unsigned char gb_form_actions_hit(unsigned char x, unsigned char y,
                                  unsigned char h,
                                  const gb_form_action_t *actions,
                                  unsigned char count, unsigned char gap,
                                  unsigned char mx, unsigned char my)
{
    unsigned char i;
    for (i = 0; i < count; i++) {
        if (gb_button_hit(x, y, actions[i].w, h, mx, my, actions[i].flags))
            return i;
        x = (unsigned char)(x + actions[i].w + gap);
    }
    return GB_FORM_NO_ACTION;
}
#endif

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
    FORM_MODAL_LATCH = 1;
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
    FORM_MODAL_LATCH = 0;
    gb_restore_parent();
    return result;
}
