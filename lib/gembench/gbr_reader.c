/* Bounded, allocation-free reader for canonical GBR v1 resources.
 *
 * This source is compiled both by the host test suite and SDCC. It deliberately
 * avoids packed structs and recursion. Resource bytes may either be in the
 * caller's application page or in an MSX2 mapper segment reached through the
 * kernel's bounded-copy service. */
#include "gbr.h"

#ifdef GBR_BANKED
#include "gbr_bank.h"
#endif

#define GBR_READ_CHUNK 32u

static unsigned int read_u16_memory(const unsigned char *data,
                                    unsigned int offset)
{
    return (unsigned int)data[offset] |
           ((unsigned int)data[(unsigned int)(offset + 1u)] << 8);
}

static unsigned char resource_storage_valid(const gbr_resource_t *resource)
{
    if (resource == 0) return 0;
    if (resource->storage == GBR_STORAGE_MEMORY)
        return (unsigned char)(resource->data != 0);
#ifdef GBR_BANKED
    if (resource->storage == GBR_STORAGE_SEGMENT)
        return (unsigned char)(resource->segment != 0);
#endif
    return 0;
}

unsigned char gbr_read(const gbr_resource_t *resource,
                       unsigned int offset, unsigned char *data,
                       unsigned char length)
{
    unsigned int end;
    unsigned char index;
    if (!resource_storage_valid(resource) || data == 0) return 0;
    end = (unsigned int)(offset + length);
    if (end < offset || end > resource->size) return 0;
    if (length == 0) return 1;
#ifdef GBR_BANKED
    if (resource->storage == GBR_STORAGE_SEGMENT)
        return gbr_segment_read(resource->segment, offset, data, length);
#endif
    for (index = 0; index < length; index++)
        data[index] = resource->data[(unsigned int)(offset + index)];
    return 1;
}

#ifndef GBR_READER_ACCESS_ONLY
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
        resource->storage = GBR_STORAGE_MEMORY;
        resource->segment = 0;
    }
}

static unsigned char byte_is_link(unsigned char value, unsigned char count)
{
    return (unsigned char)(value == GBR_NONE8 || value < count);
}
#endif

static unsigned char raw_tree(const gbr_resource_t *resource,
                              unsigned char index, gbr_tree_t *tree)
{
    unsigned char data[GBR_TREE_RECORD_SIZE];
    unsigned int offset;
    if (resource == 0 || tree == 0 || index >= resource->tree_count)
        return 0;
    offset = (unsigned int)(resource->tree_table +
                            (unsigned int)index * GBR_TREE_RECORD_SIZE);
    if (!gbr_read(resource, offset, data, GBR_TREE_RECORD_SIZE)) return 0;
    tree->root = data[GBR_T_ROOT];
    tree->object_count = data[GBR_T_OBJECT_COUNT];
    tree->name = data[GBR_T_NAME];
    return 1;
}

static unsigned char raw_object(const gbr_resource_t *resource,
                                unsigned char index, gbr_object_t *object)
{
    unsigned char data[GBR_OBJECT_RECORD_SIZE];
    unsigned int offset;
    if (resource == 0 || object == 0 || index >= resource->object_count)
        return 0;
    offset = (unsigned int)(resource->object_table +
                            (unsigned int)index * GBR_OBJECT_RECORD_SIZE);
    if (!gbr_read(resource, offset, data, GBR_OBJECT_RECORD_SIZE)) return 0;
    object->parent = data[GBR_O_PARENT];
    object->first_child = data[GBR_O_FIRST_CHILD];
    object->next_sibling = data[GBR_O_NEXT_SIBLING];
    object->type = data[GBR_O_TYPE];
    object->flags = read_u16_memory(data, GBR_O_FLAGS);
    object->state = read_u16_memory(data, GBR_O_STATE);
    object->spec = read_u16_memory(data, GBR_O_SPEC);
    object->x = read_u16_memory(data, GBR_O_X);
    object->y = data[GBR_O_Y];
    object->w = read_u16_memory(data, GBR_O_W);
    object->h = data[GBR_O_H];
    return 1;
}

static unsigned char raw_string(const gbr_resource_t *resource,
                                unsigned char index, gbr_string_t *string)
{
    unsigned char entry_data[2];
    unsigned char length;
    unsigned int entry;
    unsigned int offset;
    if (resource == 0 || string == 0 || index >= resource->string_count)
        return 0;
    entry = (unsigned int)(resource->string_index + (unsigned int)index * 2u);
    if (!gbr_read(resource, entry, entry_data, 2)) return 0;
    offset = read_u16_memory(entry_data, 0);
    if (!gbr_read(resource, offset, &length, 1)) return 0;
    string->offset = (unsigned int)(offset + 1u);
    string->length = length;
    return 1;
}

#ifndef GBR_READER_ACCESS_ONLY
static unsigned char open_storage(gbr_resource_t *resource,
                                  const unsigned char *data,
                                  unsigned char storage,
                                  unsigned char segment,
                                  unsigned int size)
{
    gbr_resource_t candidate;
    gbr_tree_t tree;
    gbr_object_t object;
    gbr_object_t linked;
    gbr_string_t string;
    unsigned char header[GBR_HEADER_SIZE];
    unsigned char chunk[GBR_READ_CHUNK];
    unsigned int checksum;
    unsigned int expected;
    unsigned int offset;
    unsigned int end;
    unsigned int index;
    unsigned int tree_index;
    unsigned int next_root;
    unsigned int steps;
    unsigned int position;
    unsigned char count;
    unsigned char byte_index;
    unsigned char parent;
    unsigned char child;
    unsigned char sibling;

    if (resource == 0) return GBR_ERR_ARGUMENT;
    clear_resource(resource);
    if (size < GBR_HEADER_SIZE || size > GBR_MAX_FILE_SIZE)
        return GBR_ERR_SIZE;
    candidate.data = data;
    candidate.size = size;
    candidate.string_count = 0;
    candidate.tree_count = 0;
    candidate.object_count = 0;
    candidate.string_index = 0;
    candidate.tree_table = 0;
    candidate.object_table = 0;
    candidate.string_data = 0;
    candidate.storage = storage;
    candidate.segment = segment;
    if (!resource_storage_valid(&candidate) ||
        !gbr_read(&candidate, 0, header, GBR_HEADER_SIZE))
        return GBR_ERR_ARGUMENT;
    if (header[0] != 'G' || header[1] != 'B' ||
        header[2] != 'R' || header[3] != '1')
        return GBR_ERR_MAGIC;
    if (header[GBR_H_VERSION] != GBR_VERSION) return GBR_ERR_VERSION;
    if (header[GBR_H_FLAGS] != 0 ||
        read_u16_memory(header, GBR_H_HEADER_SIZE) != GBR_HEADER_SIZE ||
        read_u16_memory(header, GBR_H_FILE_SIZE) != size ||
        header[GBR_H_RESERVED] != 0)
        return GBR_ERR_HEADER;

    checksum = 0;
    position = 0;
    while (position < size) {
        end = (unsigned int)(size - position);
        count = end > GBR_READ_CHUNK ? GBR_READ_CHUNK : (unsigned char)end;
        if (!gbr_read(&candidate, position, chunk, count))
            return GBR_ERR_ARGUMENT;
        for (byte_index = 0; byte_index < count; byte_index++) {
            offset = (unsigned int)(position + byte_index);
            if (offset != GBR_H_CHECKSUM && offset != GBR_H_CHECKSUM + 1u)
                checksum = (unsigned int)((checksum + chunk[byte_index]) & 0xffffu);
        }
        position = (unsigned int)(position + count);
    }
    if (checksum != read_u16_memory(header, GBR_H_CHECKSUM))
        return GBR_ERR_CHECKSUM;

    candidate.string_count = header[GBR_H_STRING_COUNT];
    candidate.tree_count = header[GBR_H_TREE_COUNT];
    candidate.object_count = header[GBR_H_OBJECT_COUNT];
    candidate.string_index = read_u16_memory(header, GBR_H_STRING_INDEX);
    candidate.tree_table = read_u16_memory(header, GBR_H_TREE_TABLE);
    candidate.object_table = read_u16_memory(header, GBR_H_OBJECT_TABLE);
    candidate.string_data = read_u16_memory(header, GBR_H_STRING_DATA);
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
        if (!raw_string(&candidate, (unsigned char)index, &string) ||
            string.offset == 0 || (unsigned int)(string.offset - 1u) != expected)
            return GBR_ERR_STRING;
        end = (unsigned int)(string.offset + string.length);
        if (end < string.offset || end > size) return GBR_ERR_STRING;
        position = string.offset;
        while (position < end) {
            offset = (unsigned int)(end - position);
            count = offset > GBR_READ_CHUNK ? GBR_READ_CHUNK : (unsigned char)offset;
            if (!gbr_read(&candidate, position, chunk, count))
                return GBR_ERR_STRING;
            for (byte_index = 0; byte_index < count; byte_index++)
                if (chunk[byte_index] < 0x20u || chunk[byte_index] > 0x7eu)
                    return GBR_ERR_STRING;
            position = (unsigned int)(position + count);
        }
        expected = end;
    }
    if (expected != size) return GBR_ERR_STRING;

    next_root = 0;
    for (tree_index = 0; tree_index < candidate.tree_count; tree_index++) {
        offset = (unsigned int)(candidate.tree_table +
                                tree_index * GBR_TREE_RECORD_SIZE);
        if (!gbr_read(&candidate,
                      (unsigned int)(offset + GBR_T_RESERVED), chunk, 1) ||
            chunk[0] != 0 ||
            !raw_tree(&candidate, (unsigned char)tree_index, &tree))
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

unsigned char gbr_open(gbr_resource_t *resource,
                       const unsigned char *data, unsigned int size)
{
    if (data == 0) {
        clear_resource(resource);
        return GBR_ERR_ARGUMENT;
    }
    return open_storage(resource, data, GBR_STORAGE_MEMORY, 0, size);
}

#ifdef GBR_BANKED
unsigned char gbr_open_segment(gbr_resource_t *resource,
                               unsigned char segment, unsigned int size)
{
    return open_storage(resource, 0, GBR_STORAGE_SEGMENT, segment, size);
}
#endif
#endif

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

#ifndef GBR_READER_NO_FIND_TREE
unsigned char gbr_find_tree(const gbr_resource_t *resource,
                            const char *name, unsigned char *index)
{
    gbr_tree_t tree;
    gbr_string_t string;
    unsigned char chunk[GBR_READ_CHUNK];
    unsigned int position;
    unsigned int name_len;
    unsigned int tree_index;
    unsigned char count;
    unsigned char byte_index;
    if (!resource_storage_valid(resource) || name == 0 || index == 0)
        return 0;
    name_len = 0;
    while (name[name_len] != 0 && name_len < 256u) name_len++;
    if (name_len > 255u) return 0;
    for (tree_index = 0; tree_index < resource->tree_count; tree_index++) {
        if (!raw_tree(resource, (unsigned char)tree_index, &tree) ||
            !raw_string(resource, tree.name, &string) ||
            name_len != string.length)
            continue;
        position = 0;
        while (position < name_len) {
            count = (unsigned int)(name_len - position) > GBR_READ_CHUNK
                        ? GBR_READ_CHUNK
                        : (unsigned char)(name_len - position);
            if (!gbr_read(resource, (unsigned int)(string.offset + position),
                          chunk, count))
                break;
            for (byte_index = 0; byte_index < count; byte_index++)
                if ((unsigned char)name[position + byte_index] != chunk[byte_index])
                    break;
            if (byte_index != count) break;
            position = (unsigned int)(position + count);
        }
        if (position == name_len) {
            *index = (unsigned char)tree_index;
            return 1;
        }
    }
    return 0;
}
#endif
