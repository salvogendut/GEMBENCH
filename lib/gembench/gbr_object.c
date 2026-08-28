/* App-linked object drawing and hit testing for the first GEMBENCH GBR slice.
 * Supported visible types are box, text/string, and button. */
#include "gb.h"
#include "gbr_object.h"

#define UI_SURFACE 1u
#define UI_EDGE    2u
#define UI_ACCENT  3u

#define TEXT_CHUNK 16u
#define BUTTON_TEXT_MAX 31u

static unsigned char object_in_tree(const gbr_runtime_t *runtime,
                                    unsigned char index)
{
    unsigned int end;
    if (runtime == 0 || runtime->resource == 0) return 0;
    end = (unsigned int)runtime->tree.root + runtime->tree.object_count;
    return (unsigned char)(index >= runtime->tree.root && index < end);
}

static unsigned char add_coordinate(unsigned int *value, unsigned int add)
{
    if (*value > (unsigned int)(0xffffu - add)) return 0;
    *value = (unsigned int)(*value + add);
    return 1;
}

static unsigned char object_depth(const gbr_runtime_t *runtime,
                                  unsigned char index,
                                  unsigned char *depth)
{
    gbr_object_t object;
    unsigned int steps = 0;
    *depth = 0;
    while (index != runtime->tree.root && steps < runtime->tree.object_count) {
        if (!gbr_object_at(runtime->resource, index, &object)) return 0;
        index = object.parent;
        (*depth)++;
        steps++;
    }
    return (unsigned char)(index == runtime->tree.root);
}

static unsigned char object_blocked(const gbr_runtime_t *runtime,
                                    unsigned char index,
                                    unsigned char include_disabled)
{
    gbr_object_t object;
    unsigned int steps = 0;
    while (steps < runtime->tree.object_count) {
        if (!gbr_object_at(runtime->resource, index, &object)) return 1;
        if (object.flags & GBR_FLAG_HIDDEN) return 1;
        if (include_disabled &&
            (runtime->states[index] & GBR_STATE_DISABLED)) return 1;
        if (index == runtime->tree.root) return 0;
        index = object.parent;
        steps++;
    }
    return 1;
}

static unsigned char screen_rect(const gbr_rect_t *rect,
                                 unsigned char *x, unsigned char *y,
                                 unsigned char *w, unsigned char *h)
{
    unsigned int right;
    unsigned int bottom;
    unsigned int left_col;
    unsigned int right_col;
    if (rect->w == 0 || rect->h == 0 || rect->x >= GB_XPIX ||
        rect->y >= GB_LINES)
        return 0;
    right = (unsigned int)(rect->x + rect->w);
    bottom = (unsigned int)(rect->y + rect->h);
    if (right < rect->x || bottom < rect->y) return 0;
    if (right > GB_XPIX) right = GB_XPIX;
    if (bottom > GB_LINES) bottom = GB_LINES;
    left_col = rect->x >> 2;
    right_col = (unsigned int)((right + 3u) >> 2);
    if (right_col <= left_col || bottom <= rect->y) return 0;
    *x = (unsigned char)left_col;
    *y = (unsigned char)rect->y;
    *w = (unsigned char)(right_col - left_col);
    *h = (unsigned char)(bottom - rect->y);
    return 1;
}

static unsigned char copy_string(const gbr_runtime_t *runtime,
                                 unsigned int spec, char *buffer,
                                 unsigned char capacity)
{
    gbr_string_t string;
    unsigned char length;
    unsigned char index;
    if (capacity == 0) return 0;
    buffer[0] = 0;
    if (spec == GBR_NONE16) return 1;
    if (spec >= runtime->resource->string_count ||
        !gbr_string_at(runtime->resource, (unsigned char)spec, &string))
        return 0;
    length = string.length;
    if (length >= capacity) length = (unsigned char)(capacity - 1u);
    for (index = 0; index < length; index++)
        buffer[index] = (char)runtime->resource->data[string.offset + index];
    buffer[length] = 0;
    return 1;
}

static unsigned char draw_text(const gbr_runtime_t *runtime,
                               const gbr_object_t *object,
                               const gbr_rect_t *rect,
                               unsigned int state)
{
    gbr_string_t string;
    char chunk[TEXT_CHUNK + 1u];
    unsigned int source;
    unsigned int left;
    unsigned int x;
    unsigned char count;
    unsigned char index;
    if (object->spec == GBR_NONE16) return GBR_RT_OK;
    if (object->spec >= runtime->resource->string_count ||
        !gbr_string_at(runtime->resource, (unsigned char)object->spec, &string))
        return GBR_RT_ERR_OBJECT;
    source = string.offset;
    left = string.length;
    x = rect->x;
    while (left != 0 && x < GB_XPIX) {
        count = left > TEXT_CHUNK ? TEXT_CHUNK : (unsigned char)left;
        for (index = 0; index < count; index++)
            chunk[index] = (char)runtime->resource->data[source + index];
        chunk[count] = 0;
        if (state & GBR_STATE_SELECTED)
            gb_textrev((unsigned char)(x >> 2), (unsigned char)rect->y, chunk);
        else
            gb_textbw((unsigned char)(x >> 2), (unsigned char)rect->y, chunk);
        source = (unsigned int)(source + count);
        left = (unsigned int)(left - count);
        x = (unsigned int)(x + count * 6u);
    }
    return GBR_RT_OK;
}

static unsigned char draw_object(const gbr_runtime_t *runtime,
                                 unsigned char object_index,
                                 unsigned int root_x, unsigned int root_y)
{
    gbr_object_t object;
    gbr_rect_t rect;
    unsigned int state;
    unsigned char x, y, w, h;
    unsigned char flags;
    char label[BUTTON_TEXT_MAX + 1u];
    if (!gbr_object_at(runtime->resource, object_index, &object) ||
        !gbr_object_rect(runtime, object_index, root_x, root_y, &rect))
        return GBR_RT_ERR_OBJECT;
    state = runtime->states[object_index];
    switch (object.type) {
        case GBR_TYPE_BOX:
            if (!screen_rect(&rect, &x, &y, &w, &h)) return GBR_RT_OK;
            gb_fill(x, y, w, h, UI_SURFACE);
            gb_frame(x, y, w, h,
                     (unsigned char)((state & (GBR_STATE_SELECTED |
                                               GBR_STATE_OUTLINED))
                                         ? UI_ACCENT : UI_EDGE));
            return GBR_RT_OK;
        case GBR_TYPE_TEXT:
        case GBR_TYPE_STRING:
            if (rect.y >= GB_LINES) return GBR_RT_OK;
            return draw_text(runtime, &object, &rect, state);
        case GBR_TYPE_BUTTON:
            if (!screen_rect(&rect, &x, &y, &w, &h)) return GBR_RT_OK;
            if (!copy_string(runtime, object.spec, label, sizeof(label)))
                return GBR_RT_ERR_OBJECT;
            flags = 0;
            if (state & GBR_STATE_DISABLED) flags |= GB_WIDGET_DISABLED;
            if (state & GBR_STATE_SELECTED) flags |= GB_WIDGET_PRESSED;
            if (state & GBR_STATE_OUTLINED) flags |= GB_WIDGET_FOCUSED;
            gb_button(x, y, w, h, label, flags);
            return GBR_RT_OK;
        default:
            return GBR_RT_ERR_UNSUPPORTED;
    }
}

unsigned char gbr_runtime_init(gbr_runtime_t *runtime,
                               const gbr_resource_t *resource,
                               unsigned char tree_index,
                               unsigned int *states,
                               unsigned char state_count)
{
    gbr_object_t object;
    unsigned int index;
    if (runtime == 0 || resource == 0 || resource->data == 0 || states == 0)
        return GBR_RT_ERR_ARGUMENT;
    if (!gbr_tree_at(resource, tree_index, &runtime->tree))
        return GBR_RT_ERR_TREE;
    if (state_count < resource->object_count)
        return GBR_RT_ERR_STATE_BUFFER;
    runtime->resource = resource;
    runtime->states = states;
    runtime->state_count = state_count;
    for (index = 0; index < resource->object_count; index++) {
        if (!gbr_object_at(resource, (unsigned char)index, &object))
            return GBR_RT_ERR_OBJECT;
        states[index] = object.state;
    }
    return GBR_RT_OK;
}

unsigned char gbr_object_rect(const gbr_runtime_t *runtime,
                              unsigned char object_index,
                              unsigned int root_x, unsigned int root_y,
                              gbr_rect_t *rect)
{
    gbr_object_t object;
    unsigned int steps = 0;
    if (runtime == 0 || rect == 0 || !object_in_tree(runtime, object_index) ||
        !gbr_object_at(runtime->resource, object_index, &object))
        return 0;
    rect->x = root_x;
    rect->y = root_y;
    rect->w = object.w;
    rect->h = object.h;
    while (object_index != runtime->tree.root &&
           steps < runtime->tree.object_count) {
        if (!add_coordinate(&rect->x, object.x) ||
            !add_coordinate(&rect->y, object.y))
            return 0;
        object_index = object.parent;
        if (!gbr_object_at(runtime->resource, object_index, &object)) return 0;
        steps++;
    }
    return (unsigned char)(object_index == runtime->tree.root);
}

unsigned char gbr_draw_tree(const gbr_runtime_t *runtime,
                            unsigned int root_x, unsigned int root_y)
{
    gbr_object_t object;
    unsigned int index;
    unsigned int end;
    unsigned char result;
    if (runtime == 0 || runtime->resource == 0 || runtime->states == 0)
        return GBR_RT_ERR_ARGUMENT;
    end = (unsigned int)runtime->tree.root + runtime->tree.object_count;
    for (index = runtime->tree.root; index < end; index++) {
        if (object_blocked(runtime, (unsigned char)index, 0)) continue;
        if (!gbr_object_at(runtime->resource, (unsigned char)index, &object))
            return GBR_RT_ERR_OBJECT;
        if (object.type != GBR_TYPE_BOX && object.type != GBR_TYPE_TEXT &&
            object.type != GBR_TYPE_STRING && object.type != GBR_TYPE_BUTTON)
            return GBR_RT_ERR_UNSUPPORTED;
    }
    for (index = runtime->tree.root; index < end; index++) {
        if (object_blocked(runtime, (unsigned char)index, 0)) continue;
        result = draw_object(runtime, (unsigned char)index, root_x, root_y);
        if (result != GBR_RT_OK) return result;
    }
    return GBR_RT_OK;
}

unsigned char gbr_hit_test(const gbr_runtime_t *runtime,
                           unsigned int root_x, unsigned int root_y,
                           unsigned int pointer_x, unsigned int pointer_y,
                           unsigned char *object_index)
{
    gbr_object_t object;
    gbr_rect_t rect;
    unsigned int index;
    unsigned int end;
    unsigned int right;
    unsigned int bottom;
    unsigned char depth;
    unsigned char best_depth = 0;
    unsigned char found = 0;
    if (runtime == 0 || object_index == 0) return 0;
    *object_index = GBR_HIT_NONE;
    end = (unsigned int)runtime->tree.root + runtime->tree.object_count;
    for (index = runtime->tree.root; index < end; index++) {
        if (object_blocked(runtime, (unsigned char)index, 1) ||
            !gbr_object_at(runtime->resource, (unsigned char)index, &object) ||
            !(object.flags & GBR_FLAG_SELECTABLE) ||
            !gbr_object_rect(runtime, (unsigned char)index, root_x, root_y, &rect))
            continue;
        right = (unsigned int)(rect.x + rect.w);
        bottom = (unsigned int)(rect.y + rect.h);
        if (right < rect.x || bottom < rect.y || pointer_x < rect.x ||
            pointer_x >= right || pointer_y < rect.y || pointer_y >= bottom)
            continue;
        if (!object_depth(runtime, (unsigned char)index, &depth)) continue;
        if (!found || depth >= best_depth) {
            found = 1;
            best_depth = depth;
            *object_index = (unsigned char)index;
        }
    }
    return found;
}

unsigned char gbr_state_change(gbr_runtime_t *runtime,
                               unsigned char object_index,
                               unsigned int set_bits,
                               unsigned int clear_bits)
{
    if (runtime == 0 || runtime->states == 0 ||
        !object_in_tree(runtime, object_index) ||
        ((set_bits | clear_bits) & (unsigned int)~GBR_STATE_MASK) != 0)
        return 0;
    runtime->states[object_index] =
        (unsigned int)((runtime->states[object_index] | set_bits) & ~clear_bits);
    return 1;
}

unsigned int gbr_state(const gbr_runtime_t *runtime,
                       unsigned char object_index)
{
    if (runtime == 0 || runtime->states == 0 ||
        !object_in_tree(runtime, object_index))
        return 0;
    return runtime->states[object_index];
}
