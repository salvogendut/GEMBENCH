# GBR version 1

Status: **draft, implemented by the initial host compiler**.

GBR is a compact, little-endian resource format for GEMBENCH. Version 1 contains
strings and object trees. The complete file is limited to 16 KiB so one resource
can occupy a single mapper segment.

## Source format

`tools/gbrc.py` accepts UTF-8 JSON. All strings must currently be printable
ASCII and at most 255 bytes. Text is interned in first-use order, making output
deterministic.

Each tree has a name and one nested root object. Supported object keys are:

| Key | Meaning |
| --- | --- |
| `type` | Required object type name |
| `x`, `w` | Horizontal pixel geometry, `0..511` |
| `y`, `h` | Vertical pixel geometry, `0..255` |
| `flags` | Optional list of behavioural flags |
| `state` | Optional list of visual states |
| `text` | Optional interned string reference |
| `spec` | Optional raw `0..65535` type-specific value |
| `children` | Optional nested child objects |

`text` and `spec` are mutually exclusive. Object records are flattened in
pre-order. Parent, first-child, and next-sibling fields contain global object
indices; `255` means no object.

The current object types are `box`, `text`, `string`, `button`, `field`, `icon`,
`image`, `checkbox`, `radio`, and `user`.

## Binary layout

All multi-byte integers are unsigned and little-endian. Offsets are absolute
from the beginning of the file.

### Header: 24 bytes

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | ASCII magic `GBR1` |
| 4 | 1 | Format version, currently `1` |
| 5 | 1 | File flags, currently `0` |
| 6 | 2 | Header size, currently `24` |
| 8 | 2 | Complete file size |
| 10 | 1 | String count |
| 11 | 1 | Tree count |
| 12 | 1 | Object count |
| 13 | 1 | Reserved, zero |
| 14 | 2 | String-index offset |
| 16 | 2 | Tree-table offset |
| 18 | 2 | Object-table offset |
| 20 | 2 | String-data offset |
| 22 | 2 | Additive 16-bit checksum |

The checksum is the sum of every file byte modulo 65536 while treating the two
checksum bytes as zero.

### String index

The index contains one 16-bit absolute offset per string. Each referenced value
is stored as a one-byte length followed by that many bytes. Strings are not
NUL-terminated.

### Tree record: 4 bytes

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | Root object index |
| 1 | 1 | Number of contiguous objects in this tree |
| 2 | 1 | Tree-name string index |
| 3 | 1 | Reserved, zero |

### Object record: 16 bytes

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | Parent object index or `255` |
| 1 | 1 | First-child object index or `255` |
| 2 | 1 | Next-sibling object index or `255` |
| 3 | 1 | Object type |
| 4 | 2 | Behaviour flags |
| 6 | 2 | Visual state bits |
| 8 | 2 | String index or type-specific value; `65535` means none |
| 10 | 2 | X coordinate |
| 12 | 1 | Y coordinate |
| 13 | 2 | Width |
| 15 | 1 | Height |

Flag, state, type, and byte-offset constants are mirrored in
`include/gembench/gbr.h`.

## Deliberate omissions

Version 1 does not yet encode icons, raster payloads, editable-field templates,
keyboard shortcuts, palette roles, user-object callbacks, or menu-specific
metadata. Those need target runtime designs before binary fields are assigned.
