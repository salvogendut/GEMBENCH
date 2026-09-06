/* Shared Desktop policy: exact live identity first, then normal launch.
 * Provider supplies the catalog, deferred/native client and presentation leaves. */
static void open_accessory(unsigned char index)
{
#ifdef GB_DEFER_MESSAGES
    gb_owner_t endpoint;
    gb_defer_send_t message;
#else
    unsigned char result;
#endif
    if (index >= GB_DESK_ACCESSORY_COUNT) return;
#ifdef GB_DEFER_MESSAGES
    endpoint = gb_defer_find_accessory(gb_desk_accessory_ids[index]);
    if (endpoint) {
        message.receiver = endpoint;
        message.type = GB_DEFER_SHELL;
        message.p0 = GB_SHELL_ACTIVATE;
        message.p1 = message.p2 = 0;
        (void)gb_defer_send(&message);
        return;
    }
#else
    result = gb_shell_request_accessory(gb_desk_accessory_ids[index],
                                        GB_SHELL_ACTIVATE);
    if (result != GB_SHELL_NOT_FOUND) return;
#endif
    if (gb_wm_full()) gb_alert("Sorry, not enough RAM", "to run more apps.");
    else gb_wm_open(gb_desk_accessory_apps[index]);
}
