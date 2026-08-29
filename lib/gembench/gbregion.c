#include "gbregion.h"

#define GB_BANK_CUR 0x134Fu
#define GB_CLIP_X   0x1338u
#define GB_CLIP_Y   0x1339u
#define GB_CLIP_W   0x133Au
#define GB_CLIP_H   0x133Bu
#define GB_WM_NWIN  0x1350u
#define GB_WM_TABLE 0x1352u
#define GB_WM_Z     0x141Au
#define GB_WM_ESZ   25u
#define GB_WM_MAX   8u

#ifdef GB_REGION_HOST_TEST
extern unsigned char gb_region_host_memory[65536];
#define GB_MEM8(address) gb_region_host_memory[(unsigned int)(address)]
#else
#define GB_MEM8(address) (*(volatile unsigned char *)(address))
#endif

static void rect_copy(gb_visible_rect_t *destination,
                      const gb_visible_rect_t *source)
{
    destination->x = source->x;
    destination->y = source->y;
    destination->w = source->w;
    destination->h = source->h;
}

static unsigned char rect_intersect(const gb_visible_rect_t *a,
                                    const gb_visible_rect_t *b,
                                    gb_visible_rect_t *result)
{
    unsigned char left = a->x > b->x ? a->x : b->x;
    unsigned char top = a->y > b->y ? a->y : b->y;
    unsigned char ar = (unsigned char)(a->x + a->w);
    unsigned char br = (unsigned char)(b->x + b->w);
    unsigned char ab = (unsigned char)(a->y + a->h);
    unsigned char bb = (unsigned char)(b->y + b->h);
    unsigned char right = ar < br ? ar : br;
    unsigned char bottom = ab < bb ? ab : bb;

    if (right <= left || bottom <= top) return 0;
    result->x = left;
    result->y = top;
    result->w = (unsigned char)(right - left);
    result->h = (unsigned char)(bottom - top);
    return 1;
}

static unsigned int wm_entry(unsigned char slot)
{
    unsigned int address = GB_WM_TABLE;
    while (slot--) address += GB_WM_ESZ;
    return address;
}

static void memory_rect(unsigned int address, gb_visible_rect_t *rect)
{
    rect->x = GB_MEM8(address);
    rect->y = GB_MEM8(address + 1u);
    rect->w = GB_MEM8(address + 2u);
    rect->h = GB_MEM8(address + 3u);
}

static void clip_rect(const gb_visible_rect_t *rect)
{
    GB_MEM8(GB_CLIP_X) = rect->x;
    GB_MEM8(GB_CLIP_Y) = rect->y;
    GB_MEM8(GB_CLIP_W) = rect->w;
    GB_MEM8(GB_CLIP_H) = rect->h;
}

static unsigned char emit(gb_visible_state_t *state,
                          unsigned char *count,
                          const gb_visible_rect_t *rect)
{
    if (!rect->w || !rect->h) return 1;
    if (*count >= GB_VISIBLE_CAPACITY) return 0;
    rect_copy(&state->work[*count], rect);
    (*count)++;
    return 1;
}

static unsigned char subtract_cover(gb_visible_state_t *state,
                                    const gb_visible_rect_t *cover)
{
    unsigned char i;
    unsigned char next_count = 0;
    gb_visible_rect_t source;
    gb_visible_rect_t intersection;
    gb_visible_rect_t piece;

    for (i = 0; i < state->count; i++) {
        rect_copy(&source, &state->regions[i]);
        if (!rect_intersect(&source, cover, &intersection)) {
            if (!emit(state, &next_count, &source)) return 0;
            continue;
        }

        piece.x = source.x;
        piece.y = source.y;
        piece.w = source.w;
        piece.h = (unsigned char)(intersection.y - source.y);
        if (!emit(state, &next_count, &piece)) return 0;

        piece.x = source.x;
        piece.y = (unsigned char)(intersection.y + intersection.h);
        piece.w = source.w;
        piece.h = (unsigned char)(source.y + source.h - piece.y);
        if (!emit(state, &next_count, &piece)) return 0;

        piece.x = source.x;
        piece.y = intersection.y;
        piece.w = (unsigned char)(intersection.x - source.x);
        piece.h = intersection.h;
        if (!emit(state, &next_count, &piece)) return 0;

        piece.x = (unsigned char)(intersection.x + intersection.w);
        piece.y = intersection.y;
        piece.w = (unsigned char)(source.x + source.w - piece.x);
        piece.h = intersection.h;
        if (!emit(state, &next_count, &piece)) return 0;
    }

    state->count = next_count;
    for (i = 0; i < next_count; i++)
        rect_copy(&state->regions[i], &state->work[i]);
    return 1;
}

static unsigned char damage_fallback(gb_visible_state_t *state)
{
    state->count = 1;
    state->index = 0;
    rect_copy(&state->regions[0], &state->damage);
    state->active = 1;
    clip_rect(&state->regions[0]);
    return 1;
}

unsigned char gb_visible_begin(gb_visible_state_t *state)
{
    unsigned char nwin;
    unsigned char z;
    unsigned char slot;
    unsigned char current_z = 0xFFu;
    unsigned char page;
    unsigned int entry;
    gb_visible_rect_t window;
    gb_visible_rect_t cover;

    if (!state) return 0;
    state->count = 0;
    state->index = 0;
    state->overflow = 0;
    state->active = 0;
    state->damage.x = GB_MEM8(GB_CLIP_X);
    state->damage.y = GB_MEM8(GB_CLIP_Y);
    state->damage.w = GB_MEM8(GB_CLIP_W);
    state->damage.h = GB_MEM8(GB_CLIP_H);
    if (!state->damage.w || !state->damage.h) return 0;

    nwin = GB_MEM8(GB_WM_NWIN);
    if (!nwin || nwin > GB_WM_MAX) return damage_fallback(state);
    page = GB_MEM8(GB_BANK_CUR);
    for (z = 0; z < nwin; z++) {
        slot = GB_MEM8(GB_WM_Z + z);
        if (slot >= GB_WM_MAX) return damage_fallback(state);
        entry = wm_entry(slot);
        if (GB_MEM8(entry) == page) {
            /* A page normally owns one legacy window.  Do not guess if an
               application registered two windows from the same page. */
            if (current_z != 0xFFu) return damage_fallback(state);
            current_z = z;
        }
    }
    if (current_z == 0xFFu) return damage_fallback(state);

    entry = wm_entry(GB_MEM8(GB_WM_Z + current_z));
    memory_rect(entry + 1u, &window);
    if (!rect_intersect(&state->damage, &window, &state->regions[0])) return 0;
    state->count = 1;

    for (z = (unsigned char)(current_z + 1u); z < nwin; z++) {
        slot = GB_MEM8(GB_WM_Z + z);
        if (slot >= GB_WM_MAX) return damage_fallback(state);
        entry = wm_entry(slot);
        memory_rect(entry + 1u, &cover);
        if (!subtract_cover(state, &cover)) {
            state->overflow = 1;
            return damage_fallback(state);
        }
        if (!state->count) return 0;
    }

    state->active = 1;
    clip_rect(&state->regions[0]);
    return 1;
}

void gb_visible_end(gb_visible_state_t *state)
{
    if (!state || !state->active) return;
    clip_rect(&state->damage);
    state->active = 0;
}

unsigned char gb_visible_next(gb_visible_state_t *state)
{
    if (!state || !state->active) return 0;
    state->index++;
    if (state->index < state->count) {
        clip_rect(&state->regions[state->index]);
        return 1;
    }
    gb_visible_end(state);
    return 0;
}
