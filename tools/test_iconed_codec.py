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

# --- .SPR cursor: 16x16, file = d0,m0,d2,m2 (each W*H bytes); phase2 = +2 px ---

CUR_W = 4   # bytes (cursor_arrow_w)
CUR_H = 16  # rows  (cursor_arrow_h)
PHASE = CUR_W * CUR_H  # 64

def decode_cursor(data, di, mi):
    """data[di:], mask[mi:] (one phase) -> grid: 0 = transparent, else pen 1..3."""
    grid = [[0] * (CUR_W * 4) for _ in range(CUR_H)]
    for y in range(CUR_H):
        for bx in range(CUR_W):
            d = data[di + y * CUR_W + bx]
            m = data[mi + y * CUR_W + bx]
            for i in range(4):
                if (m >> (7 - i)) & 1:        # mask bit set -> transparent
                    grid[y][bx * 4 + i] = 0
                else:
                    grid[y][bx * 4 + i] = decode_pixel(d, i)
    return grid

def encode_cursor_phase(grid, shift):
    """grid (16 wide) -> (data, mask) for the given +shift px, dropping x+shift>=16."""
    dout = bytearray(PHASE)
    mout = bytearray(PHASE)
    for y in range(CUR_H):
        for bx in range(CUR_W):
            d = 0
            m = 0
            for i in range(4):
                x = bx * 4 + i - shift     # source pixel for this output column
                pen = grid[y][x] if 0 <= x < CUR_W * 4 else 0
                if pen == 0:               # transparent -> mask both bits, data 0
                    m = set_pixel(m, i, 3)
                else:
                    d = set_pixel(d, i, pen)
            dout[y * CUR_W + bx] = d
            mout[y * CUR_W + bx] = m
    return bytes(dout), bytes(mout)

def test_spr(path):
    data = open(path, "rb").read()
    assert len(data) == 4 * PHASE, f"{path}: expected {4*PHASE} bytes, got {len(data)}"
    grid = decode_cursor(data, 0, PHASE)                 # phase 0: d0 @0, m0 @64
    d0, m0 = encode_cursor_phase(grid, 0)
    d2, m2 = encode_cursor_phase(grid, 2)
    assert d0 == data[0:PHASE],            f"{path}: d0 mismatch"
    assert m0 == data[PHASE:2*PHASE],      f"{path}: m0 mismatch"
    assert d2 == data[2*PHASE:3*PHASE],    f"{path}: d2 regen mismatch"
    assert m2 == data[3*PHASE:4*PHASE],    f"{path}: m2 regen mismatch"
    print(f"OK  {path}: phase0 round-trips and d2/m2 regenerate from +2px shift")

if __name__ == "__main__":
    test_ist("build/DEFAULT.IST")
    test_ist("build/MIXED.IST")   # also v2 (mixed icon sizes -> exercises per-icon w/h)
    test_spr("build/DEFAULT.SPR")
    test_spr("build/HAND.SPR")
    print("All ICONED codec round-trip checks passed.")
