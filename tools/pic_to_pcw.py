#!/usr/bin/env python3
"""pic_to_pcw - transcode a GEOBENCH .PIC for the PCW CGA2 renderer.

The PCW target uses Screen-6-like 2bpp geometry, but its CGA2 display maps
GEOBENCH pens through a hardware permutation:

    screen = ((gb & 0x55) << 1) | (((~gb) & 0xAA) >> 1)

Most PCW drawing primitives apply that permutation while writing to the screen.
The picture path is different: Viewer/Desktop use GB_PICBLIT/gb_restorerect,
which call restore_block and copy raw screen bytes. PCW distribution .PIC files
therefore need their bitmap payload pre-permuted to hardware-space.

Input .PIC files are the normal CPC Mode-1 GBPC v2 assets. Output keeps the v2
container and stamps the mode byte to 6, but the pixel payload is PCW-ready raw
CGA2 bytes for restore_block.

Usage: tools/pic_to_pcw.py <in.PIC> <out.PIC>
"""
import sys

BIT0_FOR_PIXEL = (7, 6, 5, 4)   # CPC Mode 1: pen bit0 of pixel i
BIT1_FOR_PIXEL = (3, 2, 1, 0)   #             pen bit1 of pixel i


def mode1_to_screen6(byte):
    s6 = 0
    for i in range(4):
        pen = ((byte >> BIT0_FOR_PIXEL[i]) & 1) | (((byte >> BIT1_FOR_PIXEL[i]) & 1) << 1)
        s6 |= pen << (6 - 2 * i)
    return s6


def pcw_perm(gb):
    return (((gb & 0x55) << 1) | (((~gb) & 0xAA) >> 1)) & 0xFF


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: pic_to_pcw.py <in.PIC> <out.PIC>")
    data = bytearray(open(sys.argv[1], "rb").read())
    if data[:4] != b"GBPC" or data[4] != 2:
        sys.exit(f"{sys.argv[1]}: not a GBPC v2 .PIC")
    hdr, pix = data[:14], data[14:]
    hdr[5] = 6
    out = bytes(hdr) + bytes(pcw_perm(mode1_to_screen6(b)) for b in pix)
    open(sys.argv[2], "wb").write(out)
    print(f"{sys.argv[1]} -> {sys.argv[2]}  ({len(out)} bytes, PCW CGA2)")


if __name__ == "__main__":
    main()
