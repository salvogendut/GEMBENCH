# GBR version 1

Status: **frozen as part of GEMBENCH-1 on 2026-08-29**. The compatibility
policy and machine-readable manifest are described in
[gembench/ABI-V1.md](gembench/ABI-V1.md).

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
| `id` | Optional source-only C identifier for this flattened object |
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

`id` values must be unique C identifiers. They do not add bytes to GBR v1;
`gbrc.py --c-header ... --symbol-prefix ...` emits their flattened indices,
the resource blob, counts, and section offsets into a deterministic C header.

The object types are `box`, `text`, `string`, `button`, `field`, `icon`, `image`,
`checkbox`, `radio`, and `user`. Their numeric identities are frozen. The
GEMBENCH-1 renderer implements box, text, string, button, field, checkbox, and
radio. Icon, image, and user remain format-only reservations; a visible instance
is rejected before any partial tree draw.

Checkbox and radio behavior is an additive runtime implementation of the
already frozen type, flag, and state meanings. `GBR_FORM_ENGINE=1` adds shared
pointer activation, checked-state updates, sibling radio exclusivity, forward
and reverse focus traversal, default Enter activation, non-default Escape exit,
and radio cursor navigation. Mutable state remains in the caller-owned overlay;
no GBR1 byte or record interpretation changed.

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

## Canonical validation

GBR v1 readers must reject a resource before exposing any record when:

- the magic, version, flags, header size, declared file size, reserved bytes,
  or checksum are invalid;
- the file exceeds 16 KiB or the string, tree, or object counts are zero;
- the string index, tree table, object table, and string data are not tightly
  packed in that order;
- a string offset is non-canonical, its payload crosses the file boundary, or
  it contains bytes outside printable ASCII;
- tree ranges do not partition the complete object table, or a tree name is
  not a valid string index;
- an object type, flag, state, Screen 7 horizontal coordinate, or link is out
  of range; or
- parent, first-child, and next-sibling links do not form a bounded tree within
  the owning tree record's contiguous object range.

This strict layout is intentional. It gives the Z80 reader simple bounded
arithmetic, prevents offsets from aliasing headers or tables, and leaves future
extensions to a new format version rather than ambiguous v1 files.

The host verifier is available as:

```sh
python3 tools/gbrverify.py build/examples/hello-dialog.gbr
```

`lib/gembench/gbr_reader.c` implements the same checks without allocation or
recursion and exposes trees, objects, and strings as copied records containing
indices and offsets. It is compiled with SDCC as part of `make gbr-check`.
Generated blobs verified during the same build may compile the reader with
`GBR_READER_ACCESS_ONLY`; this retains bounded accessors while omitting the
duplicate target-side open pass. External or mutable resources must continue
to use the strict validator.

The runtime descriptor may identify either directly addressable application
memory or an MSX2 mapper segment. `gbr_read` is the common bounded-copy boundary;
callers never retain a pointer into a temporarily mapped segment. This storage
choice is runtime metadata only and does not change any byte in GBR v1. The
auxiliary-segment transport remains an opt-in experiment after the Milestone 7
placement decision.

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
| 8 | 2 | String index for text-bearing types, otherwise a type-specific value; `65535` means none |
| 10 | 2 | X coordinate |
| 12 | 1 | Y coordinate |
| 13 | 2 | Width |
| 15 | 1 | Height |

Flag, state, type, reserved-field, and byte-offset constants are mirrored in
`include/gembench/gbr.h` and checked against `abi/gembench-v1.json`.

`text`, `string`, `button`, `field`, `checkbox`, and `radio` records interpret
the field at offset 8 as a string index. The compiler rejects a raw `spec` on
those types, and readers reject a non-`65535` index outside the string table.
Other object types may use the field as a bounded type-specific value.

## Deliberate omissions

Version 1 does not yet encode icon or raster payloads, editable-field templates,
keyboard shortcuts, palette roles, user-object callbacks, or menu-specific
metadata. Those need target runtime designs before binary fields are assigned.

The existing numeric identities for those format-only object types are
reserved, not permission to silently assign a new record interpretation. Any
incompatible payload or layout requires a new resource version.
