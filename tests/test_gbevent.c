#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "gbevent.h"

static int failures;
static unsigned char sample_key;
static unsigned char sample_x;
static unsigned char sample_y;
static unsigned char sample_flags;
static unsigned int key_reads;

unsigned char gb_getkey(void)
{
    unsigned char key = sample_key;
    sample_key = 0;
    key_reads++;
    return key;
}

unsigned char gb_mx(void) { return sample_x; }
unsigned char gb_my(void) { return sample_y; }
unsigned char gb_flags(void) { return sample_flags; }

static void check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

static gb_msg_t message(unsigned char type, unsigned char p0,
                        unsigned char p1, unsigned char p2)
{
    gb_msg_t value;
    value.type = type;
    value.p0 = p0;
    value.p1 = p1;
    value.p2 = p2;
    return value;
}

static void test_layout_and_init(void)
{
    gb_event_subscription_t subscription;

    check(sizeof(gb_event_t) == 9, "event record is exactly nine bytes");
    check(sizeof(gb_event_subscription_t) == 6,
          "subscription state is exactly six bytes");
    check(offsetof(gb_event_t, p2) == 8, "event payload is packed and stable");

    memset(&subscription, 0xA5, sizeof(subscription));
    check(!gb_event_init(&subscription, 0x80, 1),
          "unknown subscription classes are rejected");
    check(subscription.mask == 0 && subscription.timer_period == 0 &&
              subscription.pointer_seen == 0,
          "invalid subscription fails atomically");
    check(!gb_event_init(&subscription, GB_EVENT_TIMER, 0),
          "timer subscription requires a non-zero period");
    check(gb_event_init(&subscription, 0, 0) && subscription.mask == 0,
          "an explicitly empty subscription is valid");
}

static void test_filtering(void)
{
    gb_event_subscription_t subscription;
    gb_event_t event;
    gb_msg_t frame = message(GB_MSG_FRAME, 1, 2, 3);
    gb_msg_t draw = message(GB_MSG_DRAW, 4, 5, 6);

    key_reads = 0;
    sample_key = 'A'; sample_x = 10; sample_y = 20; sample_flags = 0;
    check(gb_event_init(&subscription, GB_EVENT_KEY, 0),
          "key-only subscription initializes");
    check(gb_event_collect(&subscription, &event, &frame) == GB_EVENT_KEY &&
              event.key == 'A',
          "subscribed key is delivered");
    check(event.pointer_flags == 0 && event.message == 0,
          "unsubscribed fields stay clear");
    check(gb_event_collect(&subscription, &event, &draw) == 0,
          "unsubscribed window message is filtered");
    check(key_reads == 1, "non-frame callbacks never drain the keyboard");
}

static void test_combination_and_coalescing(void)
{
    gb_event_subscription_t subscription;
    gb_event_t event;
    gb_msg_t frame = message(GB_MSG_FRAME, 0, 0, 0);
    gb_msg_t click = message(GB_MSG_CLICK, 7, 8, 9);
    gb_msg_t sized = message(GB_MSG_SIZED, 31, 144, 0);

    key_reads = 0;
    sample_x = 8; sample_y = 30; sample_key = 'K'; sample_flags = 0;
    check(gb_event_init(&subscription, GB_EVENT_ALL, 2),
          "all-class subscription initializes");
    check(gb_event_collect(&subscription, &event, &frame) == GB_EVENT_KEY,
          "first pointer sample seeds position without fake motion");

    sample_x = 11; sample_y = 34;
    check(gb_event_collect(&subscription, &event, &frame) ==
              (GB_EVENT_POINTER | GB_EVENT_TIMER) &&
              event.pointer_flags == GB_EVENT_POINTER_MOVED &&
              event.pointer_x == 11 && event.pointer_y == 34,
          "latest pointer movement and timer share one record");

    check(gb_event_collect(&subscription, &event, &frame) == 0,
          "unchanged pointer and not-yet-due timer produce no event");

    sample_x = 12; sample_key = 'Z';
    check(gb_event_collect(&subscription, &event, &frame) ==
              (GB_EVENT_KEY | GB_EVENT_POINTER | GB_EVENT_TIMER) &&
              event.key == 'Z',
          "key, pointer, and timer classes combine without a queue");

    sample_x = 15; sample_y = 40; sample_flags = 0x04;
    check(gb_event_collect(&subscription, &event, &click) ==
              (GB_EVENT_POINTER | GB_EVENT_WINDOW) &&
              event.pointer_flags == (GB_EVENT_POINTER_MOVED |
                                      GB_EVENT_POINTER_CLICKED |
                                      GB_EVENT_POINTER_FIRE) &&
              event.message == GB_MSG_CLICK && event.p0 == 7 &&
              event.p1 == 8 && event.p2 == 9,
          "content click preserves pointer and WM payload in one record");

    check(gb_event_collect(&subscription, &event, &sized) == GB_EVENT_WINDOW &&
              event.message == GB_MSG_SIZED && event.p0 == 31 &&
              event.p1 == 144,
          "non-frame window messages preserve their payload");
    check(key_reads == 4, "exactly one keyboard read occurs per frame callback");
}

static void test_null_boundaries(void)
{
    gb_event_subscription_t subscription;
    gb_event_t event;
    gb_msg_t frame = message(GB_MSG_FRAME, 0, 0, 0);

    check(!gb_event_init(NULL, GB_EVENT_KEY, 0), "null subscription init fails");
    check(gb_event_init(&subscription, GB_EVENT_KEY, 0),
          "valid subscription follows null test");
    check(!gb_event_collect(NULL, &event, &frame) && event.classes == 0,
          "null subscription emits an empty record");
    check(!gb_event_collect(&subscription, &event, NULL) && event.classes == 0,
          "null message emits an empty record");
    check(!gb_event_collect(&subscription, NULL, &frame),
          "null output fails safely");
}

int main(void)
{
    test_layout_and_init();
    test_filtering();
    test_combination_and_coalescing();
    test_null_boundaries();
    if (failures) return 1;
    puts("gbevent: all tests passed");
    return 0;
}
