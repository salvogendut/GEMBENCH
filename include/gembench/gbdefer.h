#ifndef GEMBENCH_GBDEFER_H
#define GEMBENCH_GBDEFER_H

#include "gb.h"

/* Architecture Milestone 3 (#35): a bounded MSX2 application-message FIFO.
 * An endpoint is the existing generation-tagged application owner. Sending
 * only copies this six-byte value into resident storage; no target callback
 * can run until a later root-loop turn. */
#define GB_DEFER_QUEUE_CAPACITY 8u
#define GB_DEFER_INLINE_BYTES   4u
#define GB_DEFER_API_VERSION    1u

#define GB_DEFER_OK             0u
#define GB_DEFER_ERR_UNSUPPORTED 1u
#define GB_DEFER_ERR_STALE      2u
#define GB_DEFER_ERR_NO_HANDLER 3u
#define GB_DEFER_ERR_FULL       4u
#define GB_DEFER_ERR_BADARG     5u
#define GB_DEFER_ERR_CONTEXT    6u

/* Type 1 is reserved for deferred shell lifecycle requests. Values 32..255
 * are application-defined. */
#define GB_DEFER_SHELL          1u
#define GB_DEFER_APP_MIN       32u

typedef struct {
    gb_owner_t receiver;
    unsigned char type;
    unsigned char p0;
    unsigned char p1;
    unsigned char p2;
} gb_defer_send_t;

typedef struct {
    gb_owner_t sender;
    gb_owner_t receiver;
    unsigned char type;
    unsigned char p0;
    unsigned char p1;
    unsigned char p2;
} gb_defer_message_t;

/* Register the current application's handler. Passing NULL unregisters it and
 * cancels messages waiting for this receiver. The handler runs only from the
 * root loop and should return promptly. */
unsigned char gb_defer_register(void (*handler)(void));
/* The six bytes may live in mapped application data or in a normal C local on
 * the fixed MSX stack; the kernel validates the complete range against its
 * captured TPA ceiling and copies it before returning. */
unsigned char gb_defer_send(const gb_defer_send_t *message);
const gb_defer_message_t *gb_defer_current(void);
unsigned char gb_defer_slots_free(void);
unsigned char gb_defer_cancel_all(void);

/* Discovery returns generation-tagged application endpoints, not window slots. */
gb_owner_t gb_defer_find_service(unsigned char service_class);
gb_owner_t gb_defer_find_accessory(unsigned char accessory_id);

/* Valid in a deferred handler. The root raises/repaints this application's
 * primary window after the handler returns, avoiding a nested callback. */
#define gb_defer_activate() (gb_msg.p2 = 1u)

#endif
