/* App-linked drawing, state, focus, and hit testing for GBR object trees. */
#include "gb.h"
#include "gbr_object.h"

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

#ifndef GBR_RENDERER_ONLY
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
#endif

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

#ifdef GBR_GRAPHICS_RUNTIME
static unsigned char graphic_type(unsigned char type)
{
    return (unsigned char)(type == GBR_TYPE_ICON || type == GBR_TYPE_IMAGE);
}

static const gbr_graphic_binding_t *graphic_binding(
    const gbr_runtime_t *runtime, unsigned int spec)
{
    unsigned char index;
    for (index = 0; index < runtime->graphic_binding_count; index++)
        if (runtime->graphic_bindings[index].spec == spec)
            return &runtime->graphic_bindings[index];
    return 0;
}

static unsigned char graphic_ready(const gbr_runtime_t *runtime,
                                   const gbr_object_t *object)
{
    const gbr_graphic_binding_t *binding;
    if (runtime->graphics_context == 0 ||
        !gb_vdi_valid(runtime->graphics_context))
        return 0;
    binding = graphic_binding(runtime, object->spec);
    return (unsigned char)(binding != 0 &&
        gb_vdi_raster_valid(binding->raster) &&
        object->w == (unsigned int)binding->raster->width_cells * 4u &&
        object->h == binding->raster->height);
}
#endif

#ifdef GBR_FORM_RUNTIME
#ifndef GBR_RENDERER_ONLY
static unsigned char text_type(unsigned char type)
{
    return (unsigned char)(type == GBR_TYPE_TEXT || type == GBR_TYPE_STRING ||
                           type == GBR_TYPE_BUTTON || type == GBR_TYPE_FIELD ||
                           type == GBR_TYPE_CHECKBOX || type == GBR_TYPE_RADIO);
}
#endif

#ifndef GBR_RESIDENT_DRAW
static const char *text_override(const gbr_runtime_t *runtime,
                                 unsigned char object_index)
{
    unsigned char index;
    for (index = 0; index < runtime->text_binding_count; index++)
        if (runtime->text_bindings[index].object_index == object_index)
            return runtime->text_bindings[index].text;
    return 0;
}
#endif

static unsigned char bounded_override(const char *text)
{
    unsigned char length = 0;
    if (text == 0) return 0;
    while (length < GBR_TEXT_OVERRIDE_MAX && text[length]) length++;
    return (unsigned char)(text[length] == 0);
}
#endif

#ifndef GBR_RESIDENT_DRAW
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
    if (capacity == 0) return 0;
    buffer[0] = 0;
    if (spec == GBR_NONE16) return 1;
    if (spec >= runtime->resource->string_count ||
        !gbr_string_at(runtime->resource, (unsigned char)spec, &string))
        return 0;
    length = string.length;
    if (length >= capacity) length = (unsigned char)(capacity - 1u);
    if (length != 0 &&
        !gbr_read(runtime->resource, string.offset,
                  (unsigned char *)buffer, length))
        return 0;
    buffer[length] = 0;
    return 1;
}

static unsigned char copy_object_string(const gbr_runtime_t *runtime,
                                        unsigned char object_index,
                                        unsigned int spec, char *buffer,
                                        unsigned char capacity)
{
#ifdef GBR_FORM_RUNTIME
    const char *override = text_override(runtime, object_index);
    unsigned char length = 0;
    if (override == 0) return copy_string(runtime, spec, buffer, capacity);
    if (!bounded_override(override) || capacity == 0) return 0;
    while (override[length] && length + 1u < capacity) {
        buffer[length] = override[length];
        length++;
    }
    if (override[length]) return 0;
    buffer[length] = 0;
    return 1;
#else
    (void)object_index;
    return copy_string(runtime, spec, buffer, capacity);
#endif
}

#ifdef GBR_FORM_RUNTIME
static unsigned char draw_override(const char *text, const gbr_rect_t *rect,
                                   unsigned int state)
{
    char chunk[TEXT_CHUNK + 1u];
    unsigned int x = rect->x;
    unsigned char source = 0;
    unsigned char count;
    unsigned char index;
    if (!bounded_override(text)) return GBR_RT_ERR_OBJECT;
    while (text[source] && x < GB_XPIX) {
        count = 0;
        while (count < TEXT_CHUNK && text[source + count]) count++;
        for (index = 0; index < count; index++)
            chunk[index] = text[source + index];
        chunk[count] = 0;
        if (state & GBR_STATE_SELECTED)
            gb_textrev((unsigned char)(x >> 2), (unsigned char)rect->y, chunk);
        else
            gb_textbw((unsigned char)(x >> 2), (unsigned char)rect->y, chunk);
        source = (unsigned char)(source + count);
        x = (unsigned int)(x + count * 6u);
    }
    return GBR_RT_OK;
}
#endif

static unsigned char draw_text(const gbr_runtime_t *runtime,
                               unsigned char object_index,
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
#ifdef GBR_FORM_RUNTIME
    const char *override = text_override(runtime, object_index);
    if (override != 0) return draw_override(override, rect, state);
#else
    (void)object_index;
#endif
    if (object->spec == GBR_NONE16) return GBR_RT_OK;
    if (object->spec >= runtime->resource->string_count ||
        !gbr_string_at(runtime->resource, (unsigned char)object->spec, &string))
        return GBR_RT_ERR_OBJECT;
    source = string.offset;
    left = string.length;
    x = rect->x;
    while (left != 0 && x < GB_XPIX) {
        count = left > TEXT_CHUNK ? TEXT_CHUNK : (unsigned char)left;
        if (!gbr_read(runtime->resource, source,
                      (unsigned char *)chunk, count))
            return GBR_RT_ERR_OBJECT;
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

#if defined(GBR_FORM_RUNTIME) && !defined(GBR_M7_LEGACY_FORMS)
static void draw_choice(unsigned char x, unsigned char y,
                        unsigned char w, unsigned char h,
                        const char *label, unsigned int state,
                        unsigned char radio)
{
    unsigned char ty = y;
    unsigned char pen;
    if (h > 8u) ty = (unsigned char)(y + ((h - 8u + 1u) >> 1));
    pen = (state & GBR_STATE_DISABLED) ? GB_UI_SURFACE :
          (state & GBR_STATE_OUTLINED) ? GB_UI_ACCENT : GB_UI_EDGE;
    gb_fill(x, y, w, h, GB_UI_SURFACE);
    if (radio) {
        gb_frame(x, y, 4u, h, pen);
        gb_textbw(x, ty, (state & GBR_STATE_CHECKED) ? "(o)" : "( )");
        gb_textbw((unsigned char)(x + 5u), ty, label);
    } else {
        gb_frame(x, y, 3u, h, pen);
        if (state & GBR_STATE_CHECKED)
            gb_textbw((unsigned char)(x + 1u), ty, "x");
        gb_textbw((unsigned char)(x + 4u), ty, label);
    }
}
#endif

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
            gb_fill(x, y, w, h, GB_UI_SURFACE);
            gb_frame(x, y, w, h,
                     (unsigned char)((state & (GBR_STATE_SELECTED |
                                               GBR_STATE_OUTLINED))
                                         ? GB_UI_ACCENT : GB_UI_EDGE));
            return GBR_RT_OK;
        case GBR_TYPE_TEXT:
        case GBR_TYPE_STRING:
            if (rect.y >= GB_LINES) return GBR_RT_OK;
            return draw_text(runtime, object_index, &object, &rect, state);
        case GBR_TYPE_BUTTON:
            if (!screen_rect(&rect, &x, &y, &w, &h)) return GBR_RT_OK;
            if (!copy_object_string(runtime, object_index, object.spec,
                                    label, sizeof(label)))
                return GBR_RT_ERR_OBJECT;
            flags = 0;
            if (state & GBR_STATE_DISABLED) flags |= GB_WIDGET_DISABLED;
            if (state & GBR_STATE_SELECTED) flags |= GB_WIDGET_PRESSED;
            if ((state & GBR_STATE_OUTLINED) ||
                (object.flags & GBR_FLAG_DEFAULT))
                flags |= GB_WIDGET_FOCUSED;
            gb_button(x, y, w, h, label, flags);
            return GBR_RT_OK;
#ifdef GBR_GRAPHICS_RUNTIME
        case GBR_TYPE_ICON:
        case GBR_TYPE_IMAGE:
        {
            const gbr_graphic_binding_t *binding =
                graphic_binding(runtime, object.spec);
            if (binding == 0 || (rect.x & 3u) != 0 ||
                rect.x >= GB_XPIX || rect.y >= GB_LINES ||
                !gb_vdi_raster(runtime->graphics_context,
                               (unsigned char)(rect.x >> 2),
                               (unsigned char)rect.y, binding->raster))
                return GBR_RT_ERR_GRAPHIC;
            if (object.type == GBR_TYPE_ICON &&
                (state & (GBR_STATE_SELECTED | GBR_STATE_OUTLINED)) &&
                !gb_vdi_frame(runtime->graphics_context,
                              (unsigned char)(rect.x >> 2),
                              (unsigned char)rect.y,
                              (unsigned char)(rect.w >> 2),
                              (unsigned char)rect.h, GB_VDI_ROLE_ACCENT))
                return GBR_RT_ERR_GRAPHIC;
            return GBR_RT_OK;
        }
#endif
#ifdef GBR_FORM_RUNTIME
        case GBR_TYPE_FIELD:
            if (!screen_rect(&rect, &x, &y, &w, &h)) return GBR_RT_OK;
            if (!copy_object_string(runtime, object_index, object.spec,
                                    label, sizeof(label)))
                return GBR_RT_ERR_OBJECT;
            flags = 0;
            if (state & GBR_STATE_DISABLED) flags |= GB_WIDGET_DISABLED;
            if (state & GBR_STATE_OUTLINED) flags |= GB_WIDGET_FOCUSED;
            gb_field(x, y, w, h, label, flags);
            return GBR_RT_OK;
#ifndef GBR_M7_LEGACY_FORMS
        case GBR_TYPE_CHECKBOX:
        case GBR_TYPE_RADIO:
            if (!screen_rect(&rect, &x, &y, &w, &h)) return GBR_RT_OK;
            if (!copy_object_string(runtime, object_index, object.spec,
                                    label, sizeof(label)))
                return GBR_RT_ERR_OBJECT;
            draw_choice(x, y, w, h, label, state,
                        (unsigned char)(object.type == GBR_TYPE_RADIO ||
                                        (object.flags & GBR_FLAG_RADIO)));
            return GBR_RT_OK;
#endif
#endif
        default:
            return GBR_RT_ERR_UNSUPPORTED;
    }
}
#endif

#ifndef GBR_RENDERER_ONLY
unsigned char gbr_runtime_init(gbr_runtime_t *runtime,
                               const gbr_resource_t *resource,
                               unsigned char tree_index,
                               unsigned int *states,
                               unsigned char state_count)
{
    gbr_object_t object;
    unsigned int index;
    if (runtime == 0 || resource == 0 || states == 0)
        return GBR_RT_ERR_ARGUMENT;
    if (!gbr_tree_at(resource, tree_index, &runtime->tree))
        return GBR_RT_ERR_TREE;
    if (state_count < resource->object_count)
        return GBR_RT_ERR_STATE_BUFFER;
    runtime->resource = resource;
    runtime->states = states;
    runtime->state_count = state_count;
    runtime->text_bindings = 0;
    runtime->text_binding_count = 0;
#ifdef GBR_GRAPHICS_RUNTIME
    runtime->graphics_context = 0;
    runtime->graphic_bindings = 0;
    runtime->graphic_binding_count = 0;
#endif
    for (index = 0; index < resource->object_count; index++) {
        if (!gbr_object_at(resource, (unsigned char)index, &object))
            return GBR_RT_ERR_OBJECT;
        states[index] = object.state;
    }
    return GBR_RT_OK;
}
#endif

#if defined(GBR_GRAPHICS_RUNTIME) && !defined(GBR_RENDERER_ONLY)
unsigned char gbr_bind_graphics(gbr_runtime_t *runtime,
                                const gb_vdi_context_t *context,
                                const gbr_graphic_binding_t *bindings,
                                unsigned char binding_count)
{
    gbr_object_t object;
    const gbr_graphic_binding_t *binding;
    unsigned int index;
    unsigned int end;
    unsigned char current;
    unsigned char previous;
    unsigned char referenced;
    if (runtime == 0 || runtime->resource == 0 || !gb_vdi_valid(context) ||
        binding_count > runtime->tree.object_count ||
        (binding_count != 0 && bindings == 0))
        return 0;
    for (current = 0; current < binding_count; current++) {
        if (bindings[current].spec == GBR_NONE16 ||
            !gb_vdi_raster_valid(bindings[current].raster))
            return 0;
        for (previous = 0; previous < current; previous++)
            if (bindings[previous].spec == bindings[current].spec) return 0;
        referenced = 0;
        end = (unsigned int)runtime->tree.root + runtime->tree.object_count;
        for (index = runtime->tree.root; index < end; index++) {
            if (!gbr_object_at(runtime->resource, (unsigned char)index, &object))
                return 0;
            if (graphic_type(object.type) &&
                object.spec == bindings[current].spec)
                referenced = 1;
        }
        if (!referenced) return 0;
    }
    end = (unsigned int)runtime->tree.root + runtime->tree.object_count;
    for (index = runtime->tree.root; index < end; index++) {
        if (!gbr_object_at(runtime->resource, (unsigned char)index, &object))
            return 0;
        if (!graphic_type(object.type)) continue;
        binding = 0;
        for (current = 0; current < binding_count; current++)
            if (bindings[current].spec == object.spec) {
                binding = &bindings[current];
                break;
            }
        if (binding == 0 ||
            object.w != (unsigned int)binding->raster->width_cells * 4u ||
            object.h != binding->raster->height)
            return 0;
    }
    runtime->graphics_context = context;
    runtime->graphic_bindings = bindings;
    runtime->graphic_binding_count = binding_count;
    return 1;
}
#endif

#if defined(GBR_FORM_RUNTIME) && !defined(GBR_RENDERER_ONLY)
unsigned char gbr_bind_text(gbr_runtime_t *runtime,
                            const gbr_text_binding_t *bindings,
                            unsigned char binding_count)
{
    gbr_object_t object;
    unsigned char index;
    unsigned char previous;
    if (runtime == 0 || runtime->resource == 0) return 0;
    if (binding_count == 0) {
        runtime->text_bindings = 0;
        runtime->text_binding_count = 0;
        return 1;
    }
    if (bindings == 0 || binding_count > runtime->tree.object_count) return 0;
    for (index = 0; index < binding_count; index++) {
        if (!object_in_tree(runtime, bindings[index].object_index) ||
            !gbr_object_at(runtime->resource, bindings[index].object_index,
                           &object) ||
            !text_type(object.type) || !bounded_override(bindings[index].text))
            return 0;
        for (previous = 0; previous < index; previous++)
            if (bindings[previous].object_index == bindings[index].object_index)
                return 0;
    }
    runtime->text_bindings = bindings;
    runtime->text_binding_count = binding_count;
    return 1;
}
#endif

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

#ifndef GBR_RESIDENT_DRAW
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
#ifdef GBR_GRAPHICS_RUNTIME
        if (graphic_type(object.type)) {
            gbr_rect_t rect;
            if (!graphic_ready(runtime, &object) ||
                !gbr_object_rect(runtime, (unsigned char)index,
                                 root_x, root_y, &rect) ||
                (rect.x & 3u) != 0 || rect.x >= GB_XPIX ||
                rect.y >= GB_LINES || rect.w > GB_XPIX - rect.x ||
                rect.h > GB_LINES - rect.y)
                return GBR_RT_ERR_GRAPHIC;
        }
#endif
        if (object.type != GBR_TYPE_BOX && object.type != GBR_TYPE_TEXT &&
            object.type != GBR_TYPE_STRING && object.type != GBR_TYPE_BUTTON
#ifdef GBR_GRAPHICS_RUNTIME
            && object.type != GBR_TYPE_ICON && object.type != GBR_TYPE_IMAGE
#endif
#ifdef GBR_FORM_RUNTIME
            && object.type != GBR_TYPE_FIELD
#ifndef GBR_M7_LEGACY_FORMS
            && object.type != GBR_TYPE_CHECKBOX
            && object.type != GBR_TYPE_RADIO
#endif
#endif
            )
            return GBR_RT_ERR_UNSUPPORTED;
    }
    for (index = runtime->tree.root; index < end; index++) {
        if (object_blocked(runtime, (unsigned char)index, 0)) continue;
        result = draw_object(runtime, (unsigned char)index, root_x, root_y);
        if (result != GBR_RT_OK) return result;
    }
    return GBR_RT_OK;
}
#endif

#ifndef GBR_RENDERER_ONLY
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

#ifdef GBR_FORM_RUNTIME
static unsigned char focusable(const gbr_runtime_t *runtime,
                               unsigned char object_index)
{
    gbr_object_t object;
    return (unsigned char)(!object_blocked(runtime, object_index, 1) &&
                           gbr_object_at(runtime->resource, object_index,
                                         &object) &&
                           (object.flags & GBR_FLAG_SELECTABLE));
}

unsigned char gbr_focus_set(gbr_runtime_t *runtime,
                            unsigned char object_index)
{
    unsigned int index;
    unsigned int end;
    if (runtime == 0 || runtime->states == 0 ||
        !object_in_tree(runtime, object_index) ||
        !focusable(runtime, object_index))
        return 0;
    end = (unsigned int)runtime->tree.root + runtime->tree.object_count;
    for (index = runtime->tree.root; index < end; index++)
        runtime->states[index] &= (unsigned int)~GBR_STATE_OUTLINED;
    runtime->states[object_index] |= GBR_STATE_OUTLINED;
    return 1;
}

unsigned char gbr_focus_next(gbr_runtime_t *runtime,
                             unsigned char current,
                             unsigned char reverse,
                             unsigned char *object_index)
{
    unsigned int root;
    unsigned int end;
    unsigned int candidate;
    unsigned char steps;
    if (runtime == 0 || object_index == 0 || runtime->states == 0)
        return 0;
    *object_index = GBR_HIT_NONE;
    root = runtime->tree.root;
    end = root + runtime->tree.object_count;
    if ((unsigned int)current >= root && (unsigned int)current < end) {
        candidate = current;
        if (reverse)
            candidate = (candidate == root) ? end - 1u : candidate - 1u;
        else
            candidate = (candidate + 1u == end) ? root : candidate + 1u;
    } else {
        candidate = reverse ? end - 1u : root;
    }
    for (steps = 0; steps < runtime->tree.object_count; steps++) {
        if (focusable(runtime, (unsigned char)candidate)) {
            if (!gbr_focus_set(runtime, (unsigned char)candidate)) return 0;
            *object_index = (unsigned char)candidate;
            return 1;
        }
        if (reverse)
            candidate = (candidate == root) ? end - 1u : candidate - 1u;
        else
            candidate = (candidate + 1u == end) ? root : candidate + 1u;
    }
    return 0;
}

#endif
#endif
