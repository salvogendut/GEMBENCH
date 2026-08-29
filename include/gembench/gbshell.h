#ifndef GEMBENCH_GBSHELL_H
#define GEMBENCH_GBSHELL_H

/*
 * Bounded MSX2 shell discovery and application messaging.
 *
 * A window registers one coarse service class after its normal WM registration.
 * Discovery returns an opaque, short-lived handle.  Delivery is synchronous and
 * non-reentrant: the target is raised, receives GB_MSG_SHELL through its existing
 * callback, and the calling bank is restored before gb_shell_send() returns.
 * There is no resident message queue or dynamically allocated state.
 */

#define GB_SHELL_CLASS_MASK        0xE0u
#define GB_SHELL_CLASS_TEXT_EDITOR 0x20u
#define GB_SHELL_CLASS_BITMAP_APP  0x40u
#define GB_SHELL_CLASS_ICON_APP    0x60u
#define GB_SHELL_CLASS_FILEMGR     0x80u
#define GB_SHELL_CLASS_ACCESSORY   0xA0u

#define GB_SHELL_OPEN     1u
#define GB_SHELL_ACTIVATE 2u
#define GB_SHELL_CLOSE    3u
#define GB_SHELL_QUIT     4u

#define GB_SHELL_OK          0u
#define GB_SHELL_NOT_FOUND   1u
#define GB_SHELL_STALE       2u
#define GB_SHELL_BUSY        3u
#define GB_SHELL_BAD_REQUEST 4u
#define GB_SHELL_NO_HANDLER  5u
#define GB_SHELL_REJECTED    6u

/* Append-only message value after the frozen GEMBENCH-1 window messages. */
#define GB_MSG_SHELL 11u

/* Valid only while handling GB_MSG_SHELL/GB_SHELL_OPEN. */
#define gb_shell_argument ((const char *)0x1423)

/* Register the focused/calling window as a provider of one service class. */
unsigned char gb_shell_register(unsigned char service_class);

/* Return an opaque slot+1 handle for the topmost matching app, or zero. */
unsigned char gb_shell_find(unsigned char service_class);

/*
 * Deliver a request to a handle returned by gb_shell_find().  `argument11` is
 * required only for GB_SHELL_OPEN and must point to an 11-byte 8.3 name.  The
 * target may replace gb_msg.p1 with a GB_SHELL_* response before returning.
 */
unsigned char gb_shell_send(unsigned char handle, unsigned char request,
                            const char *argument11);

/* Find the topmost provider and send in one cooperative callback turn. */
unsigned char gb_shell_request(unsigned char service_class,
                               unsigned char request,
                               const char *argument11);

#endif
