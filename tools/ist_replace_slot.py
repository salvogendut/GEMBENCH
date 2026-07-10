#!/usr/bin/env python3
"""Replace one bitmap in a positional GEOBENCH .IST icon set.

Usage:
    tools/ist_replace_slot.py <set.IST> <slot-index> <icon.asm>
"""
import re
import struct
import sys

HDR = 16


def parse_icon(path):
    width = height = None
    data = bytearray()
    for line in open(path):
        text = line.strip()
        match = re.match(r'\w+_w\s+equ\s+(\d+)', text)
        if match:
            width = int(match.group(1))
        match = re.match(r'\w+_h\s+equ\s+(\d+)', text)
        if match:
            height = int(match.group(1))
        if text.startswith('db'):
            data += bytes(int(value, 16)
                          for value in re.findall(r'#([0-9A-Fa-f]{2})', text))
    if width is None or height is None:
        sys.exit(f"{path}: missing _w/_h constants")
    if len(data) != width * height:
        sys.exit(f"{path}: {len(data)} bytes (expected {width}*{height}={width * height})")
    return width, height, bytes(data)


def main(argv):
    if len(argv) != 4:
        sys.exit("usage: ist_replace_slot.py <set.IST> <slot-index> <icon.asm>")
    path, slot, icon_path = argv[1], int(argv[2]), argv[3]
    raw = open(path, 'rb').read()
    if raw[0:4] != b'GBIS':
        sys.exit(f"{path}: not a GBIS .IST file")
    count = raw[5]
    if not 0 <= slot < count:
        sys.exit(f"slot {slot} out of range (set has {count} icons)")

    entries = [struct.unpack_from('<HBB', raw, HDR + index * 4)
               for index in range(count)]
    bitmaps = [raw[offset:offset + width * height]
               for offset, width, height in entries]
    width, height, bitmap = parse_icon(icon_path)
    entries[slot] = (0, width, height)
    bitmaps[slot] = bitmap

    directory = bytearray()
    blob = bytearray()
    offset = HDR + count * 4
    for (_, item_width, item_height), item_bitmap in zip(entries, bitmaps):
        directory += struct.pack('<HBB', offset, item_width, item_height)
        blob += item_bitmap
        offset += len(item_bitmap)

    header = bytearray(raw[:HDR])
    with open(path, 'wb') as output:
        output.write(header + directory + blob)
    print(f"{path}: replaced slot {slot} with {icon_path} ({width * 4}x{height})")


if __name__ == '__main__':
    main(sys.argv)
