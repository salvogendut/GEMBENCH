#ifndef GEMBENCH_GBTIMER_H
#define GEMBENCH_GBTIMER_H

/*
 * Architecture Milestone 8: background visual timers for MSX2.
 *
 * A task worker may inspect the root-refreshed time bytes and publish one
 * coalesced, generation-tagged damage rectangle. gb_timer_damage() performs
 * memory stores only: it does not call the kernel, firmware, drawing code, or a
 * paged module, so it is safe in a pure worker callback. The Desktop root hook
 * validates the live owner, consumes the request with gb_timer_collect(), and
 * repaints through the compositor.
 */

#define GB_TIMER_HOUR   (*(volatile unsigned char *)0x1240u)
#define GB_TIMER_MINUTE (*(volatile unsigned char *)0x1241u)
#define GB_TIMER_SECOND (*(volatile unsigned char *)0x1242u)
#define GB_TIMER_TASK_SLOT (*(volatile unsigned char *)0x1342u)
#define GB_TIMER_OWNER     (*(volatile unsigned char *)0xC3CAu)
#define GB_TIMER_DROPPED   (*(volatile unsigned char *)0xC1ECu)

/* While the root compositor consumes a request it retains the source identity
 * and sets bit 7. This lets the source distinguish its small timer redraw from
 * an unrelated ordinary repaint without exposing a kernel/window handle API. */
#define GB_TIMER_ACTIVE_FOR(owner) \
    (GB_TIMER_OWNER == (unsigned char)(0x80u | (owner)))

/* Publish one damage rectangle. A request already waiting for the root task is
 * left unchanged. Fullscreen mode suppresses publication because revealing the
 * ordinary window stack performs a current-time repaint anyway. */
void gb_timer_damage(unsigned char x, unsigned char y,
                     unsigned char w, unsigned char h);

/* Root-task collector. Applications must not call this function. */
void gb_timer_collect(void);

#endif
