#!/usr/bin/env python3
"""Validate and list GEOBENCH distribution pictures by target."""

import argparse
import struct
from pathlib import Path


def picture_mode(path: Path) -> int:
    data = path.read_bytes()
    if len(data) < 14 or data[:5] != b"GBPC\x02":
        raise ValueError(f"{path}: expected a GBPC v2 picture")

    mode = data[5]
    width, height = struct.unpack_from("<HH", data, 6)
    if width < 4 or width % 4 or height < 1:
        raise ValueError(f"{path}: invalid {width}x{height} dimensions")
    if mode == 1:
        stride = width // 4
    elif mode == 7:
        if width > 512 or height > 255:
            raise ValueError(f"{path}: Screen 7 picture exceeds 512x255")
        stride = width // 2
    else:
        raise ValueError(f"{path}: unsupported GBPC mode {mode}")
    expected = 14 + stride * height
    if len(data) != expected:
        raise ValueError(f"{path}: expected {expected} bytes, found {len(data)}")
    return mode


def catalog_paths(directory: Path, target: str) -> list[Path]:
    paths = []
    for path in sorted(directory.glob("*.PIC")):
        mode = picture_mode(path)
        if mode == 1 or target == "msx":
            paths.append(path)
    return paths


def main() -> None:
    parser = argparse.ArgumentParser(
        description="List validated distribution pictures for a target")
    parser.add_argument("target", choices=("portable", "msx"))
    parser.add_argument("directory", nargs="?", default="assets/pictures")
    args = parser.parse_args()
    try:
        for path in catalog_paths(Path(args.directory), args.target):
            print(path)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
