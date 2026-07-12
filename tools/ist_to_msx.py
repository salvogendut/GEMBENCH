#!/usr/bin/env python3
"""ist_to_msx - legacy host-side GEOBENCH .IST transcoder.

The .IST v2 container ("GBIS", version 2, count, then a directory of
{offset u16le, width_bytes u8, height u8} and the packed icon bitmaps) is
identical on both platforms - only the in-byte pixel packing differs. This
re-packs each icon's bitmap bytes for Screen 6, leaving the header and directory
untouched, so an icon set authored with the CPC tools (packicons.py / iconedit.py)
drops straight into old MSX builds. Current CPC, MSX, and PCW distributions all
store the canonical input unchanged and let the kernel transcode it at runtime;
this utility remains only for inspecting or supporting older artifacts.

Usage: tools/ist_to_msx.py <in.IST> <out.IST>
"""
import struct
import sys

HDR = 16


def mode1_to_screen6(byte):
    s6 = 0
    for i in range(4):
        pen = ((byte >> (7 - i)) & 1) | (((byte >> (3 - i)) & 1) << 1)
        s6 |= pen << (6 - 2 * i)
    return s6


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: ist_to_msx.py <in.IST> <out.IST>")
    data = bytearray(open(sys.argv[1], "rb").read())
    if data[:4] != b"GBIS" or data[4] != 2:
        sys.exit(f"{sys.argv[1]}: not a GBIS v2 .IST")
    n = data[5]
    for k in range(n):
        off, w, h = struct.unpack_from("<HBB", data, HDR + k * 4)
        for i in range(off, off + w * h):
            data[i] = mode1_to_screen6(data[i])
    open(sys.argv[2], "wb").write(data)
    print(f"{sys.argv[1]} -> {sys.argv[2]}  ({n} icons, {len(data)} bytes, Screen 6)")


if __name__ == "__main__":
    main()
