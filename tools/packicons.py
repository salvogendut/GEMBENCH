#!/usr/bin/env python3
"""packicons - pack CPC icon .asm files into a GEOBENCH icon set (.IST).

A set is a header, a per-icon directory, then the icon bitmaps. Each icon
carries its own size, so a set can mix sizes (a big drive icon, small system
icons, ...). The desktop reads each icon's size and lays out its box at draw
time.

Header (16 bytes):
    0-3   magic "GBIS"
    4     version (2)
    5     icon count
    6-15  reserved (0)

Directory (count * 4 bytes), one entry per slot in the desktop's order:
    0-1   offset of the icon data from the start of the file (little-endian)
    2     width in bytes (px = bytes*4, Mode 1)
    3     height in rows

Then the icon bitmaps (each width*height bytes), in slot order.

Slot order (must match kernel/gbkern.asm): floppy ide clock trash geobench
basic binary picture text.

Usage:
    tools/packicons.py <out.IST> <icon0.asm> <icon1.asm> ...
"""
import sys, re, struct

MAGIC = b'GBIS'
VERSION = 2
HDR = 16

def parse_icon(path):
    w = h = None
    data = bytearray()
    for line in open(path):
        s = line.strip()
        m = re.match(r'\w+_w\s+equ\s+(\d+)', s)
        if m: w = int(m.group(1))
        m = re.match(r'\w+_h\s+equ\s+(\d+)', s)
        if m: h = int(m.group(1))
        if s.startswith('db'):
            data += bytes(int(b, 16) for b in re.findall(r'#([0-9A-Fa-f]{2})', s))
    if w is None or h is None:
        sys.exit(f"{path}: missing _w/_h constants")
    if len(data) != w * h:
        sys.exit(f"{path}: {len(data)} bytes (expected {w}*{h}={w*h})")
    return w, h, bytes(data)

def main(argv):
    if len(argv) < 3:
        sys.exit("usage: packicons.py <out.IST> <icon.asm> ...")
    out, asms = argv[1], argv[2:]
    icons = [parse_icon(a) for a in asms]
    n = len(icons)

    header = bytearray(16)
    header[0:4] = MAGIC
    header[4] = VERSION
    header[5] = n

    directory = bytearray()
    blob = bytearray()
    off = HDR + n * 4                       # data starts after header + directory
    sizes = []
    for w, h, data in icons:
        directory += struct.pack('<HBB', off, w, h)
        blob += data
        sizes.append((w, h))
        off += len(data)

    with open(out, 'wb') as f:
        f.write(header)
        f.write(directory)
        f.write(blob)
    total = HDR + len(directory) + len(blob)
    szs = ' '.join(f'{w*4}x{h}' for w, h in sizes)
    print(f"{out}: {n} icons [{szs}], {total} bytes")

if __name__ == '__main__':
    main(sys.argv)
