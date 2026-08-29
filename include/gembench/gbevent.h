#ifndef GEMBENCH_GBEVENT_H
#define GEMBENCH_GBEVENT_H

/*
 * GEMBENCH non-blocking multi-event aggregation.
 *
 * The existing window procedure remains the delivery boundary.  A caller feeds
 * each gb_msg to gb_event_collect(); subscribed keyboard, pointer, timer, and
 * window activity is folded into one caller-owned record.  There is no hidden
 * queue and no resident state.
 */

#include "gb.h"

#define GB_EVENT_KEY       0x01u
#define GB_EVENT_POINTER   0x02u
#define GB_EVENT_TIMER     0x04u
#define GB_EVENT_WINDOW    0x08u
#define GB_EVENT_ALL       0x0Fu

#define GB_EVENT_POINTER_MOVED   0x01u
#define GB_EVENT_POINTER_CLICKED 0x02u
#define GB_EVENT_POINTER_FIRE    0x04u

typedef struct {
    unsigned char classes;       /* GB_EVENT_* classes present in this record */
    unsigned char key;           /* one buffered character, or zero            */
    unsigned char pointer_x;     /* current byte-column pointer position        */
    unsigned char pointer_y;     /* current line                                */
    unsigned char pointer_flags; /* GB_EVENT_POINTER_*                          */
    unsigned char message;       /* non-frame GB_MSG_* value, or zero           */
    unsigned char p0;
    unsigned char p1;
    unsigned char p2;
} gb_event_t;

typedef struct {
    unsigned char mask;          /* accepted GB_EVENT_* classes                 */
    unsigned char timer_period;  /* focused GB_MSG_FRAME callbacks per tick     */
    unsigned char timer_left;
    unsigned char last_x;
    unsigned char last_y;
    unsigned char pointer_seen;
} gb_event_subscription_t;

/*
 * Initialise an app-owned subscription.  Unknown mask bits, or a TIMER
 * subscription with period zero, fail atomically and leave the subscription
 * disabled.  A zero mask is valid.
 */
unsigned char gb_event_init(gb_event_subscription_t *subscription,
                            unsigned char mask,
                            unsigned char timer_period);

/*
 * Fold one existing WM callback into event.  GB_MSG_FRAME is the sampling
 * pulse and is not itself reported as GB_EVENT_WINDOW.  At most one keyboard
 * character and one timer tick are emitted per call; pointer motion is sampled
 * once and therefore coalesces naturally.  Returns event->classes, or zero.
 */
unsigned char gb_event_collect(gb_event_subscription_t *subscription,
                               gb_event_t *event,
                               const volatile gb_msg_t *message);

#endif
