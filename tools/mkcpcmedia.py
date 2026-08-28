#!/usr/bin/env python3
"""Build an extended AMSDOS DATA .DSK for the CPC picture gallery.

The complete gallery is larger than a 40-track CF2. This builder therefore uses
an 80-track, single-sided geometry with the normal DATA sector IDs (C1-C9), 1K
allocation blocks, and 8-bit CP/M block numbers. GEOBENCH's CPC floppy backend
can read that layout without a side-selection or filesystem change.

Usage:
  mkcpcmedia.py OUT.dsk --add FILE[=NAME] [--add ...]
"""

import argparse
import sys
from pathlib import Path


TRACKS = 80
SIDES = 1
SECTORS_PER_TRACK = 9
SECTOR_SIZE = 512
BLOCK_SIZE = 1024
DIR_BLOCKS = 2
SECTOR_IDS = tuple(range(0xC1, 0xCA))
TRACK_SIZE = 256 + SECTORS_PER_TRACK * SECTOR_SIZE


def name83(path: Path, override: str) -> tuple[str, str, bytes]:
    name = (override or path.name).upper()
    base, dot, ext = name.partition(".")
    if not dot or not base or not ext or len(base) > 8 or len(ext) > 3:
        raise ValueError(f"{name}: expected an 8.3 filename")
    try:
        packed = (base.ljust(8) + ext.ljust(3)).encode("ascii")
    except UnicodeEncodeError as exc:
        raise ValueError(f"{name}: filename must be ASCII") from exc
    return base, ext, packed


def amsdos_header(raw: bytes, base: str, ext: str) -> bytes:
    header = bytearray(128)
    header[1:9] = base.ljust(8).encode("ascii")
    header[9:12] = ext.ljust(3).encode("ascii")
    header[18] = 2                       # unprotected binary
    length = len(raw)
    header[24] = length & 0xFF
    header[25] = (length >> 8) & 0xFF    # logical length used by GEOBENCH
    header[64] = length & 0xFF
    header[65] = (length >> 8) & 0xFF
    header[66] = (length >> 16) & 0xFF
    checksum = sum(header[:67]) & 0xFFFF
    header[67] = checksum & 0xFF
    header[68] = checksum >> 8
    return bytes(header)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("out")
    parser.add_argument(
        "--add", action="append", default=[], metavar="FILE[=NAME]",
        help="add a file, optionally overriding its 8.3 disk name",
    )
    args = parser.parse_args()
    if not args.add:
        parser.error("at least one --add is required")

    sector_count = TRACKS * SECTORS_PER_TRACK
    sectors = [bytearray(b"\xE5" * SECTOR_SIZE) for _ in range(sector_count)]
    addressable_blocks = min(256, sector_count * SECTOR_SIZE // BLOCK_SIZE)
    directory = []
    next_block = DIR_BLOCKS
    seen = set()

    def put_sector(lsn: int, payload: bytes) -> None:
        if lsn >= sector_count:
            raise ValueError("logical sector exceeds disk geometry")
        sectors[lsn][:len(payload)] = payload

    for add_arg in args.add:
        path_s, separator, override = add_arg.partition("=")
        path = Path(path_s)
        if not path.is_file():
            sys.exit(f"mkcpcmedia: missing input {path}")
        try:
            base, ext, packed_name = name83(path, override if separator else "")
        except ValueError as exc:
            sys.exit(f"mkcpcmedia: {exc}")
        if packed_name in seen:
            sys.exit(f"mkcpcmedia: duplicate name {base}.{ext}")
        seen.add(packed_name)

        raw = path.read_bytes()
        stream = amsdos_header(raw, base, ext) + raw
        stream += b"\x1A" * (-len(stream) % 128)
        records_total = len(stream) // 128
        position = 0
        extent = 0

        while True:
            records = min(records_total - extent * 128, 128)
            blocks = (records * 128 + BLOCK_SIZE - 1) // BLOCK_SIZE
            allocations = []
            for _ in range(blocks):
                if next_block >= addressable_blocks:
                    sys.exit(f"mkcpcmedia: disk full adding {base}.{ext}")
                block = next_block
                next_block += 1
                allocations.append(block)
                chunk = stream[position:position + BLOCK_SIZE]
                position += BLOCK_SIZE
                put_sector(block * 2, chunk[:SECTOR_SIZE])
                put_sector(block * 2 + 1, chunk[SECTOR_SIZE:])

            entry = bytearray(32)
            entry[0] = 0
            entry[1:12] = packed_name
            entry[12] = extent
            entry[15] = records
            entry[16:16 + len(allocations)] = bytes(allocations)
            directory.append(bytes(entry))
            if extent * 128 + records >= records_total:
                break
            extent += 1

    if len(directory) > 64:
        sys.exit("mkcpcmedia: directory full")
    directory_bytes = b"".join(directory) + b"\xE5" * (2048 - len(directory) * 32)
    for index in range(4):
        put_sector(index, directory_bytes[index * SECTOR_SIZE:(index + 1) * SECTOR_SIZE])

    image = bytearray(256)
    image[0:34] = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
    image[0x22:0x30] = b"mkcpcmedia    "
    image[0x30] = TRACKS
    image[0x31] = SIDES
    for track in range(TRACKS):
        image[0x34 + track] = TRACK_SIZE // 256

    for track in range(TRACKS):
        track_info = bytearray(256)
        track_info[0:12] = b"Track-Info\r\n"
        track_info[0x10] = track
        track_info[0x12] = 0x02             # 250 kbps
        track_info[0x13] = 0x02             # MFM
        track_info[0x14] = 2                # 512-byte sectors
        track_info[0x15] = SECTORS_PER_TRACK
        track_info[0x16] = 0x4E
        track_info[0x17] = 0xE5
        for index, sector_id in enumerate(SECTOR_IDS):
            descriptor = 0x18 + index * 8
            track_info[descriptor] = track
            track_info[descriptor + 2] = sector_id
            track_info[descriptor + 3] = 2
            track_info[descriptor + 6] = SECTOR_SIZE & 0xFF
            track_info[descriptor + 7] = SECTOR_SIZE >> 8
        image += track_info
        base_lsn = track * SECTORS_PER_TRACK
        for index in range(SECTORS_PER_TRACK):
            image += sectors[base_lsn + index]

    Path(args.out).write_bytes(image)
    highest_track = ((next_block * 2 - 1) // SECTORS_PER_TRACK)
    print(
        f"{args.out}: {len(seen)} files, {len(directory)} extents, "
        f"{next_block - DIR_BLOCKS} blocks, highest track {highest_track}, "
        f"{len(image)} bytes"
    )


if __name__ == "__main__":
    main()
