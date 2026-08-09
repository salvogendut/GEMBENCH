#!/usr/bin/env python3
"""Codec checks for the tileable title-bar experiment."""

from titlebaredit import (
    CLOSE_BYTES,
    CLOSE_H,
    CLOSE_W,
    MAX_BYTES,
    MAX_H,
    MAX_W,
    THEME_BYTES,
    TILE_BYTES,
    TILE_H,
    TILE_W,
    decode_theme,
    decode_tbr,
    default_close_grid,
    default_max_grid,
    encode_theme,
    encode_tbr,
    sample_grid,
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

    print("\nall title-bar tile tests passed")


if __name__ == "__main__":
    main()
