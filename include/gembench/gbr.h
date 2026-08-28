#ifndef GEMBENCH_GBR_H
#define GEMBENCH_GBR_H

/* GBR v1 uses byte offsets rather than packed C structs so its layout is stable
 * across SDCC, host compilers, and assembly consumers. */

#define GBR_VERSION                 1u
#define GBR_MAX_FILE_SIZE       16384u
#define GBR_NONE8                 255u
#define GBR_NONE16              65535u

#define GBR_HEADER_SIZE             24u
#define GBR_TREE_RECORD_SIZE         4u
#define GBR_OBJECT_RECORD_SIZE      16u

#define GBR_H_MAGIC                  0u
#define GBR_H_VERSION                4u
#define GBR_H_FLAGS                  5u
#define GBR_H_HEADER_SIZE            6u
#define GBR_H_FILE_SIZE              8u
#define GBR_H_STRING_COUNT          10u
#define GBR_H_TREE_COUNT            11u
#define GBR_H_OBJECT_COUNT          12u
#define GBR_H_STRING_INDEX          14u
#define GBR_H_TREE_TABLE            16u
#define GBR_H_OBJECT_TABLE          18u
#define GBR_H_STRING_DATA           20u
#define GBR_H_CHECKSUM              22u

#define GBR_T_ROOT                   0u
#define GBR_T_OBJECT_COUNT           1u
#define GBR_T_NAME                   2u

#define GBR_O_PARENT                 0u
#define GBR_O_FIRST_CHILD            1u
#define GBR_O_NEXT_SIBLING           2u
#define GBR_O_TYPE                   3u
#define GBR_O_FLAGS                  4u
#define GBR_O_STATE                  6u
#define GBR_O_SPEC                   8u
#define GBR_O_X                     10u
#define GBR_O_Y                     12u
#define GBR_O_W                     13u
#define GBR_O_H                     15u

#define GBR_TYPE_BOX                 0u
#define GBR_TYPE_TEXT                1u
#define GBR_TYPE_STRING              2u
#define GBR_TYPE_BUTTON              3u
#define GBR_TYPE_FIELD               4u
#define GBR_TYPE_ICON                5u
#define GBR_TYPE_IMAGE               6u
#define GBR_TYPE_CHECKBOX            7u
#define GBR_TYPE_RADIO               8u
#define GBR_TYPE_USER                9u

#define GBR_FLAG_SELECTABLE     0x0001u
#define GBR_FLAG_DEFAULT        0x0002u
#define GBR_FLAG_EXIT           0x0004u
#define GBR_FLAG_RADIO          0x0008u
#define GBR_FLAG_HIDDEN         0x0010u

#define GBR_STATE_DISABLED      0x0001u
#define GBR_STATE_SELECTED      0x0002u
#define GBR_STATE_CHECKED       0x0004u
#define GBR_STATE_OUTLINED      0x0008u
#define GBR_STATE_SHADOWED      0x0010u

#define GBR_U16_AT(base, offset) \
    ((unsigned int)((base)[(offset)]) | \
     ((unsigned int)((base)[(offset) + 1u]) << 8))

#endif
