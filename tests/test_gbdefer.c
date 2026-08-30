#include <stddef.h>
#include <stdio.h>

#include "gbdefer.h"

#ifdef __SDCC
typedef char send_record_size[sizeof(gb_defer_send_t) == 6 ? 1 : -1];
typedef char message_record_size[sizeof(gb_defer_message_t) == 8 ? 1 : -1];
typedef char send_receiver_offset[
    offsetof(gb_defer_send_t, receiver) == 0 ? 1 : -1];
typedef char send_type_offset[offsetof(gb_defer_send_t, type) == 2 ? 1 : -1];
typedef char message_sender_offset[
    offsetof(gb_defer_message_t, sender) == 0 ? 1 : -1];
typedef char message_receiver_offset[
    offsetof(gb_defer_message_t, receiver) == 2 ? 1 : -1];
typedef char message_type_offset[
    offsetof(gb_defer_message_t, type) == 4 ? 1 : -1];
#endif

int main(void)
{
    if (GB_DEFER_QUEUE_CAPACITY != 8 || GB_DEFER_INLINE_BYTES != 4 ||
        GB_DEFER_API_VERSION != 1 || GB_MSG_DEFER != 12 ||
        GB_CAP_DEFERRED_MSG != 0x0800u)
        return 1;
    if (GB_DEFER_OK != 0 || GB_DEFER_ERR_STALE != 2 ||
        GB_DEFER_ERR_NO_HANDLER != 3 || GB_DEFER_ERR_FULL != 4 ||
        GB_DEFER_ERR_BADARG != 5 || GB_DEFER_ERR_CONTEXT != 6)
        return 1;
    puts("gbdefer contract tests: ok");
    return 0;
}
