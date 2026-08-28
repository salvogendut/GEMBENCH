#!/usr/bin/env python3
"""Codec checks for the tileable title-bar experiment."""

import random

from titlebaredit import (
    CLOSE_BYTES,
    CLOSE_H,
    CLOSE_W,
    GADGET_BYTES,
    MAX_BYTES,
    MAX_H,
    MAX_W,
    THEME_BYTES,
    TILE_BYTES,
    TILE_H,
    TILE_W,
    decode_theme,
    decode_gdt,
    decode_tbr,
    default_close_grid,
    default_max_grid,
    encode_theme,
    encode_gdt,
    encode_tbr,
    ellipse_points,
    flood_fill_grid,
    line_points,
    rectangle_points,
    sample_grid,
    shift_grid,
    spray_points,
    stripe_grid,
)


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print(f"ok   {message}")


def main() -> None:
    stripes = stripe_grid()
    encoded = encode_tbr(stripes)
    check(len(encoded) == TILE_BYTES, "title tile is exactly 56 bytes")
    check(decode_tbr(encoded) == stripes, "stripe tile round-trips")

    close = default_close_grid()
    maximize = default_max_grid()
    gadgets = encode_gdt(close, maximize)
    check(len(gadgets) == GADGET_BYTES == CLOSE_BYTES + MAX_BYTES,
          "gadget theme is exactly 50 bytes")
    check(decode_gdt(gadgets) == (close, maximize),
          "close and maximize gadgets round-trip independently")
    theme = encode_theme(stripes, close, maximize)
    check(len(theme) == THEME_BYTES == TILE_BYTES + CLOSE_BYTES + MAX_BYTES,
          "title theme is exactly 106 bytes")
    decoded_title, decoded_close, decoded_max = decode_theme(theme)
    check(decoded_title == stripes and decoded_close == close and decoded_max == maximize,
          "title and gadget tiles round-trip")
    legacy_title, legacy_close, legacy_max = decode_theme(encoded)
    check(legacy_title == stripes and legacy_close == close and legacy_max == maximize,
          "legacy themes receive traditional gadgets")
    check(len(close) == CLOSE_H and all(len(row) == CLOSE_W for row in close),
          "close gadget is 8x10")
    check(len(maximize) == MAX_H and all(len(row) == MAX_W for row in maximize),
          "maximize gadget is 12x10")

    sample = sample_grid()
    check(len(sample) == TILE_H and all(len(row) == TILE_W for row in sample),
          "sample tile is 16x14")
    check(decode_tbr(encode_tbr(sample)) == sample, "sample weave round-trips")

    known = [[0] * TILE_W for _ in range(TILE_H)]
    known[0][:4] = [1, 2, 3, 0]
    check(encode_tbr(known)[0] == 0xA6, "canonical Mode-1 pixel packing")

    try:
        decode_theme(bytes(TILE_BYTES - 1))
    except ValueError:
        check(True, "truncated tiles are rejected")
    else:
        check(False, "truncated tiles are rejected")

    check(line_points(0, 0, 4, 4) == [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)],
          "line tool uses inclusive Bresenham pixels")
    outline = set(rectangle_points(1, 1, 3, 3, False))
    check(len(outline) == 8 and (2, 2) not in outline,
          "outlined square leaves its centre untouched")
    filled = set(rectangle_points(1, 1, 3, 3, True))
    check(len(filled) == 9 and (2, 2) in filled,
          "filled square covers its centre")
    circle = set(ellipse_points(0, 0, 4, 4, False))
    check({(0, 2), (2, 0), (4, 2), (2, 4)} <= circle,
          "circle tool reaches each bounding-box edge")
    disk = set(ellipse_points(0, 0, 4, 4, True))
    check((2, 2) in disk and (0, 0) not in disk,
          "filled circle covers its centre without filling corners")

    fill_grid = [[0, 0, 1], [0, 1, 1], [2, 2, 1]]
    changed = flood_fill_grid(fill_grid, 0, 0, 3)
    check(len(changed) == 3 and fill_grid[0][2] == 1,
          "bucket fill is bounded by other pens")
    spray = spray_points(8, 6, 0, 0, random.Random(7))
    check((0, 0) in spray and all(0 <= x < 8 and 0 <= y < 6 for x, y in spray),
          "spray paint clips at canvas edges")
    shifted = shift_grid([[1, 2], [3, 0]], 1, 0)
    check(shifted == [[0, 1], [0, 3]],
          "arrow control shifts one pixel and clears the exposed edge")

    print("\nall title-bar tile tests passed")


if __name__ == "__main__":
    main()
