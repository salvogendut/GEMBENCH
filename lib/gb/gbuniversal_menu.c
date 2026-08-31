/* Portable top-bar dropdown for compile-once applications.
 *
 * It deliberately uses only frozen kernel calls and the semantic drawing
 * wrapper.  The save-under buffer belongs to the application image, avoiding
 * target-era low-RAM scratch addresses that universal source may not use.
 */
#include "gbuniversal.h"

#define POPUP_MAX_ITEMS 4u
#define POPUP_BUFFER_BYTES 768u

static unsigned char popup_under[POPUP_BUFFER_BYTES];
static unsigned char popup_live;
static unsigned char popup_close;

unsigned char gb_universal_popup_active(void)
{
    return popup_live;
}

void gb_universal_popup_close(void)
{
    popup_close = 1u;
}

static unsigned char text_columns(const char *text)
{
    unsigned char n = 0u;
    while (text[n]) ++n;
    return (unsigned char)((n * 6u + 3u) >> 2);
}

static void draw_row(unsigned char x, unsigned char y,
                     const char *label, unsigned char row,
                     unsigned char selected, unsigned char width)
{
    unsigned char row_y = (unsigned char)(y + 2u + row * 10u);
    unsigned char paper = selected ? GB_UI_EDGE : GB_UI_SURFACE;
    unsigned char pen = selected ? GB_UI_SURFACE : GB_UI_TEXT;
    gb_fill((unsigned char)(x + 1u), row_y,
            (unsigned char)(width - 2u), 10u, paper);
    gb_text_semantic((unsigned char)(x + 1u), row_y, label, pen, paper);
}

unsigned char gb_universal_popup(unsigned char x,
                                 const char *const *labels,
                                 unsigned char count)
{
    unsigned char i, width = 4u, height, columns;
    unsigned char flags, hot = 0xFFu, over, selected = 0xFFu;
    unsigned char y = 8u;
    unsigned int bytes;

    if (!labels || count == 0u || count > POPUP_MAX_ITEMS) return 0xFFu;
    for (i = 0u; i != count; ++i) {
        columns = (unsigned char)(text_columns(labels[i]) + 4u);
        if (columns > width) width = columns;
    }
    height = (unsigned char)(count * 10u + 4u);
    if ((unsigned char)(y + height) > gb_screen_lines())
        y = (unsigned char)(gb_screen_lines() - height);
    bytes = (unsigned int)width * height;
    if (bytes > POPUP_BUFFER_BYTES) return 0xFFu;

    popup_live = 1u;
    popup_close = 0u;
    gb_curhide();
    gb_saverect(x, y, width, height, popup_under);
    gb_fill(x, y, width, height, GB_UI_SURFACE);
    gb_frame(x, y, width, height, GB_UI_EDGE);
    for (i = 0u; i != count; ++i)
        draw_row(x, y, labels[i], i, 0u, width);
    gb_curshow();

    while (!popup_close) {
        flags = gb_poll();
        over = 0xFFu;
        if (gb_mx() >= x && gb_mx() < (unsigned char)(x + width) &&
            gb_my() >= (unsigned char)(y + 2u) &&
            gb_my() < (unsigned char)(y + 2u + count * 10u))
            over = (unsigned char)((gb_my() - y - 2u) / 10u);
        if (over != hot) {
            gb_curhide();
            if (hot != 0xFFu) draw_row(x, y, labels[hot], hot, 0u, width);
            if (over != 0xFFu) draw_row(x, y, labels[over], over, 1u, width);
            gb_curshow();
            hot = over;
        }
        if (flags & GB_QUIT) break;
        if (flags & GB_CLICK) {
            selected = over;
            break;
        }
    }

    popup_live = 0u;
    while (gb_poll() & (GB_QUIT | GB_CLICK)) { }
    gb_curhide();
    gb_restorerect(x, y, width, height, popup_under);
    gb_curshow();
    return selected;
}
