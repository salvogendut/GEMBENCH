#include "gbevent.h"

static void event_clear(gb_event_t *event)
{
    event->classes = 0;
    event->key = 0;
    event->pointer_x = 0;
    event->pointer_y = 0;
    event->pointer_flags = 0;
    event->message = 0;
    event->p0 = 0;
    event->p1 = 0;
    event->p2 = 0;
}

unsigned char gb_event_init(gb_event_subscription_t *subscription,
                            unsigned char mask,
                            unsigned char timer_period)
{
    if (!subscription) return 0;

    subscription->mask = 0;
    subscription->timer_period = 0;
    subscription->timer_left = 0;
    subscription->last_x = 0;
    subscription->last_y = 0;
    subscription->pointer_seen = 0;

    if ((mask & (unsigned char)~GB_EVENT_ALL) != 0) return 0;
    if ((mask & GB_EVENT_TIMER) != 0 && timer_period == 0) return 0;

    subscription->mask = mask;
    if ((mask & GB_EVENT_TIMER) != 0) {
        subscription->timer_period = timer_period;
        subscription->timer_left = timer_period;
    }
    return 1;
}

static void event_pointer(gb_event_subscription_t *subscription,
                          gb_event_t *event,
                          unsigned char clicked)
{
    unsigned char x = gb_mx();
    unsigned char y = gb_my();
    unsigned char flags = 0;

    if (subscription->pointer_seen) {
        if (x != subscription->last_x || y != subscription->last_y)
            flags |= GB_EVENT_POINTER_MOVED;
    } else {
        subscription->pointer_seen = 1;
    }
    subscription->last_x = x;
    subscription->last_y = y;

    if (clicked) {
        flags |= GB_EVENT_POINTER_CLICKED;
        if ((gb_flags() & 0x04u) != 0) flags |= GB_EVENT_POINTER_FIRE;
    }
    if (!flags) return;

    event->classes |= GB_EVENT_POINTER;
    event->pointer_x = x;
    event->pointer_y = y;
    event->pointer_flags = flags;
}

unsigned char gb_event_collect(gb_event_subscription_t *subscription,
                               gb_event_t *event,
                               const volatile gb_msg_t *message)
{
    unsigned char key;

    if (!event) return 0;
    event_clear(event);
    if (!subscription || !message || !subscription->mask) return 0;

    if (message->type == GB_MSG_FRAME) {
        if ((subscription->mask & GB_EVENT_KEY) != 0) {
            key = gb_getkey();
            if (key) {
                event->key = key;
                event->classes |= GB_EVENT_KEY;
            }
        }
        if ((subscription->mask & GB_EVENT_POINTER) != 0)
            event_pointer(subscription, event, 0);
        if ((subscription->mask & GB_EVENT_TIMER) != 0) {
            subscription->timer_left--;
            if (!subscription->timer_left) {
                subscription->timer_left = subscription->timer_period;
                event->classes |= GB_EVENT_TIMER;
            }
        }
    } else {
        if ((subscription->mask & GB_EVENT_POINTER) != 0 &&
            message->type == GB_MSG_CLICK)
            event_pointer(subscription, event, 1);
        if ((subscription->mask & GB_EVENT_WINDOW) != 0) {
            event->message = message->type;
            event->p0 = message->p0;
            event->p1 = message->p1;
            event->p2 = message->p2;
            event->classes |= GB_EVENT_WINDOW;
        }
    }
    return event->classes;
}
