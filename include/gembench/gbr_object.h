#ifndef GEMBENCH_GBR_OBJECT_H
#define GEMBENCH_GBR_OBJECT_H

#include "gbr.h"

#define GBR_RT_OK                  0u
#define GBR_RT_ERR_ARGUMENT        1u
#define GBR_RT_ERR_TREE            2u
#define GBR_RT_ERR_STATE_BUFFER    3u
#define GBR_RT_ERR_OBJECT          4u
#define GBR_RT_ERR_COORDINATE      5u
#define GBR_RT_ERR_UNSUPPORTED     6u

#define GBR_HIT_NONE             255u

typedef struct gbr_rect {
    unsigned int x;
    unsigned int y;
    unsigned int w;
    unsigned int h;
} gbr_rect_t;

/* Mutable object state lives outside the immutable resource. The caller owns
 * one unsigned-int slot per resource object, which is normally application RAM
 * while a larger GBR payload may reside in a temporarily mapped segment. */
typedef struct gbr_runtime {
    const gbr_resource_t *resource;
    gbr_tree_t tree;
    unsigned int *states;
    unsigned char state_count;
} gbr_runtime_t;

unsigned char gbr_runtime_init(gbr_runtime_t *runtime,
                               const gbr_resource_t *resource,
                               unsigned char tree_index,
                               unsigned int *states,
                               unsigned char state_count);
unsigned char gbr_object_rect(const gbr_runtime_t *runtime,
                              unsigned char object_index,
                              unsigned int root_x, unsigned int root_y,
                              gbr_rect_t *rect);
unsigned char gbr_draw_tree(const gbr_runtime_t *runtime,
                            unsigned int root_x, unsigned int root_y);
unsigned char gbr_hit_test(const gbr_runtime_t *runtime,
                           unsigned int root_x, unsigned int root_y,
                           unsigned int pointer_x, unsigned int pointer_y,
                           unsigned char *object_index);
unsigned char gbr_state_change(gbr_runtime_t *runtime,
                               unsigned char object_index,
                               unsigned int set_bits,
                               unsigned int clear_bits);
unsigned int gbr_state(const gbr_runtime_t *runtime,
                       unsigned char object_index);

#endif
