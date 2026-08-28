#!/usr/bin/env python3
"""Compile declarative JSON resources into the GEMBENCH GBR v1 format."""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


MAGIC = b"GBR1"
VERSION = 1
MAX_FILE_SIZE = 16 * 1024
NONE8 = 0xFF
NONE16 = 0xFFFF

HEADER = struct.Struct("<4sBBHHBBBBHHHHH")
TREE = struct.Struct("<BBBB")
OBJECT = struct.Struct("<BBBBHHHHBHB")

TYPE_IDS = {
    "box": 0,
    "text": 1,
    "string": 2,
    "button": 3,
    "field": 4,
    "icon": 5,
    "image": 6,
    "checkbox": 7,
    "radio": 8,
    "user": 9,
}

TEXT_TYPES = {"text", "string", "button", "field", "checkbox", "radio"}
TEXT_TYPE_IDS = {TYPE_IDS[name] for name in TEXT_TYPES}

FLAG_BITS = {
    "selectable": 0x0001,
    "default": 0x0002,
    "exit": 0x0004,
    "radio": 0x0008,
    "hidden": 0x0010,
}

STATE_BITS = {
    "disabled": 0x0001,
    "selected": 0x0002,
    "checked": 0x0004,
    "outlined": 0x0008,
    "shadowed": 0x0010,
}

KNOWN_FLAG_MASK = sum(FLAG_BITS.values())
KNOWN_STATE_MASK = sum(STATE_BITS.values())

OBJECT_KEYS = {
    "id",
    "type",
    "x",
    "y",
    "w",
    "h",
    "flags",
    "state",
    "text",
    "spec",
    "children",
}

C_IDENTIFIER = re.compile(r"[A-Z][A-Z0-9_]*\Z")


class ResourceError(ValueError):
    """Raised when source data cannot be represented safely in GBR v1."""


@dataclass
class ObjectRecord:
    parent: int
    first_child: int
    next_sibling: int
    type_id: int
    flags: int
    state: int
    spec: int
    x: int
    y: int
    w: int
    h: int

    def pack(self) -> bytes:
        return OBJECT.pack(
            self.parent,
            self.first_child,
            self.next_sibling,
            self.type_id,
            self.flags,
            self.state,
            self.spec,
            self.x,
            self.y,
            self.w,
            self.h,
        )


class StringTable:
    def __init__(self) -> None:
        self.values: list[bytes] = []
        self.indices: dict[str, int] = {}

    def intern(self, value: Any, location: str) -> int:
        if not isinstance(value, str):
            raise ResourceError(f"{location}: expected a string")
        try:
            encoded = value.encode("ascii")
        except UnicodeEncodeError as exc:
            raise ResourceError(
                f"{location}: GBR v1 strings must contain printable ASCII only"
            ) from exc
        if any(byte < 0x20 or byte > 0x7E for byte in encoded):
            raise ResourceError(
                f"{location}: GBR v1 strings must contain printable ASCII only"
            )
        if len(encoded) > 0xFF:
            raise ResourceError(f"{location}: string exceeds 255 bytes")
        if value in self.indices:
            return self.indices[value]
        if len(self.values) >= 0xFF:
            raise ResourceError("resource has more than 255 unique strings")
        index = len(self.values)
        self.indices[value] = index
        self.values.append(encoded)
        return index


def _mapping(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ResourceError(f"{location}: expected an object")
    return value


def _list(value: Any, location: str) -> list[Any]:
    if not isinstance(value, list):
        raise ResourceError(f"{location}: expected a list")
    return value


def _integer(value: Any, minimum: int, maximum: int, location: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ResourceError(f"{location}: expected an integer")
    if not minimum <= value <= maximum:
        raise ResourceError(f"{location}: expected {minimum}..{maximum}, got {value}")
    return value


def _bits(value: Any, names: dict[str, int], location: str) -> int:
    result = 0
    for index, name in enumerate(_list(value, location)):
        if not isinstance(name, str) or name not in names:
            valid = ", ".join(sorted(names))
            raise ResourceError(
                f"{location}[{index}]: unknown value {name!r}; expected one of {valid}"
            )
        result |= names[name]
    return result


def _flatten_object(
    source: Any,
    parent: int,
    records: list[ObjectRecord],
    strings: StringTable,
    object_ids: dict[str, int],
    location: str,
) -> int:
    obj = _mapping(source, location)
    unknown = sorted(set(obj) - OBJECT_KEYS)
    if unknown:
        raise ResourceError(f"{location}: unknown keys: {', '.join(unknown)}")

    type_name = obj.get("type")
    if not isinstance(type_name, str) or type_name not in TYPE_IDS:
        valid = ", ".join(TYPE_IDS)
        raise ResourceError(f"{location}.type: expected one of {valid}")

    if len(records) >= 0xFF:
        raise ResourceError("resource has more than 255 objects")
    index = len(records)
    object_id = obj.get("id")
    if object_id is not None:
        if not isinstance(object_id, str) or not C_IDENTIFIER.fullmatch(object_id):
            raise ResourceError(
                f"{location}.id: expected an uppercase C identifier"
            )
        if object_id in object_ids:
            raise ResourceError(f"{location}.id: duplicate object id {object_id}")
        object_ids[object_id] = index
    records.append(
        ObjectRecord(
            parent=parent,
            first_child=NONE8,
            next_sibling=NONE8,
            type_id=TYPE_IDS[type_name],
            flags=_bits(obj.get("flags", []), FLAG_BITS, f"{location}.flags"),
            state=_bits(obj.get("state", []), STATE_BITS, f"{location}.state"),
            spec=NONE16,
            x=_integer(obj.get("x", 0), 0, 511, f"{location}.x"),
            y=_integer(obj.get("y", 0), 0, 255, f"{location}.y"),
            w=_integer(obj.get("w", 0), 0, 511, f"{location}.w"),
            h=_integer(obj.get("h", 0), 0, 255, f"{location}.h"),
        )
    )

    if "text" in obj and "spec" in obj:
        raise ResourceError(f"{location}: text and spec are mutually exclusive")
    if "text" in obj:
        if type_name not in TEXT_TYPES:
            raise ResourceError(f"{location}.text: {type_name} objects do not carry text")
        records[index].spec = strings.intern(obj["text"], f"{location}.text")
    elif "spec" in obj:
        if type_name in TEXT_TYPES:
            raise ResourceError(f"{location}.spec: {type_name} objects require text")
        records[index].spec = _integer(
            obj["spec"], 0, NONE16, f"{location}.spec"
        )

    children = _list(obj.get("children", []), f"{location}.children")
    child_indices: list[int] = []
    for child_number, child in enumerate(children):
        child_indices.append(
            _flatten_object(
                child,
                index,
                records,
                strings,
                object_ids,
                f"{location}.children[{child_number}]",
            )
        )
    if child_indices:
        records[index].first_child = child_indices[0]
        for current, following in zip(child_indices, child_indices[1:]):
            records[current].next_sibling = following
    return index


def compile_document_with_ids(document: Any) -> tuple[bytes, dict[str, int]]:
    root = _mapping(document, "document")
    unknown = sorted(set(root) - {"format", "trees"})
    if unknown:
        raise ResourceError(f"document: unknown keys: {', '.join(unknown)}")
    if root.get("format") != "GBR1":
        raise ResourceError("document.format: expected 'GBR1'")

    source_trees = _list(root.get("trees"), "document.trees")
    if not source_trees:
        raise ResourceError("document.trees: at least one tree is required")
    if len(source_trees) > 0xFF:
        raise ResourceError("resource has more than 255 trees")

    strings = StringTable()
    records: list[ObjectRecord] = []
    object_ids: dict[str, int] = {}
    trees: list[tuple[int, int, int]] = []

    for tree_number, source_tree in enumerate(source_trees):
        location = f"document.trees[{tree_number}]"
        tree = _mapping(source_tree, location)
        unknown_tree = sorted(set(tree) - {"name", "root"})
        if unknown_tree:
            raise ResourceError(
                f"{location}: unknown keys: {', '.join(unknown_tree)}"
            )
        name_index = strings.intern(tree.get("name"), f"{location}.name")
        first = len(records)
        root_index = _flatten_object(
            tree.get("root"),
            NONE8,
            records,
            strings,
            object_ids,
            f"{location}.root",
        )
        count = len(records) - first
        trees.append((root_index, count, name_index))

    string_index_offset = HEADER.size
    tree_table_offset = string_index_offset + 2 * len(strings.values)
    object_table_offset = tree_table_offset + TREE.size * len(trees)
    string_data_offset = object_table_offset + OBJECT.size * len(records)

    string_data = bytearray()
    string_offsets: list[int] = []
    for value in strings.values:
        string_offsets.append(string_data_offset + len(string_data))
        string_data.append(len(value))
        string_data.extend(value)

    file_size = string_data_offset + len(string_data)
    if file_size > MAX_FILE_SIZE:
        raise ResourceError(
            f"compiled resource is {file_size} bytes; GBR v1 limit is {MAX_FILE_SIZE}"
        )

    string_index = b"".join(struct.pack("<H", offset) for offset in string_offsets)
    tree_table = b"".join(
        TREE.pack(root_index, count, name_index, 0)
        for root_index, count, name_index in trees
    )
    object_table = b"".join(record.pack() for record in records)

    header = HEADER.pack(
        MAGIC,
        VERSION,
        0,
        HEADER.size,
        file_size,
        len(strings.values),
        len(trees),
        len(records),
        0,
        string_index_offset,
        tree_table_offset,
        object_table_offset,
        string_data_offset,
        0,
    )
    blob = bytearray(header + string_index + tree_table + object_table + string_data)
    checksum = sum(blob) & 0xFFFF
    struct.pack_into("<H", blob, HEADER.size - 2, checksum)
    return bytes(blob), object_ids


def compile_document(document: Any) -> bytes:
    return compile_document_with_ids(document)[0]


def render_c_header(blob: bytes, object_ids: dict[str, int], prefix: str) -> str:
    """Render a checked-in C view of one GBR without changing the binary ABI.

    Object ``id`` values are source-only metadata.  They become stable generated
    constants while the packed object records remain canonical GBR v1.
    """
    if not isinstance(prefix, str) or not C_IDENTIFIER.fullmatch(prefix):
        raise ResourceError("symbol prefix must be an uppercase C identifier")
    header = read_header(blob)
    guard = f"GEMBENCH_GENERATED_{prefix}_GBR_H"
    array_name = f"{prefix.lower()}_gbr"
    lines = [
        "/* Generated by tools/gbrc.py; do not edit. */",
        f"#ifndef {guard}",
        f"#define {guard}",
        "",
        f"#define {prefix}_GBR_SIZE {len(blob)}u",
        f"#define {prefix}_STRING_COUNT {header['string_count']}u",
        f"#define {prefix}_TREE_COUNT {header['tree_count']}u",
        f"#define {prefix}_OBJECT_COUNT {header['object_count']}u",
        f"#define {prefix}_STRING_INDEX {header['string_index_offset']}u",
        f"#define {prefix}_TREE_TABLE {header['tree_table_offset']}u",
        f"#define {prefix}_OBJECT_TABLE {header['object_table_offset']}u",
        f"#define {prefix}_STRING_DATA {header['string_data_offset']}u",
    ]
    for name, index in sorted(object_ids.items(), key=lambda item: item[1]):
        lines.append(f"#define {name} {index}u")
    lines.extend(("", f"static const unsigned char {array_name}[] = {{"))
    for offset in range(0, len(blob), 12):
        chunk = ", ".join(f"0x{byte:02x}" for byte in blob[offset : offset + 12])
        lines.append(f"    {chunk},")
    lines.extend(("};", "", f"#endif /* {guard} */", ""))
    return "\n".join(lines)


def read_header(blob: bytes) -> dict[str, int | bytes]:
    if len(blob) < HEADER.size:
        raise ResourceError("file is shorter than the GBR v1 header")
    values = HEADER.unpack_from(blob)
    keys = (
        "magic",
        "version",
        "flags",
        "header_size",
        "file_size",
        "string_count",
        "tree_count",
        "object_count",
        "reserved",
        "string_index_offset",
        "tree_table_offset",
        "object_table_offset",
        "string_data_offset",
        "checksum",
    )
    return dict(zip(keys, values))


def _u16(blob: bytes, offset: int) -> int:
    return blob[offset] | (blob[offset + 1] << 8)


def verify_blob(blob: bytes) -> dict[str, int | bytes]:
    """Strictly validate one canonical GBR v1 binary.

    Version 1 is deliberately compact: all four sections are contiguous and
    strings fill the remainder of the file.  Enforcing that canonical layout
    keeps the Z80 reader bounded and rejects aliases into headers or tables.
    """
    if not isinstance(blob, bytes):
        raise ResourceError("binary resource must be bytes")
    if len(blob) < HEADER.size:
        raise ResourceError("file is shorter than the GBR v1 header")
    if len(blob) > MAX_FILE_SIZE:
        raise ResourceError(
            f"file is {len(blob)} bytes; GBR v1 limit is {MAX_FILE_SIZE}"
        )

    header = read_header(blob)
    if header["magic"] != MAGIC:
        raise ResourceError("invalid GBR magic")
    if header["version"] != VERSION:
        raise ResourceError(f"unsupported GBR version {header['version']}")
    if header["flags"] != 0:
        raise ResourceError("GBR v1 file flags must be zero")
    if header["header_size"] != HEADER.size:
        raise ResourceError("invalid GBR v1 header size")
    if header["file_size"] != len(blob):
        raise ResourceError("header file size does not match the binary length")
    if header["reserved"] != 0:
        raise ResourceError("GBR v1 reserved header byte must be zero")

    checksum = (sum(blob) - blob[HEADER.size - 2] - blob[HEADER.size - 1]) & 0xFFFF
    if header["checksum"] != checksum:
        raise ResourceError("GBR checksum mismatch")

    string_count = int(header["string_count"])
    tree_count = int(header["tree_count"])
    object_count = int(header["object_count"])
    if not string_count or not tree_count or not object_count:
        raise ResourceError("GBR v1 requires strings, trees, and objects")

    string_index = int(header["string_index_offset"])
    tree_table = int(header["tree_table_offset"])
    object_table = int(header["object_table_offset"])
    string_data = int(header["string_data_offset"])
    expected_tree = HEADER.size + 2 * string_count
    expected_object = expected_tree + TREE.size * tree_count
    expected_strings = expected_object + OBJECT.size * object_count
    if (
        string_index != HEADER.size
        or tree_table != expected_tree
        or object_table != expected_object
        or string_data != expected_strings
        or string_data >= len(blob)
    ):
        raise ResourceError("GBR sections are not in canonical v1 layout")

    next_string = string_data
    for index in range(string_count):
        offset = _u16(blob, string_index + 2 * index)
        if offset != next_string or offset >= len(blob):
            raise ResourceError(f"string {index}: invalid or non-canonical offset")
        length = blob[offset]
        end = offset + 1 + length
        if end > len(blob):
            raise ResourceError(f"string {index}: payload exceeds the file")
        if any(byte < 0x20 or byte > 0x7E for byte in blob[offset + 1 : end]):
            raise ResourceError(f"string {index}: payload is not printable ASCII")
        next_string = end
    if next_string != len(blob):
        raise ResourceError("string data does not consume the complete file")

    trees = [
        TREE.unpack_from(blob, tree_table + TREE.size * index)
        for index in range(tree_count)
    ]
    objects = [
        OBJECT.unpack_from(blob, object_table + OBJECT.size * index)
        for index in range(object_count)
    ]

    next_root = 0
    for index, (root, count, name, reserved) in enumerate(trees):
        if reserved:
            raise ResourceError(f"tree {index}: reserved byte must be zero")
        if not count or root != next_root or root + count > object_count:
            raise ResourceError(f"tree {index}: invalid object range")
        if name >= string_count:
            raise ResourceError(f"tree {index}: name string is out of range")
        next_root += count
    if next_root != object_count:
        raise ResourceError("tree ranges do not cover the object table")

    for index, obj in enumerate(objects):
        parent, child, sibling, type_id, flags, state, spec, x, _y, w, _h = obj
        if type_id not in TYPE_IDS.values():
            raise ResourceError(f"object {index}: unknown object type")
        if flags & ~KNOWN_FLAG_MASK:
            raise ResourceError(f"object {index}: unknown flag bits")
        if state & ~KNOWN_STATE_MASK:
            raise ResourceError(f"object {index}: unknown state bits")
        if x > 511 or w > 511:
            raise ResourceError(f"object {index}: Screen 7 geometry is out of range")
        if type_id in TEXT_TYPE_IDS and spec != NONE16 and spec >= string_count:
            raise ResourceError(f"object {index}: text string is out of range")
        for label, link in (("parent", parent), ("child", child), ("sibling", sibling)):
            if link != NONE8 and link >= object_count:
                raise ResourceError(f"object {index}: {label} link is out of range")

    for tree_index, (root, count, _name, _reserved) in enumerate(trees):
        end = root + count
        for index in range(root, end):
            parent, child, sibling = objects[index][0:3]
            if index == root:
                if parent != NONE8 or sibling != NONE8:
                    raise ResourceError(f"tree {tree_index}: root links are invalid")
            elif parent == NONE8 or not root <= parent < index:
                raise ResourceError(f"object {index}: parent does not precede it in its tree")

            if child != NONE8:
                if not index < child < end or objects[child][0] != index:
                    raise ResourceError(f"object {index}: first-child link is inconsistent")
            if sibling != NONE8:
                if (
                    not index < sibling < end
                    or parent == NONE8
                    or objects[sibling][0] != parent
                ):
                    raise ResourceError(f"object {index}: sibling link is inconsistent")

            if index != root:
                linked = objects[parent][1]
                steps = 0
                while linked != NONE8 and linked != index and steps < count:
                    linked = objects[linked][2]
                    steps += 1
                if linked != index:
                    raise ResourceError(f"object {index}: not linked from its parent")

    return header


def load_source(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as source:
            return json.load(source)
    except OSError as exc:
        raise ResourceError(f"cannot read {path}: {exc.strerror}") from exc
    except json.JSONDecodeError as exc:
        raise ResourceError(f"{path}:{exc.lineno}:{exc.colno}: {exc.msg}") from exc


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compile a JSON object tree to GEMBENCH GBR v1"
    )
    parser.add_argument("source", type=Path, help="input JSON resource")
    parser.add_argument("-o", "--output", type=Path, required=True, help="output .gbr")
    parser.add_argument(
        "--c-header", type=Path, help="optional generated C blob/object-ID header"
    )
    parser.add_argument(
        "--symbol-prefix", help="uppercase prefix used by --c-header"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if (args.c_header is None) != (args.symbol_prefix is None):
            raise ResourceError("--c-header and --symbol-prefix must be used together")
        blob, object_ids = compile_document_with_ids(load_source(args.source))
        verify_blob(blob)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(blob)
        if args.c_header is not None:
            args.c_header.parent.mkdir(parents=True, exist_ok=True)
            args.c_header.write_text(
                render_c_header(blob, object_ids, args.symbol_prefix),
                encoding="ascii",
            )
    except (OSError, ResourceError) as exc:
        print(f"gbrc: error: {exc}", file=sys.stderr)
        return 2
    print(f"GBR1: wrote {args.output} ({len(blob)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
