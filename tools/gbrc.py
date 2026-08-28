#!/usr/bin/env python3
"""Compile declarative JSON resources into the GEMBENCH GBR v1 format."""

from __future__ import annotations

import argparse
import json
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

OBJECT_KEYS = {
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
        records[index].spec = strings.intern(obj["text"], f"{location}.text")
    elif "spec" in obj:
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
                f"{location}.children[{child_number}]",
            )
        )
    if child_indices:
        records[index].first_child = child_indices[0]
        for current, following in zip(child_indices, child_indices[1:]):
            records[current].next_sibling = following
    return index


def compile_document(document: Any) -> bytes:
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
            tree.get("root"), NONE8, records, strings, f"{location}.root"
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
    return bytes(blob)


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
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        blob = compile_document(load_source(args.source))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(blob)
    except (OSError, ResourceError) as exc:
        print(f"gbrc: error: {exc}", file=sys.stderr)
        return 2
    print(f"GBR1: wrote {args.output} ({len(blob)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
