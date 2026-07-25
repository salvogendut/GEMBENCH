/* gbactions.c - compact, opt-in default action rows.
 *
 * This is the constrained-app counterpart to gb_form_actions(): it keeps the
 * standard surface/edge appearance without pulling in the full button or form
 * units. Widths are caller-owned and should leave one column around the label.
 * The fixed 10-line height is the standard compact action metric.
 */
#include "gb.h"

void gb_actions(unsigned char x, unsigned char y,
                const gb_action_t *actions,
                unsigned char count, unsigned char gap)
{
    unsigned char i;
    for (i = 0; i < count; i++) {
        gb_frame(x, y, actions[i].w, GB_ACTION_H, 2);
        gb_textbw((unsigned char)(x + 1), (unsigned char)(y + 1),
                  actions[i].label);
        x = (unsigned char)(x + actions[i].w + gap);
    }
}

unsigned char gb_actions_hit(unsigned char x, unsigned char y,
                             const gb_action_t *actions,
                             unsigned char count, unsigned char gap,
                             unsigned char mx, unsigned char my)
{
    unsigned char i;
    if (my < y || my >= (unsigned char)(y + GB_ACTION_H))
        return GB_ACTION_NONE;
    for (i = 0; i < count; i++) {
        if (mx >= x && mx < (unsigned char)(x + actions[i].w)) return i;
        x = (unsigned char)(x + actions[i].w + gap);
    }
    return GB_ACTION_NONE;
}
