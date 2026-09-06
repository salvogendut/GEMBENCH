/* Execute the real gbdoc menu component and Desktop fragments on the host. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../lib/gb/gb.h"
#undef gb_msg
static gb_msg_t host_message;
#define gb_msg host_message
#define GBDOC_MENU_ONLY 1
#define GB_DESK_ACCESSORIES 1
#define DESKTOP_SYSTEM_MENU 0
#define GB_DESK_CATALOG_DATA
#include "../include/gembench/gbdesk_catalog.h"
static unsigned char published[37], modal, close_requested, choice = 255;
static unsigned char popup_calls, damage_calls, activations, activated;
static unsigned char want_accessory;
static const gb_doc_t deskdoc = { 0 };
void gb_menu(const void *raw)
{
    const unsigned char *definition = raw;
    memcpy(published, definition, 1 + definition[0] * 9);
}
unsigned char gb_modal(void) { return modal; }
void gb_popup_close(void) { close_requested = 1; }
unsigned char gb_wm_x(void) { return 0; }
unsigned char gb_wm_y(void) { return 0; }
unsigned char gb_wm_w(void) { return GB_COLS; }
unsigned char gb_wm_h(void) { return GB_LINES; }
void gb_wm_damage(unsigned char x, unsigned char y, unsigned char w, unsigned char h)
{
    assert(!x && !y && w == GB_COLS && h == GB_LINES);
    ++damage_calls;
}
unsigned char gb_popup(unsigned char x, unsigned char y, const char *const *labels, unsigned char count)
{
    assert(x == 10 && y == 8 && count == GB_DESK_ACCESSORY_COUNT);
    assert(labels == gb_desk_accessory_labels);
    ++popup_calls;
    return choice;
}
#include "../lib/gb/gbdoc.c"
static void open_accessory(unsigned char index)
{
    assert(!modal && index < GB_DESK_ACCESSORY_COUNT);
    assert(gb_desk_accessory_ids[index] == index + 1);
    assert(strlen(gb_desk_accessory_apps[index]) == 11);
    activated = index; ++activations;
}
#include "../apps/desktop/core/accessory_menu.inc"
#include "../apps/desktop/core/menu_init.inc"
static void frame(void)
{
    if (gb_doc_frame()) {
#include "../apps/desktop/core/accessory_pending.inc"
    }
}
int main(void)
{
    desktop_menu_init();
    assert(published[0] == 1 && published[1] == 10);
    assert(!memcmp(published + 2, "Desk\0\0\0\0", 8));
    host_message.type = GB_MSG_FRAME;
    assert(!gb_doc_event());
    host_message.type = GB_MSG_MENU;
    for (unsigned char col = 9; col <= 16; col += 7) {
        host_message.p0 = col; assert(!gb_doc_event());
    }
    frame(); assert(!popup_calls && !activations);
    host_message.p0 = 12; assert(gb_doc_event());
    frame(); assert(popup_calls == 1 && !damage_calls && !activations);
    choice = 1; assert(gb_doc_event()); frame();
    assert(popup_calls == 2 && damage_calls == 1 && activations == 1 && activated == 1);
    assert(!want_accessory); frame(); assert(activations == 1);
    modal = 1; assert(gb_doc_event() && close_requested); modal = 0;
    frame(); assert(popup_calls == 2); /* title re-click must not re-arm */
    for (unsigned char i = 0; i < 4; ++i)
        gb_menu_add("Extra", gb_desk_accessory_labels, 2, accessory_action);
    assert(published[0] == 4); /* fixed title capacity */
    assert(gb_doc_event()); desktop_menu_init(); frame();
    assert(published[0] == 1 && popup_calls == 2); /* reset clears stale request */
    accessory_action(GB_DESK_ACCESSORY_COUNT); assert(!want_accessory);
    puts("shared Desktop menu: bounds, cancel, deferred action, modal toggle, capacity PASS");
    return 0;
}
