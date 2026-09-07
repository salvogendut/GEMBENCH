/* Same Desktop menu registration. A native integration component may omit
 * System until its settings/media/dialog providers have been qualified. */
static void desktop_menu_init(void)
{
    gb_doc(&deskdoc);                        /* empty doc: no File/Edit/View */
#ifdef GB_DESK_ACCESSORIES
    gb_menu_add("Desk", gb_desk_accessory_labels, GB_DESK_ACCESSORY_COUNT,
                accessory_action);
#endif
#if !defined(DESKTOP_SYSTEM_MENU) || DESKTOP_SYSTEM_MENU
#ifndef DESKTOP_SYSTEM_ITEM_COUNT
#define DESKTOP_SYSTEM_ITEM_COUNT 7
#endif
    gb_menu_add("System", sys_items, DESKTOP_SYSTEM_ITEM_COUNT, sys_action);
#endif
}
