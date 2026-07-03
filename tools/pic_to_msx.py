#!/usr/bin/env python3
"""pic_to_msx - transcode a GEOBENCH .PIC from CPC Mode 1 to V9938 Screen 6 (#287).

The .PIC v2 container is identical on both platforms - a 14-byte header
("GBPC", ver 2, mode, width, height, 4 inks) then packed 4px/byte pixel data -
so only the in-byte pixel encoding and the mode byte change. This lets the
MSX2 Viewer show pictures made with the CPC tools (tools/picconv.py) without a
source image: read the Mode-1 .PIC, re-pack each byte for Screen 6, stamp the
mode byte 6.

Usage: tools/pic_to_msx.py <in.PIC> <out.PIC>
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


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: pic_to_msx.py <in.PIC> <out.PIC>")
    data = bytearray(open(sys.argv[1], "rb").read())
    if data[:4] != b"GBPC" or data[4] != 2:
        sys.exit(f"{sys.argv[1]}: not a GBPC v2 .PIC")
    hdr, pix = data[:14], data[14:]
    hdr[5] = 6                                   # mode byte -> Screen 6
    out = bytes(hdr) + bytes(mode1_to_screen6(b) for b in pix)
    open(sys.argv[2], "wb").write(out)
    print(f"{sys.argv[1]} -> {sys.argv[2]}  ({len(out)} bytes, Screen 6)")


if __name__ == "__main__":
    main()
