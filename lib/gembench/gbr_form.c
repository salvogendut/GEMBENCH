/* Generic activation and navigation for validated GBR form trees.
 *
 * This unit is deliberately separate from gbr_object.c. Applications that only
 * draw or hit-test resource objects do not pay for form policy; GBR_FORM_ENGINE=1
 * opts into these helpers on top of GBR_FORMS=1.
 */
#include "gbr_object.h"

static unsigned char in_tree(const gbr_runtime_t *runtime,
                             unsigned char index)
{
    unsigned char end;
    if (runtime == 0 || runtime->resource == 0) return 0;
    end = (unsigned char)(runtime->tree.root + runtime->tree.object_count);
    return (unsigned char)(index >= runtime->tree.root && index < end);
}

static unsigned char blocked(const gbr_runtime_t *runtime,
                             unsigned char index)
{
    gbr_object_t object;
    unsigned char steps = 0;
    while (steps < runtime->tree.object_count) {
        if (!gbr_object_at(runtime->resource, index, &object)) return 1;
        if ((object.flags & GBR_FLAG_HIDDEN) ||
            (runtime->states[index] & GBR_STATE_DISABLED))
            return 1;
        if (index == runtime->tree.root) return 0;
        index = object.parent;
        steps++;
    }
    return 1;
}

static unsigned char focusable(const gbr_runtime_t *runtime,
                               unsigned char index, gbr_object_t *object)
{
    return (unsigned char)(in_tree(runtime, index) && !blocked(runtime, index) &&
                           gbr_object_at(runtime->resource, index, object) &&
                           (object->flags & GBR_FLAG_SELECTABLE));
}

static unsigned char radio_control(const gbr_object_t *object)
{
    return (unsigned char)(object->type == GBR_TYPE_RADIO ||
                           (object->flags & GBR_FLAG_RADIO));
}

static unsigned char form_find(const gbr_runtime_t *runtime,
                               unsigned int require_flags,
                               unsigned int reject_flags,
                               unsigned char *object_index)
{
    gbr_object_t object;
    unsigned char index;
    unsigned char end;
    if (runtime == 0 || object_index == 0) return 0;
    end = (unsigned char)(runtime->tree.root + runtime->tree.object_count);
    for (index = runtime->tree.root; index < end; index++) {
        if (!focusable(runtime, (unsigned char)index, &object) ||
            (object.flags & require_flags) != require_flags ||
            (object.flags & reject_flags) != 0)
            continue;
        *object_index = (unsigned char)index;
        return 1;
    }
    *object_index = GBR_HIT_NONE;
    return 0;
}

static unsigned char radio_next(gbr_runtime_t *runtime,
                                unsigned char current,
                                unsigned char reverse,
                                unsigned char *object_index)
{
    gbr_object_t base;
    gbr_object_t candidate_object;
    unsigned char root;
    unsigned char end;
    unsigned char candidate;
    unsigned char steps;
    if (runtime == 0 || object_index == 0 ||
        !focusable(runtime, current, &base) || !radio_control(&base))
        return 0;
    root = runtime->tree.root;
    end = root + runtime->tree.object_count;
    candidate = current;
    for (steps = 0; steps < runtime->tree.object_count; steps++) {
        if (reverse)
            candidate = (candidate == root) ? end - 1u : candidate - 1u;
        else
            candidate = (candidate + 1u == end) ? root : candidate + 1u;
        if (!focusable(runtime, (unsigned char)candidate, &candidate_object) ||
            candidate_object.parent != base.parent ||
            !radio_control(&candidate_object))
            continue;
        *object_index = (unsigned char)candidate;
        return 1;
    }
    *object_index = GBR_HIT_NONE;
    return 0;
}

unsigned char gbr_form_activate(gbr_runtime_t *runtime,
                                unsigned char object_index)
{
    gbr_object_t object;
    gbr_object_t candidate;
    unsigned char index;
    unsigned char end;
    unsigned char result;
    if (runtime == 0 || !focusable(runtime, object_index, &object) ||
        !gbr_focus_set(runtime, object_index))
        return GBR_FORM_NONE;

    result = (unsigned char)(GBR_FORM_HANDLED | GBR_FORM_REDRAW |
                             GBR_FORM_ACTIVATED);
    if (radio_control(&object)) {
        end = (unsigned char)(runtime->tree.root + runtime->tree.object_count);
        for (index = runtime->tree.root; index < end; index++) {
            if (!gbr_object_at(runtime->resource, (unsigned char)index,
                               &candidate) ||
                candidate.parent != object.parent ||
                !radio_control(&candidate))
                continue;
            runtime->states[index] &= (unsigned int)~GBR_STATE_CHECKED;
        }
        runtime->states[object_index] |= GBR_STATE_CHECKED;
    } else if (object.type == GBR_TYPE_CHECKBOX) {
        runtime->states[object_index] ^= GBR_STATE_CHECKED;
    }
    if (object.flags & GBR_FLAG_EXIT) result |= GBR_FORM_EXIT;
    return result;
}

unsigned char gbr_form_click(gbr_runtime_t *runtime,
                             unsigned int root_x, unsigned int root_y,
                             unsigned int pointer_x, unsigned int pointer_y,
                             unsigned char *object_index)
{
    if (object_index == 0 ||
        !gbr_hit_test(runtime, root_x, root_y, pointer_x, pointer_y,
                      object_index))
        return GBR_FORM_NONE;
    return gbr_form_activate(runtime, *object_index);
}

unsigned char gbr_form_key(gbr_runtime_t *runtime,
                           unsigned char current, unsigned char key,
                           unsigned char reverse,
                           unsigned char *object_index)
{
    gbr_object_t current_object;
    unsigned char target = GBR_HIT_NONE;
    if (object_index == 0) return GBR_FORM_NONE;
    *object_index = GBR_HIT_NONE;
    if (key == GBR_KEY_TAB) {
        if (!gbr_focus_next(runtime, current, reverse, &target))
            return GBR_FORM_NONE;
        *object_index = target;
        return (unsigned char)(GBR_FORM_HANDLED | GBR_FORM_REDRAW);
    }
    if (key == GBR_KEY_ENTER) {
        if (in_tree(runtime, current) &&
            gbr_object_at(runtime->resource, current, &current_object) &&
            (current_object.type == GBR_TYPE_BUTTON ||
             current_object.type == GBR_TYPE_CHECKBOX ||
             current_object.type == GBR_TYPE_RADIO))
            target = current;
        else if (!form_find(runtime, GBR_FLAG_DEFAULT, 0, &target))
            target = current;
    } else if (key == GBR_KEY_ESCAPE) {
        if (!form_find(runtime, GBR_FLAG_EXIT, GBR_FLAG_DEFAULT, &target))
            return GBR_FORM_NONE;
    } else if (key == ' ') {
        target = current;
    } else if (key == GBR_KEY_LEFT || key == GBR_KEY_UP ||
               key == GBR_KEY_RIGHT || key == GBR_KEY_DOWN) {
        reverse = (unsigned char)(key == GBR_KEY_LEFT || key == GBR_KEY_UP);
        if (!radio_next(runtime, current, reverse, &target))
            return GBR_FORM_NONE;
    } else {
        return GBR_FORM_NONE;
    }
    if (!in_tree(runtime, target)) return GBR_FORM_NONE;
    *object_index = target;
    return gbr_form_activate(runtime, target);
}
