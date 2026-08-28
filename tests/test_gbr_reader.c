#include <stdio.h>
#include <string.h>

#include "gbr.h"

static const unsigned char golden[] = {
#include "fixtures/hello-dialog.gbr.inc"
};

static int failures;

static void check(int ok, const char *name)
{
    if (ok) printf("ok   %s\n", name);
    else {
        printf("FAIL %s\n", name);
        failures++;
    }
}

static void fix_checksum(unsigned char *data, unsigned int size)
{
    unsigned int index;
    unsigned int checksum = 0;
    data[GBR_H_CHECKSUM] = 0;
    data[GBR_H_CHECKSUM + 1u] = 0;
    for (index = 0; index < size; index++)
        checksum = (unsigned int)((checksum + data[index]) & 0xffffu);
    data[GBR_H_CHECKSUM] = (unsigned char)checksum;
    data[GBR_H_CHECKSUM + 1u] = (unsigned char)(checksum >> 8);
}

static void test_navigation(void)
{
    gbr_resource_t resource;
    gbr_tree_t tree;
    gbr_object_t object;
    gbr_string_t string;
    unsigned char index = 255;

    check(gbr_open(&resource, golden, sizeof(golden)) == GBR_OK,
          "golden GBR validates");
    check(resource.string_count == 3 && resource.tree_count == 1 &&
              resource.object_count == 3,
          "header counts are exposed");
    check(gbr_find_tree(&resource, "HELLO", &index) && index == 0,
          "tree lookup by name works");
    check(gbr_tree_at(&resource, index, &tree) && tree.root == 0 &&
              tree.object_count == 3,
          "tree range is readable");
    check(gbr_object_at(&resource, tree.root, &object) &&
              object.type == GBR_TYPE_BOX && object.parent == GBR_NONE8 &&
              object.first_child == 1,
          "root object is readable");
    check(gbr_object_at(&resource, object.first_child, &object) &&
              object.type == GBR_TYPE_TEXT && object.next_sibling == 2,
          "first-child and sibling navigation works");
    check(gbr_string_at(&resource, (unsigned char)object.spec, &string) &&
              string.length == 19 &&
              !memcmp(resource.data + string.offset, "Welcome to GEMBENCH", 19),
          "object string is exposed as a bounded offset");
    check(!gbr_tree_at(&resource, 1, &tree) &&
              !gbr_object_at(&resource, 3, &object) &&
              !gbr_string_at(&resource, 3, &string),
          "out-of-range access is rejected");
}

static void test_corruption(void)
{
    unsigned char data[sizeof(golden)];
    gbr_resource_t resource;

    memcpy(data, golden, sizeof(data));
    data[0] = 'X';
    check(gbr_open(&resource, data, sizeof(data)) == GBR_ERR_MAGIC,
          "bad magic is rejected");

    memcpy(data, golden, sizeof(data));
    data[sizeof(data) - 1u] ^= 1u;
    check(gbr_open(&resource, data, sizeof(data)) == GBR_ERR_CHECKSUM,
          "bad checksum is rejected");

    memcpy(data, golden, sizeof(data));
    data[GBR_H_TREE_TABLE]++;
    fix_checksum(data, sizeof(data));
    check(gbr_open(&resource, data, sizeof(data)) == GBR_ERR_LAYOUT,
          "overlapping section layout is rejected");

    memcpy(data, golden, sizeof(data));
    data[0x52] = 0xff;
    fix_checksum(data, sizeof(data));
    check(gbr_open(&resource, data, sizeof(data)) == GBR_ERR_STRING,
          "overrunning string is rejected");

    memcpy(data, golden, sizeof(data));
    data[0x1e + GBR_T_ROOT] = 3;
    fix_checksum(data, sizeof(data));
    check(gbr_open(&resource, data, sizeof(data)) == GBR_ERR_TREE,
          "invalid tree range is rejected");

    memcpy(data, golden, sizeof(data));
    data[0x22 + GBR_O_TYPE] = 10;
    fix_checksum(data, sizeof(data));
    check(gbr_open(&resource, data, sizeof(data)) == GBR_ERR_OBJECT,
          "unknown object type is rejected");

    memcpy(data, golden, sizeof(data));
    data[0x32 + GBR_O_SPEC] = 3;
    fix_checksum(data, sizeof(data));
    check(gbr_open(&resource, data, sizeof(data)) == GBR_ERR_OBJECT,
          "out-of-range text string is rejected");

    memcpy(data, golden, sizeof(data));
    data[0x22 + GBR_O_PARENT] = 0;
    fix_checksum(data, sizeof(data));
    check(gbr_open(&resource, data, sizeof(data)) == GBR_ERR_LINK,
          "invalid root parent is rejected");
}

int main(void)
{
    test_navigation();
    test_corruption();
    if (failures) {
        printf("\n%d GBR reader test(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall GBR reader tests passed\n");
    return 0;
}
