#include "gbshell.h"

unsigned char gb_shell_request_accessory(unsigned char accessory_id,
                                         unsigned char request)
{
    unsigned char handle = gb_shell_find_accessory(accessory_id);

    if (!handle) return GB_SHELL_NOT_FOUND;
    return gb_shell_send(handle, request, 0);
}
