#!/usr/bin/env python3
"""Build and inspect the optional GEOBENCH APP icon preamble.

Icon-bearing applications begin with a small executable resource block:

    0..2    Z80 JP to the application entry point
    3..6    "GBAP"
    7       format version (1)
    8       bitmap codec (1 = canonical CPC Mode 1)
    9       width in bytes (8)
    10      height in rows (32)
    11..12  bitmap length, little-endian (256)
    13..14  bitmap offset, little-endian (16)
    15      reserved
    16..271 canonical 32x32 four-pen bitmap

The application is linked at 0x4110, immediately after the preamble. Legacy
applications remain headerless and continue to start at 0x4000.
"""

import re
import struct
import sys

MAGIC = b"GBAP"
VERSION = 1
CODEC_MODE1 = 1
HEADER_SIZE = 16
ICON_WB = 8
ICON_H = 32
ICON_SIZE = ICON_WB * ICON_H
PREAMBLE_SIZE = HEADER_SIZE + ICON_SIZE
APP_BASE = 0x4000
ENTRY = APP_BASE + PREAMBLE_SIZE


def parse_icon(path):
    width = height = None
    data = bytearray()
    with open(path, encoding="ascii") as source:
        for line in source:
            text = line.strip()
            match = re.match(r"\w+_w\s+equ\s+(\d+)", text)
            if match:
                width = int(match.group(1))
            match = re.match(r"\w+_h\s+equ\s+(\d+)", text)
            if match:
                height = int(match.group(1))
            if text.startswith("db"):
                data.extend(int(value, 16)
                            for value in re.findall(r"#([0-9A-Fa-f]{2})", text))
    if width != ICON_WB or height != ICON_H or len(data) != ICON_SIZE:
        raise ValueError(
            f"{path}: APP icons must be 32x32 canonical Mode-1 bitmaps "
            f"({ICON_WB}x{ICON_H} bytes); got {width}x{height}, {len(data)} bytes"
        )
    return bytes(data)


def make_preamble(icon):
    header = bytearray(HEADER_SIZE)
    header[0:3] = bytes((0xC3, ENTRY & 0xFF, ENTRY >> 8))
    header[3:7] = MAGIC
    header[7] = VERSION
    header[8] = CODEC_MODE1
    header[9] = ICON_WB
    header[10] = ICON_H
    struct.pack_into("<HH", header, 11, ICON_SIZE, HEADER_SIZE)
    return bytes(header) + icon


def valid_preamble(data):
    if len(data) < PREAMBLE_SIZE:
        return False
    return (
        data[0] == 0xC3
        and data[1] == (ENTRY & 0xFF)
        and data[2] == (ENTRY >> 8)
        and data[3:7] == MAGIC
        and data[7] == VERSION
        and data[8] == CODEC_MODE1
        and data[9] == ICON_WB
        and data[10] == ICON_H
        and struct.unpack_from("<H", data, 11)[0] == ICON_SIZE
        and struct.unpack_from("<H", data, 13)[0] == HEADER_SIZE
    )


def inject(icon_path, raw_path, out_path):
    icon = parse_icon(icon_path)
    with open(raw_path, "rb") as source:
        raw = bytearray(source.read())
    if len(raw) < PREAMBLE_SIZE:
        raise ValueError(f"{raw_path}: linked image is shorter than the APP preamble")
    padding = raw[:PREAMBLE_SIZE]
    if padding[0] not in (0x00, 0xFF) or any(value != padding[0] for value in padding):
        raise ValueError(
            f"{raw_path}: linked image does not reserve {PREAMBLE_SIZE} bytes at 0x4000"
        )
    raw[:PREAMBLE_SIZE] = make_preamble(icon)
    with open(out_path, "wb") as target:
        target.write(raw)


def main(argv):
    if len(argv) == 3 and argv[1] == "size":
        parse_icon(argv[2])
        print(PREAMBLE_SIZE)
        return
    if len(argv) == 5 and argv[1] == "inject":
        inject(argv[2], argv[3], argv[4])
        return
    if len(argv) == 3 and argv[1] == "check":
        with open(argv[2], "rb") as source:
            data = source.read(PREAMBLE_SIZE)
        if not valid_preamble(data):
            raise ValueError(f"{argv[2]}: invalid or missing GBAP v1 preamble")
        print(f"{argv[2]}: GBAP v1, 32x32 icon, entry 0x{ENTRY:04X}")
        return
    raise SystemExit(
        "usage: embed_app_icon.py size <icon.asm>\n"
        "       embed_app_icon.py inject <icon.asm> <linked.raw> <out.APP>\n"
        "       embed_app_icon.py check <file.APP>"
    )


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (OSError, ValueError) as error:
        raise SystemExit(error)
