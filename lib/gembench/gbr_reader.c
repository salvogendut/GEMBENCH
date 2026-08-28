/* Bounded, allocation-free reader for canonical GBR v1 resources.
 *
 * This source is compiled both by the host test suite and SDCC.  It deliberately
 * avoids packed structs and recursion: the on-disk ABI is read by byte offset,
 * and all graph walks are capped by the declared object count. */
#include "gbr.h"

static unsigned int read_u16(const unsigned char *data, unsigned int offset)
{
    return (unsigned int)data[offset] |
           ((unsigned int)data[(unsigned int)(offset + 1u)] << 8);
}

static void clear_resource(gbr_resource_t *resource)
{
    if (resource != 0) {
        resource->data = 0;
        resource->size = 0;
        resource->string_count = 0;
        resource->tree_count = 0;
        resource->object_count = 0;
        resource->string_index = 0;
        resource->tree_table = 0;
        resource->object_table = 0;
        resource->string_data = 0;
    }
}

static unsigned char byte_is_link(unsigned char value, unsigned char count)
{
    return (unsigned char)(value == GBR_NONE8 || value < count);
}

static unsigned char raw_tree(const gbr_resource_t *resource,
                              unsigned char index, gbr_tree_t *tree)
{
    unsigned int offset;
    if (resource == 0 || tree == 0 || resource->data == 0 ||
        index >= resource->tree_count)
        return 0;
    offset = (unsigned int)(resource->tree_table +
                            (unsigned int)index * GBR_TREE_RECORD_SIZE);
    tree->root = resource->data[offset + GBR_T_ROOT];
    tree->object_count = resource->data[offset + GBR_T_OBJECT_COUNT];
    tree->name = resource->data[offset + GBR_T_NAME];
    return 1;
}

static unsigned char raw_object(const gbr_resource_t *resource,
                                unsigned char index, gbr_object_t *object)
{
    unsigned int offset;
    if (resource == 0 || object == 0 || resource->data == 0 ||
        index >= resource->object_count)
        return 0;
    offset = (unsigned int)(resource->object_table +
                            (unsigned int)index * GBR_OBJECT_RECORD_SIZE);
    object->parent = resource->data[offset + GBR_O_PARENT];
    object->first_child = resource->data[offset + GBR_O_FIRST_CHILD];
    object->next_sibling = resource->data[offset + GBR_O_NEXT_SIBLING];
    object->type = resource->data[offset + GBR_O_TYPE];
    object->flags = read_u16(resource->data, offset + GBR_O_FLAGS);
    object->state = read_u16(resource->data, offset + GBR_O_STATE);
    object->spec = read_u16(resource->data, offset + GBR_O_SPEC);
    object->x = read_u16(resource->data, offset + GBR_O_X);
    object->y = resource->data[offset + GBR_O_Y];
    object->w = read_u16(resource->data, offset + GBR_O_W);
    object->h = resource->data[offset + GBR_O_H];
    return 1;
}

static unsigned char raw_string(const gbr_resource_t *resource,
                                unsigned char index, gbr_string_t *string)
{
    unsigned int entry;
    unsigned int offset;
    if (resource == 0 || string == 0 || resource->data == 0 ||
        index >= resource->string_count)
        return 0;
    entry = (unsigned int)(resource->string_index + (unsigned int)index * 2u);
    offset = read_u16(resource->data, entry);
    string->offset = (unsigned int)(offset + 1u);
    string->length = resource->data[offset];
    return 1;
}

unsigned char gbr_open(gbr_resource_t *resource,
                       const unsigned char *data, unsigned int size)
{
    gbr_resource_t candidate;
    gbr_tree_t tree;
    gbr_object_t object;
    gbr_object_t linked;
    unsigned int checksum;
    unsigned int expected;
    unsigned int offset;
    unsigned int end;
    unsigned int index;
    unsigned int tree_index;
    unsigned int next_root;
    unsigned int steps;
    unsigned char parent;
    unsigned char child;
    unsigned char sibling;

    if (resource == 0 || data == 0) return GBR_ERR_ARGUMENT;
    clear_resource(resource);
    if (size < GBR_HEADER_SIZE || size > GBR_MAX_FILE_SIZE)
        return GBR_ERR_SIZE;
    if (data[0] != 'G' || data[1] != 'B' || data[2] != 'R' || data[3] != '1')
        return GBR_ERR_MAGIC;
    if (data[GBR_H_VERSION] != GBR_VERSION) return GBR_ERR_VERSION;
    if (data[GBR_H_FLAGS] != 0 ||
        read_u16(data, GBR_H_HEADER_SIZE) != GBR_HEADER_SIZE ||
        read_u16(data, GBR_H_FILE_SIZE) != size || data[13] != 0)
        return GBR_ERR_HEADER;

    checksum = 0;
    for (index = 0; index < size; index++) {
        if (index != GBR_H_CHECKSUM && index != GBR_H_CHECKSUM + 1u)
            checksum = (unsigned int)((checksum + data[index]) & 0xffffu);
    }
    if (checksum != read_u16(data, GBR_H_CHECKSUM)) return GBR_ERR_CHECKSUM;

    candidate.data = data;
    candidate.size = size;
    candidate.string_count = data[GBR_H_STRING_COUNT];
    candidate.tree_count = data[GBR_H_TREE_COUNT];
    candidate.object_count = data[GBR_H_OBJECT_COUNT];
    candidate.string_index = read_u16(data, GBR_H_STRING_INDEX);
    candidate.tree_table = read_u16(data, GBR_H_TREE_TABLE);
    candidate.object_table = read_u16(data, GBR_H_OBJECT_TABLE);
    candidate.string_data = read_u16(data, GBR_H_STRING_DATA);
    if (candidate.string_count == 0 || candidate.tree_count == 0 ||
        candidate.object_count == 0)
        return GBR_ERR_LAYOUT;

    expected = (unsigned int)(GBR_HEADER_SIZE +
                              (unsigned int)candidate.string_count * 2u);
    if (candidate.string_index != GBR_HEADER_SIZE ||
        candidate.tree_table != expected)
        return GBR_ERR_LAYOUT;
    expected = (unsigned int)(expected +
                              (unsigned int)candidate.tree_count *
                                  GBR_TREE_RECORD_SIZE);
    if (candidate.object_table != expected) return GBR_ERR_LAYOUT;
    expected = (unsigned int)(expected +
                              (unsigned int)candidate.object_count *
                                  GBR_OBJECT_RECORD_SIZE);
    if (candidate.string_data != expected || candidate.string_data >= size)
        return GBR_ERR_LAYOUT;

    expected = candidate.string_data;
    for (index = 0; index < candidate.string_count; index++) {
        offset = read_u16(data, (unsigned int)(candidate.string_index + index * 2u));
        if (offset != expected || offset >= size) return GBR_ERR_STRING;
        end = (unsigned int)(offset + 1u + data[offset]);
        if (end > size) return GBR_ERR_STRING;
        offset++;
        while (offset < end) {
            if (data[offset] < 0x20u || data[offset] > 0x7eu)
                return GBR_ERR_STRING;
            offset++;
        }
        expected = end;
    }
    if (expected != size) return GBR_ERR_STRING;

    next_root = 0;
    for (tree_index = 0; tree_index < candidate.tree_count; tree_index++) {
        offset = (unsigned int)(candidate.tree_table +
                                tree_index * GBR_TREE_RECORD_SIZE);
        if (data[offset + 3u] != 0 || !raw_tree(&candidate, (unsigned char)tree_index, &tree))
            return GBR_ERR_TREE;
        end = (unsigned int)tree.root + tree.object_count;
        if (tree.object_count == 0 || tree.root != next_root ||
            end > candidate.object_count || tree.name >= candidate.string_count)
            return GBR_ERR_TREE;
        next_root = end;
    }
    if (next_root != candidate.object_count) return GBR_ERR_TREE;

    for (index = 0; index < candidate.object_count; index++) {
        if (!raw_object(&candidate, (unsigned char)index, &object))
            return GBR_ERR_OBJECT;
        if (object.type > GBR_TYPE_USER ||
            (object.flags & (unsigned int)~GBR_FLAG_MASK) != 0 ||
            (object.state & (unsigned int)~GBR_STATE_MASK) != 0 ||
            object.x > 511u || object.w > 511u)
            return GBR_ERR_OBJECT;
        if ((object.type == GBR_TYPE_TEXT || object.type == GBR_TYPE_STRING ||
             object.type == GBR_TYPE_BUTTON || object.type == GBR_TYPE_FIELD ||
             object.type == GBR_TYPE_CHECKBOX || object.type == GBR_TYPE_RADIO) &&
            object.spec != GBR_NONE16 && object.spec >= candidate.string_count)
            return GBR_ERR_OBJECT;
        if (!byte_is_link(object.parent, candidate.object_count) ||
            !byte_is_link(object.first_child, candidate.object_count) ||
            !byte_is_link(object.next_sibling, candidate.object_count))
            return GBR_ERR_LINK;
    }

    for (tree_index = 0; tree_index < candidate.tree_count; tree_index++) {
        (void)raw_tree(&candidate, (unsigned char)tree_index, &tree);
        end = (unsigned int)tree.root + tree.object_count;
        for (index = tree.root; index < end; index++) {
            (void)raw_object(&candidate, (unsigned char)index, &object);
            parent = object.parent;
            child = object.first_child;
            sibling = object.next_sibling;
            if (index == tree.root) {
                if (parent != GBR_NONE8 || sibling != GBR_NONE8)
                    return GBR_ERR_LINK;
            } else if (parent == GBR_NONE8 || parent < tree.root || parent >= index) {
                return GBR_ERR_LINK;
            }
            if (child != GBR_NONE8) {
                if (child <= index || child >= end ||
                    !raw_object(&candidate, child, &linked) || linked.parent != index)
                    return GBR_ERR_LINK;
            }
            if (sibling != GBR_NONE8) {
                if (sibling <= index || sibling >= end || parent == GBR_NONE8 ||
                    !raw_object(&candidate, sibling, &linked) || linked.parent != parent)
                    return GBR_ERR_LINK;
            }
            if (index != tree.root) {
                (void)raw_object(&candidate, parent, &linked);
                child = linked.first_child;
                steps = 0;
                while (child != GBR_NONE8 && child != index &&
                       steps < tree.object_count) {
                    (void)raw_object(&candidate, child, &linked);
                    child = linked.next_sibling;
                    steps++;
                }
                if (child != index) return GBR_ERR_LINK;
            }
        }
    }

    *resource = candidate;
    return GBR_OK;
}

unsigned char gbr_tree_at(const gbr_resource_t *resource,
                          unsigned char index, gbr_tree_t *tree)
{
    return raw_tree(resource, index, tree);
}

unsigned char gbr_object_at(const gbr_resource_t *resource,
                            unsigned char index, gbr_object_t *object)
{
    return raw_object(resource, index, object);
}

unsigned char gbr_string_at(const gbr_resource_t *resource,
                            unsigned char index, gbr_string_t *string)
{
    return raw_string(resource, index, string);
}

unsigned char gbr_find_tree(const gbr_resource_t *resource,
                            const char *name, unsigned char *index)
{
    gbr_tree_t tree;
    gbr_string_t string;
    unsigned int pos;
    unsigned int name_len;
    unsigned int tree_index;
    if (resource == 0 || resource->data == 0 || name == 0 || index == 0)
        return 0;
    name_len = 0;
    while (name[name_len] != 0 && name_len < 256u) name_len++;
    if (name_len > 255u) return 0;
    for (tree_index = 0; tree_index < resource->tree_count; tree_index++) {
        (void)raw_tree(resource, (unsigned char)tree_index, &tree);
        (void)raw_string(resource, tree.name, &string);
        if (name_len != string.length) continue;
        pos = 0;
        while (pos < name_len &&
               (unsigned char)name[pos] == resource->data[string.offset + pos])
            pos++;
        if (pos == name_len) {
            *index = (unsigned char)tree_index;
            return 1;
        }
    }
    return 0;
}
