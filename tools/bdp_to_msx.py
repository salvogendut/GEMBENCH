#!/usr/bin/env python3
"""bdp_to_msx - legacy host-side GEOBENCH .BDP transcoder.

A .BDP is a raw 64-byte 16x16 Mode-1 tile (no header). Both platforms pack 4 px
per byte, so only the in-byte bit layout changes: this re-packs each byte for
Screen 6 for old MSX builds. Current CPC, MSX2, and PCW distributions all store
the canonical input unchanged and let the kernel transcode it at load time; this
utility remains only for inspecting or supporting older artifacts.

Usage: tools/bdp_to_msx.py <in.BDP> <out.BDP>
"""
import sys


def mode1_to_screen6(byte):
    s6 = 0
    for i in range(4):
        pen = ((byte >> (7 - i)) & 1) | (((byte >> (3 - i)) & 1) << 1)
        s6 |= pen << (6 - 2 * i)
    return s6


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: bdp_to_msx.py <in.BDP> <out.BDP>")
    data = open(sys.argv[1], "rb").read()
    open(sys.argv[2], "wb").write(bytes(mode1_to_screen6(b) for b in data))
    print(f"{sys.argv[1]} -> {sys.argv[2]}  ({len(data)} bytes, Screen 6)")


if __name__ == "__main__":
    main()
