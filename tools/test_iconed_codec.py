#!/usr/bin/env python3
"""Host round-trip check for ICONED's Mode-1 icon/cursor codec.

ICONED (apps/iconed/main.c) edits .IST icon sets and .SPR cursors on the CPC, so
its encode/decode must invert what packicons.py / png2spr.py produce byte-for-byte
- including regenerating a cursor's 2nd pre-shifted phase (d2/m2) from phase 0.

This models the exact integer math the C will use, then asserts:
  * every icon in build/DEFAULT.IST decodes->re-encodes identically;
  * build/DEFAULT.SPR's d2/m2 are reproduced by shifting phase-0 +2 px.

Run: python3 tools/test_iconed_codec.py
"""
import sys, struct

# --- Mode-1 pixel packing (matches png2spr.py: pixel i bit0 @ 7-i, bit1 @ 3-i) ---

def decode_pixel(b, i):
    return ((b >> (7 - i)) & 1) | (((b >> (3 - i)) & 1) << 1)

def set_pixel(b, i, pen):
    if pen & 1:
        b |= 1 << (7 - i)
    if pen & 2:
        b |= 1 << (3 - i)
    return b

# --- .IST icon set: decode bitmap -> pen grid, re-encode grid -> bytes ---

def decode_icon(data, off, wbytes, h):
    grid = [[0] * (wbytes * 4) for _ in range(h)]
    for y in range(h):
        for bx in range(wbytes):
            b = data[off + y * wbytes + bx]
            for i in range(4):
                grid[y][bx * 4 + i] = decode_pixel(b, i)
    return grid

def encode_icon(grid, wbytes, h):
    out = bytearray(wbytes * h)
    for y in range(h):
        for bx in range(wbytes):
            b = 0
            for i in range(4):
                b = set_pixel(b, i, grid[y][bx * 4 + i])
            out[y * wbytes + bx] = b
    return bytes(out)

def test_ist(path):
    data = open(path, "rb").read()
    assert data[:4] == b"GBIS", f"{path}: not a GBIS set"
    assert data[4] == 2, f"{path}: version {data[4]} (ICONED supports v2 only)"
    count = data[5]
    for k in range(count):
        off, wbytes, h = struct.unpack_from("<HBB", data, 16 + k * 4)
        grid = decode_icon(data, off, wbytes, h)
        re = encode_icon(grid, wbytes, h)
        orig = data[off:off + wbytes * h]
        assert re == orig, f"{path}: icon {k} round-trip mismatch"
    print(f"OK  {path}: {count} icons decode/re-encode identically")

# --- .SPR cursor -------------------------------------------------------------
# CPC: 256 bytes = two pre-shifted phases (shift 0, shift 2), each 128 bytes with
# mask,data INTERLEAVED per byte-column. MSX2: a 66-byte V9938 hardware sprite
# (hotspot + outline plane + fill plane). Both match tools/png2spr.py.
CUR_W = 4   # byte-columns per row
CUR_H = 16  # rows
CPC_PHASE = CUR_H * CUR_W * 2   # 128 bytes/phase (mask,data interleaved)

def decode_cursor(data):
    """CPC phase 0 -> grid: 0 = transparent, else pen 1..3."""
    grid = [[0] * (CUR_W * 4) for _ in range(CUR_H)]
    for y in range(CUR_H):
        for bx in range(CUR_W):
            off = y * (CUR_W * 2) + bx * 2      # phase 0: mask, data
            m, d = data[off], data[off + 1]
            for i in range(4):
                grid[y][bx * 4 + i] = 0 if (m >> (7 - i)) & 1 else decode_pixel(d, i)
    return grid

def encode_phase(grid, shift):
    """grid -> one interleaved 128-byte phase at the given +shift px."""
    out = bytearray()
    for y in range(CUR_H):
        for bx in range(CUR_W):
            d = m = 0
            for i in range(4):
                x = bx * 4 + i - shift
                pen = grid[y][x] if 0 <= x < CUR_W * 4 else 0
                if pen == 0:
                    m = set_pixel(m, i, 3)
                else:
                    d = set_pixel(d, i, pen)
            out += bytes((m, d))
    return bytes(out)

def test_spr(path):
    data = open(path, "rb").read()
    assert len(data) == 2 * CPC_PHASE, f"{path}: expected {2*CPC_PHASE} bytes, got {len(data)}"
    grid = decode_cursor(data)
    assert encode_phase(grid, 0) == data[0:CPC_PHASE],           f"{path}: phase 0 mismatch"
    assert encode_phase(grid, 2) == data[CPC_PHASE:2*CPC_PHASE], f"{path}: phase 2 (+2px) regen mismatch"
    print(f"OK  {path}: phase 0 round-trips and phase 2 regenerates from +2px shift")

def test_msx_spr(path):
    """MSX2 66-byte sprite: decode both planes to a grid, re-encode, byte-identical."""
    data = open(path, "rb").read()
    assert len(data) == 66, f"{path}: expected 66 bytes, got {len(data)}"
    grid = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            idx = (0 if x < 8 else 16) + y
            bit = 0x80 >> (x & 7)
            grid[y][x] = 1 if data[2 + idx] & bit else (3 if data[34 + idx] & bit else 0)
    out = bytearray(66)
    out[0], out[1] = data[0], data[1]
    for y in range(16):
        for x in range(16):
            idx = (0 if x < 8 else 16) + y
            bit = 0x80 >> (x & 7)
            if grid[y][x] == 1:
                out[2 + idx] |= bit
            elif grid[y][x] == 3:
                out[34 + idx] |= bit
    assert bytes(out) == data, f"{path}: MSX2 sprite round-trip mismatch"
    print(f"OK  {path}: MSX2 hardware-sprite round-trips (outline + fill planes)")

if __name__ == "__main__":
    import os
    test_ist("build/DEFAULT.IST")
    test_ist("build/MIXED.IST")   # also v2 (mixed icon sizes -> exercises per-icon w/h)
    test_spr("build/DEFAULT.SPR")
    if os.path.exists("build/msx/DEFAULT.SPR"):
        test_msx_spr("build/msx/DEFAULT.SPR")
    test_spr("build/HAND.SPR")
    print("All ICONED codec round-trip checks passed.")
