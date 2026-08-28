#!/usr/bin/env python3
"""Build and inspect the optional GEOBENCH APP icon preamble.

GBAP v1 contains one canonical four-colour icon. GBAP v2 adds a resource
directory so an APP can carry both the portable four-colour icon and an
optional native MSX Screen-7 sixteen-colour variant. Headerless and v1
applications remain valid.

V2 layout:

    0..2    Z80 JP to the application entry point
    3..6    "GBAP"
    7       format version (2)
    8       resource count
    9       directory entry size (8)
    10..11  complete preamble size, little-endian
    12..13  directory offset (16), little-endian
    14..15  reserved
    16..    resource directory, then packed bitmap payloads

Each eight-byte directory entry contains codec, packed row width, height,
flags, payload length (word), and payload offset (word). Codec 1 is canonical
CPC Mode-1 packing (four pixels per byte); codec 7 is native Screen-7 packing
(two four-bit pixels per byte).
"""

import re
import struct
import sys

MAGIC = b"GBAP"
VERSION_V1 = 1
VERSION_V2 = 2
CODEC_MODE1 = 1
CODEC_SCREEN7 = 7
HEADER_SIZE = 16
DIR_ENTRY_SIZE = 8
ICON_WB = 8
ICON7_WB = 16
ICON_H = 32
ICON_SIZE = ICON_WB * ICON_H
ICON7_SIZE = ICON7_WB * ICON_H
PREAMBLE_SIZE = HEADER_SIZE + ICON_SIZE
DUAL_PREAMBLE_SIZE = HEADER_SIZE + 2 * DIR_ENTRY_SIZE + ICON_SIZE + ICON7_SIZE
APP_BASE = 0x4000
ENTRY = APP_BASE + PREAMBLE_SIZE


def _asm_value(text):
    text = text.strip()
    if text.startswith(("#", "$")):
        return int(text[1:], 16)
    if text.lower().startswith("0x"):
        return int(text[2:], 16)
    return int(text, 10)


def parse_icon(path, codec=CODEC_MODE1):
    width = height = None
    mode = 1
    data = bytearray()
    with open(path, encoding="ascii") as source:
        for line in source:
            text = line.split(";", 1)[0].strip()
            match = re.match(r"\w+_(w|h|mode)\s+equ\s+(\S+)", text,
                             re.IGNORECASE)
            if match:
                kind, value = match.groups()
                value = _asm_value(value)
                if kind.lower() == "w":
                    width = value
                elif kind.lower() == "h":
                    height = value
                else:
                    mode = value
            if re.match(r"^db\s+", text, re.IGNORECASE):
                for value in text[2:].split(","):
                    data.append(_asm_value(value))

    want_w = ICON_WB if codec == CODEC_MODE1 else ICON7_WB
    want_mode = 1 if codec == CODEC_MODE1 else 7
    want_size = want_w * ICON_H
    if codec not in (CODEC_MODE1, CODEC_SCREEN7):
        raise ValueError(f"unsupported APP icon codec {codec}")
    if (width != want_w or height != ICON_H or mode != want_mode
            or len(data) != want_size):
        description = "canonical Mode-1" if codec == CODEC_MODE1 \
            else "native MSX Screen-7"
        raise ValueError(
            f"{path}: APP icon must be a 32x32 {description} bitmap "
            f"(mode {want_mode}, {want_w}x{ICON_H} bytes); got mode {mode}, "
            f"{width}x{height}, {len(data)} bytes"
        )
    return bytes(data)


def _v1_preamble(icon):
    header = bytearray(HEADER_SIZE)
    header[0:3] = bytes((0xC3, ENTRY & 0xFF, ENTRY >> 8))
    header[3:7] = MAGIC
    header[7] = VERSION_V1
    header[8] = CODEC_MODE1
    header[9] = ICON_WB
    header[10] = ICON_H
    struct.pack_into("<HH", header, 11, ICON_SIZE, HEADER_SIZE)
    return bytes(header) + icon


def _v2_preamble(icon, icon16):
    resources = (
        (CODEC_MODE1, ICON_WB, icon),
        (CODEC_SCREEN7, ICON7_WB, icon16),
    )
    directory = bytearray(len(resources) * DIR_ENTRY_SIZE)
    payload = bytearray()
    offset = HEADER_SIZE + len(directory)
    for index, (codec, width, bitmap) in enumerate(resources):
        entry = index * DIR_ENTRY_SIZE
        directory[entry:entry + 4] = bytes((codec, width, ICON_H, 0))
        struct.pack_into("<HH", directory, entry + 4, len(bitmap), offset)
        payload.extend(bitmap)
        offset += len(bitmap)

    total = HEADER_SIZE + len(directory) + len(payload)
    header = bytearray(HEADER_SIZE)
    entry = APP_BASE + total
    header[0:3] = bytes((0xC3, entry & 0xFF, entry >> 8))
    header[3:7] = MAGIC
    header[7] = VERSION_V2
    header[8] = len(resources)
    header[9] = DIR_ENTRY_SIZE
    struct.pack_into("<HH", header, 10, total, HEADER_SIZE)
    return bytes(header + directory + payload)


def make_preamble(icon, icon16=None):
    if len(icon) != ICON_SIZE:
        raise ValueError("invalid four-colour APP icon length")
    if icon16 is None:
        return _v1_preamble(icon)
    if len(icon16) != ICON7_SIZE:
        raise ValueError("invalid sixteen-colour APP icon length")
    return _v2_preamble(icon, icon16)


def parse_resources(data):
    """Return (preamble_size, resource dictionaries), or raise ValueError."""
    if len(data) < HEADER_SIZE or data[0] != 0xC3 or data[3:7] != MAGIC:
        raise ValueError("missing GBAP executable preamble")
    version = data[7]
    if version == VERSION_V1:
        if len(data) < PREAMBLE_SIZE:
            raise ValueError("truncated GBAP v1 preamble")
        if (data[1] != (ENTRY & 0xFF) or data[2] != (ENTRY >> 8)
                or data[8] != CODEC_MODE1 or data[9] != ICON_WB
                or data[10] != ICON_H
                or struct.unpack_from("<H", data, 11)[0] != ICON_SIZE
                or struct.unpack_from("<H", data, 13)[0] != HEADER_SIZE):
            raise ValueError("invalid GBAP v1 metadata")
        return PREAMBLE_SIZE, [{
            "codec": CODEC_MODE1, "wbytes": ICON_WB, "height": ICON_H,
            "length": ICON_SIZE, "offset": HEADER_SIZE,
        }]
    if version != VERSION_V2:
        raise ValueError(f"unsupported GBAP version {version}")

    count = data[8]
    entry_size = data[9]
    total, directory_offset = struct.unpack_from("<HH", data, 10)
    if (count == 0 or count > 8 or entry_size != DIR_ENTRY_SIZE
            or directory_offset != HEADER_SIZE
            or total < HEADER_SIZE + count * DIR_ENTRY_SIZE
            or len(data) < total):
        raise ValueError("invalid GBAP v2 header")
    entry = APP_BASE + total
    if data[1] != (entry & 0xFF) or data[2] != (entry >> 8):
        raise ValueError("GBAP v2 entry point does not follow its preamble")

    resources = []
    occupied = []
    for index in range(count):
        pos = directory_offset + index * entry_size
        codec, width, height, flags = data[pos:pos + 4]
        length, offset = struct.unpack_from("<HH", data, pos + 4)
        expected_width = ICON_WB if codec == CODEC_MODE1 else \
            ICON7_WB if codec == CODEC_SCREEN7 else 0
        if (not expected_width or width != expected_width or height != ICON_H
                or flags != 0 or length != width * height
                or offset < directory_offset + count * entry_size
                or offset + length > total):
            raise ValueError(f"invalid GBAP v2 resource {index}")
        if any(offset < end and offset + length > start
               for start, end in occupied):
            raise ValueError("overlapping GBAP v2 resources")
        occupied.append((offset, offset + length))
        resources.append({
            "codec": codec, "wbytes": width, "height": height,
            "length": length, "offset": offset,
        })
    if resources[0]["codec"] != CODEC_MODE1:
        raise ValueError("GBAP v2 resource 0 must be the portable four-colour icon")
    if len({item["codec"] for item in resources}) != len(resources):
        raise ValueError("duplicate GBAP v2 icon codec")
    return total, resources


def valid_preamble(data):
    try:
        parse_resources(data)
        return True
    except (ValueError, struct.error):
        return False


def inject(icon_path, raw_path, out_path, icon16_path=None):
    icon = parse_icon(icon_path, CODEC_MODE1)
    icon16 = parse_icon(icon16_path, CODEC_SCREEN7) if icon16_path else None
    preamble = make_preamble(icon, icon16)
    with open(raw_path, "rb") as source:
        raw = bytearray(source.read())
    if len(raw) < len(preamble):
        raise ValueError(f"{raw_path}: linked image is shorter than the APP preamble")
    padding = raw[:len(preamble)]
    if padding[0] not in (0x00, 0xFF) or any(value != padding[0] for value in padding):
        raise ValueError(
            f"{raw_path}: linked image does not reserve {len(preamble)} bytes at 0x4000"
        )
    raw[:len(preamble)] = preamble
    with open(out_path, "wb") as target:
        target.write(raw)


def main(argv):
    if argv[1:2] == ["size"] and len(argv) in (3, 4):
        icon = parse_icon(argv[2], CODEC_MODE1)
        icon16 = parse_icon(argv[3], CODEC_SCREEN7) if len(argv) == 4 else None
        print(len(make_preamble(icon, icon16)))
        return
    if argv[1:2] == ["inject"] and len(argv) in (5, 6):
        if len(argv) == 5:
            inject(argv[2], argv[3], argv[4])
        else:
            inject(argv[2], argv[4], argv[5], argv[3])
        return
    if argv[1:2] == ["check"] and len(argv) == 3:
        with open(argv[2], "rb") as source:
            data = source.read()
        total, resources = parse_resources(data)
        codecs = "/".join(str(item["codec"]) for item in resources)
        print(f"{argv[2]}: GBAP v{data[7]}, codecs {codecs}, "
              f"entry 0x{APP_BASE + total:04X}")
        return
    raise SystemExit(
        "usage: embed_app_icon.py size <icon4.asm> [icon16.asm]\n"
        "       embed_app_icon.py inject <icon4.asm> [icon16.asm] "
        "<linked.raw> <out.APP>\n"
        "       embed_app_icon.py check <file.APP>"
    )


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (IndexError, OSError, ValueError) as error:
        raise SystemExit(error)
