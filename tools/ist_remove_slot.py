#!/usr/bin/env python3
"""ist_remove_slot - delete one icon slot from a GEOBENCH .IST set.

The .IST directory is positional (slot N has a fixed meaning across all sets), so
when DEFAULT.IST drops a slot, every tracked custom set must drop the same slot to
stay aligned with the kernel/app icon indices. Recomputes the directory offsets and
the icon count (see tools/packicons.py for the format).

Usage:
    tools/ist_remove_slot.py <set.IST> <slot-index>
"""
import sys, struct

HDR = 16

def main(argv):
    if len(argv) != 3:
        sys.exit("usage: ist_remove_slot.py <set.IST> <slot-index>")
    path, slot = argv[1], int(argv[2])
    data = open(path, 'rb').read()
    if data[0:4] != b'GBIS':
        sys.exit(f"{path}: not a GBIS .IST file")
    ver, n = data[4], data[5]
    if not (0 <= slot < n):
        sys.exit(f"slot {slot} out of range (set has {n} icons)")
    dirs = [struct.unpack_from('<HBB', data, HDR + i * 4) for i in range(n)]
    bitmaps = [data[off:off + w * h] for (off, w, h) in dirs]
    del dirs[slot]
    del bitmaps[slot]
    n2 = len(dirs)
    new_dir = bytearray()
    blob = bytearray()
    off = HDR + n2 * 4
    for (_, w, h), bm in zip(dirs, bitmaps):
        new_dir += struct.pack('<HBB', off, w, h)
        blob += bm
        off += len(bm)
    hdr = bytearray(16)
    hdr[0:4] = b'GBIS'
    hdr[4] = ver
    hdr[5] = n2
    out = bytes(hdr) + bytes(new_dir) + bytes(blob)
    open(path, 'wb').write(out)
    print(f"{path}: removed slot {slot}: {n} -> {n2} icons, {len(data)} -> {len(out)} bytes")

if __name__ == "__main__":
    main(sys.argv)
