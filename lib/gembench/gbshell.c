#include "gbshell.h"

unsigned char gb_shell_request(unsigned char service_class,
                               unsigned char request,
                               const char *argument11)
{
    unsigned char handle = gb_shell_find(service_class);

    if (!handle) return GB_SHELL_NOT_FOUND;
    return gb_shell_send(handle, request, argument11);
}
