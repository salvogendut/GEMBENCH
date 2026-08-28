#!/usr/bin/env python3
"""png2backdrop - convert a 16x16 PNG into a GEOBENCH .BDP desktop tile.

A backdrop tile is a 16x16 Mode-1 pattern the desktop repeats behind the icons
and windows (the GEOS/Workbench dither look). Each pixel is quantised to one of
the 4 desktop pens (blue paper / white / black / red) and packed Mode-1 (4 px per
byte). Output is a raw 64-byte file: 16 rows x 4 bytes, no header.

    tools/png2backdrop.py <in.png> <out.BDP>

The kernel loads the .BDP into a low-RAM tile buffer at boot (BACKDROP=<name>) and
fill_pattern repeats it, phased off absolute screen x,y so adjacent fills line up.
The output is always portable canonical Mode-1; MSX2 and PCW transcode it when
the backdrop is loaded.
"""
import sys
from PIL import Image


# The desktop pens, by their default ink colour. A pixel maps to the nearest one.
PENS = [((0, 0, 170), 0),        # pen 0: blue (paper / backdrop)
        ((255, 255, 255), 1),    # pen 1: white
        ((0, 0, 0), 2),          # pen 2: black
        ((255, 0, 0), 3)]        # pen 3: red
BIT0_FOR_PIXEL = (7, 6, 5, 4)    # Mode-1: pen bit0 of pixel i
BIT1_FOR_PIXEL = (3, 2, 1, 0)    # Mode-1: pen bit1 of pixel i

TILE = 16


def nearest_pen(rgb):
    best, bd = 0, None
    for (r, g, b), pen in PENS:
        d = (r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2
        if bd is None or d < bd:
            best, bd = pen, d
    return best


def mode1_byte(pens4):
    b = 0
    for i, pen in enumerate(pens4):
        if pen & 1:
            b |= 1 << BIT0_FOR_PIXEL[i]
        if pen & 2:
            b |= 1 << BIT1_FOR_PIXEL[i]
    return b


def main():
    argv = sys.argv[1:]
    if argv and argv[0] == '--platform':
        sys.exit("--platform is no longer supported for .BDP; output is always canonical Mode-1")
    if len(argv) != 2:
        print(__doc__)
        sys.exit(2)
    in_png, out_bdp = argv
    img = Image.open(in_png).convert("RGB")
    if img.size != (TILE, TILE):
        img = img.resize((TILE, TILE), Image.NEAREST)   # tolerate other sizes
    px = img.load()

    blob = bytearray()
    for y in range(TILE):
        for bx in range(0, TILE, 4):                    # 4 px -> 1 Mode-1 byte
            pens4 = [nearest_pen(px[bx + i, y]) for i in range(4)]
            blob.append(mode1_byte(pens4))
    with open(out_bdp, "wb") as f:
        f.write(blob)
    print(f"{in_png}: backdrop .BDP {TILE}x{TILE} (canonical Mode-1) -> {len(blob)} bytes ({out_bdp})")


if __name__ == "__main__":
    main()
