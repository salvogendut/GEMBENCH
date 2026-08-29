#ifndef GEMBENCH_GBREGION_H
#define GEMBENCH_GBREGION_H

/*
 * Bounded visible-region iteration for an existing WM repaint callback.
 *
 * The iterator snapshots the current damage clip, intersects it with the
 * calling window, then subtracts opaque windows above it.  All storage belongs
 * to the caller.  If four rectangles are insufficient, iteration falls back
 * atomically to the original single damage rectangle.
 */

#define GB_VISIBLE_CAPACITY 4u

typedef struct {
    unsigned char x;
    unsigned char y;
    unsigned char w;
    unsigned char h;
} gb_visible_rect_t;

typedef struct {
    gb_visible_rect_t regions[GB_VISIBLE_CAPACITY];
    gb_visible_rect_t work[GB_VISIBLE_CAPACITY];
    gb_visible_rect_t damage;
    unsigned char count;
    unsigned char index;
    unsigned char overflow;
    unsigned char active;
} gb_visible_state_t;

/*
 * Begin iteration and install the first visible rectangle as the active draw
 * clip.  Returns zero when the calling window is completely covered.  A table
 * inconsistency safely yields one iteration using the original damage clip.
 */
unsigned char gb_visible_begin(gb_visible_state_t *state);

/*
 * Advance to the next rectangle and install its clip.  On exhaustion, restore
 * the original damage clip and return zero.
 */
unsigned char gb_visible_next(gb_visible_state_t *state);

/* Restore the original damage clip after an early exit. */
void gb_visible_end(gb_visible_state_t *state);

#endif
