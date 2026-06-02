#!/usr/bin/env python3
"""packicons - pack CPC icon .asm files into a GEOBENCH icon set (.IST).

A GEOBENCH icon set is just the raw 256-byte (8x32, Mode 1) icons concatenated
in the desktop's fixed slot order, no header. The desktop loads it over its
icon_set buffer, so the byte layout must match the slot order exactly.

Slot order (must match desktop/main.asm icon_set):
    floppy ide clock trash geobench basic binary picture text

Usage:
    tools/packicons.py <out.IST> <icon0.asm> <icon1.asm> ...
Each .asm must be a png2cpc 32x32 icon (exactly 256 bytes of db data).
"""
import sys, re

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
    data = bytearray()
    for a in asms:
        b = asm_bytes(a)
        if len(b) != 256:
            sys.exit(f"{a}: {len(b)} bytes (expected 256)")
        data += b
    with open(out, 'wb') as f:
        f.write(data)
    print(f"{out}: {len(asms)} icons, {len(data)} bytes")

if __name__ == '__main__':
    main(sys.argv)
