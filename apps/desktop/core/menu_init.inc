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
    gb_menu_add("System", sys_items, 7, sys_action);
#endif
}
