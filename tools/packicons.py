#!/usr/bin/env python3
"""packicons - pack CPC icon .asm files into a GEOBENCH icon set (.IST).

A GEOBENCH icon set is a 16-byte header followed by the raw Mode 1 icons
concatenated in the desktop's fixed slot order. The desktop validates the
header, then loads the icons over its icon_set buffer.

Header (16 bytes):
    0-3   magic "GBIS"
    4     version (1)
    5     icon count
    6     icon width in bytes (8 = 32 px)
    7     icon height in rows (32)
    8-15  reserved (0)

Slot order (must match desktop/main.asm icon_set):
    floppy ide clock trash geobench basic binary picture text

Usage:
    tools/packicons.py <out.IST> <icon0.asm> <icon1.asm> ...
Each .asm must be a png2cpc 32x32 icon (exactly 256 bytes of db data).
"""
import sys, re

MAGIC = b'GBIS'
VERSION = 1
ICON_W = 8       # bytes per row (32 px in Mode 1)
ICON_H = 32      # rows
ICON_BYTES = ICON_W * ICON_H   # 256

def asm_bytes(path):
    data = bytearray()
    for line in open(path):
        s = line.strip()
        if s.startswith('db'):
            data += bytes(int(h, 16) for h in re.findall(r'#([0-9A-Fa-f]{2})', s))
    return bytes(data)

def main(argv):
    if len(argv) < 3:
        sys.exit("usage: packicons.py <out.IST> <icon.asm> ...")
    out, asms = argv[1], argv[2:]
    header = bytearray(16)
    header[0:4] = MAGIC
    header[4] = VERSION
    header[5] = len(asms)
    header[6] = ICON_W
    header[7] = ICON_H
    data = bytearray(header)
    for a in asms:
        b = asm_bytes(a)
        if len(b) != ICON_BYTES:
            sys.exit(f"{a}: {len(b)} bytes (expected {ICON_BYTES})")
        data += b
    with open(out, 'wb') as f:
        f.write(data)
    print(f"{out}: {len(asms)} icons, {len(data)} bytes "
          f"(16 header + {len(asms)}x{ICON_BYTES})")

if __name__ == '__main__':
    main(sys.argv)
