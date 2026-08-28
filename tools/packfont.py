#!/usr/bin/env python3
"""packfont - pack an 8x8 bitmap-font .asm into a GEOBENCH font set (.FNT).

Reads a font source like lib/font.asm (FONT_FIRST/FONT_LAST equ + `db` rows of
hex bytes, 8 bytes per glyph, bit 7 = leftmost pixel) and writes the same .FNT
container genfont.py produces, with width 8. The desktop's renderer handles an
8 px glyph as two byte-aligned Mode 1 bytes, so CLASSIC.FNT reproduces the
original fixed font exactly. Select it with FONT=CLASSIC in GEOBENCH.CFG.

Usage:
    tools/packfont.py <out.FNT> <font.asm>
"""
import sys, re, struct

MAGIC = b'GBFN'
VERSION = 1
HDR = 16
HEIGHT = 8


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: packfont.py <out.FNT> <font.asm>")
    out, src = argv[1], argv[2]
    first = last = None
    data = bytearray()
    for line in open(src):
        s = line.strip()
        m = re.match(r'FONT_FIRST\s+equ\s+(\d+)', s)
        if m:
            first = int(m.group(1))
        m = re.match(r'FONT_LAST\s+equ\s+(\d+)', s)
        if m:
            last = int(m.group(1))
        if s.startswith('db'):
            data += bytes(int(b, 16) for b in re.findall(r'#([0-9A-Fa-f]{2})', s))
    if first is None or last is None:
        sys.exit(f"{src}: missing FONT_FIRST/FONT_LAST")
    count = last - first + 1
    if len(data) != count * HEIGHT:
        sys.exit(f"{src}: {len(data)} glyph bytes (expected {count}*{HEIGHT}={count*HEIGHT})")

    header = bytearray(16)
    header[0:4] = MAGIC
    header[4] = VERSION
    header[5] = first
    header[6] = last
    header[7] = 8                 # width in pixels
    header[8] = HEIGHT
    header[9] = 1                 # bytes per row
    with open(out, 'wb') as f:
        f.write(header)
        f.write(data)
    print(f"{out}: {count} glyphs 8x{HEIGHT}, {HDR + len(data)} bytes")


if __name__ == '__main__':
    main(sys.argv)
