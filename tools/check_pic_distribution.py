#!/usr/bin/env python3
"""Verify that every shipped platform carries the same canonical .PIC bytes."""

import sys
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def edsk_tracks(path: Path):
    image = path.read_bytes()
    if not image.startswith(b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"):
        raise ValueError(f"{path}: not an extended DSK image")
    tracks = image[0x30]
    sides = image[0x31]
    pos = 256
    out = []
    for index in range(tracks * sides):
        size = image[0x34 + index] * 256
        if not size:                         # valid unformatted slot in an extended DSK
            continue
        track = image[pos:pos + size]
        if len(track) != size or size < 256:
            raise ValueError(f"{path}: malformed track {index}")
        sectors = {}
        data_pos = 256
        for sector_index in range(track[0x15]):
            desc = 0x18 + sector_index * 8
            sector_id = track[desc + 2]
            sector_size = track[desc + 6] | (track[desc + 7] << 8)
            if not sector_size:
                sector_size = 128 << track[desc + 3]
            sectors[sector_id] = track[data_pos:data_pos + sector_size]
            data_pos += sector_size
        out.append((track[0x10], track[0x11], sectors))
        pos += size
    return out


def logical_sectors(path: Path, first_sector: int):
    sectors = []
    for _track, _side, by_id in edsk_tracks(path):
        for sector_id in range(first_sector, first_sector + 9):
            if sector_id in by_id:
                sectors.append(by_id[sector_id])
    return sectors


def cpm_files(sectors, offset_tracks: int, block_size: int, directory_blocks: int):
    sectors_per_block = block_size // 512
    data = sectors[offset_tracks * 9:]
    directory_size = directory_blocks * block_size
    directory = b"".join(data[:directory_size // 512])
    entries = defaultdict(list)
    for pos in range(0, directory_size, 32):
        entry = directory[pos:pos + 32]
        if len(entry) < 32 or entry[0] in (0xE5,):
            continue
        base = bytes(value & 0x7F for value in entry[1:9]).decode("ascii").rstrip()
        ext = bytes(value & 0x7F for value in entry[9:12]).decode("ascii").rstrip()
        name = base + (("." + ext) if ext else "")
        extent = entry[12] + (entry[14] << 5)
        entries[name].append((extent, entry))

    files = {}
    for name, extents in entries.items():
        payload = bytearray()
        for _extent, entry in sorted(extents):
            records = entry[15]
            block_count = (records * 128 + block_size - 1) // block_size
            blocks = []
            for index in range(block_count):
                if block_size == 2048:
                    block = entry[16 + index * 2] | (entry[17 + index * 2] << 8)
                else:
                    block = entry[16 + index]
                first = block * sectors_per_block
                blocks.append(b"".join(data[first:first + sectors_per_block]))
            payload.extend(b"".join(blocks)[:records * 128])
        files[name] = bytes(payload)
    return files


def strip_amsdos(data: bytes) -> bytes:
    if len(data) < 128:
        return data
    checksum = data[67] | (data[68] << 8)
    if (sum(data[:67]) & 0xFFFF) != checksum:
        return data
    length = data[24] | (data[25] << 8)
    return data[128:128 + length]


def cpc_disk(path: Path):
    return cpm_files(logical_sectors(path, 0xC1), 0, 1024, 2)


def pcw_disk(path: Path):
    sectors = logical_sectors(path, 1)
    spec = sectors[0]
    block_size = 128 << spec[6]
    return cpm_files(sectors, spec[5], block_size, spec[7])


def compare_payload(label: str, actual: bytes, expected: bytes, padded: bool = False):
    if padded:
        if actual[:len(expected)] != expected or any(byte != 0x1A for byte in actual[len(expected):]):
            raise ValueError(f"{label}: payload differs from canonical asset")
    elif actual != expected:
        raise ValueError(f"{label}: payload differs from canonical asset")


def main() -> None:
    assets = {path.name: path.read_bytes() for path in sorted((ROOT / "assets/pictures").glob("*.PIC"))}
    if not assets:
        sys.exit("no canonical pictures found")
    for name, data in assets.items():
        if data[:6] != b"GBPC\x02\x01":
            sys.exit(f"assets/pictures/{name}: expected canonical GBPC v2 mode 1")

    for distro in (ROOT / "QA/CARD/PICS", ROOT / "QA/MSX/PICS"):
        names = {path.name for path in distro.glob("*.PIC")}
        if names != set(assets):
            sys.exit(f"{distro.relative_to(ROOT)}: picture set differs from assets/pictures")
        for name, expected in assets.items():
            compare_payload(str((distro / name).relative_to(ROOT)), (distro / name).read_bytes(), expected)

    cpc_media = cpc_disk(ROOT / "QA/MEDIA.DSK")
    pcw_media = pcw_disk(ROOT / "QA/PCW/MEDIA.DSK")
    if {name for name in cpc_media if name.endswith(".PIC")} != set(assets):
        sys.exit("QA/MEDIA.DSK: picture catalogue differs from assets/pictures")
    if {name for name in pcw_media if name.endswith(".PIC")} != set(assets):
        sys.exit("QA/PCW/MEDIA.DSK: picture catalogue differs from assets/pictures")
    for name, expected in assets.items():
        compare_payload(f"QA/MEDIA.DSK:{name}", strip_amsdos(cpc_media[name]), expected)
        compare_payload(f"QA/PCW/MEDIA.DSK:{name}", pcw_media[name], expected, padded=True)

    cpc_main = cpc_disk(ROOT / "QA/GEOBENCH.DSK")
    pcw_main = pcw_disk(ROOT / "QA/PCW/GEOBENCH.DSK")
    compare_payload("QA/GEOBENCH.DSK:LOGO.PIC", strip_amsdos(cpc_main["LOGO.PIC"]), assets["LOGO.PIC"])
    compare_payload("QA/PCW/GEOBENCH.DSK:LOGO.PIC", pcw_main["LOGO.PIC"], assets["LOGO.PIC"], padded=True)

    for path, files in (
        ("QA/COMPANION.DSK", cpc_disk(ROOT / "QA/COMPANION.DSK")),
        ("QA/PCW/COMPANION.DSK", pcw_disk(ROOT / "QA/PCW/COMPANION.DSK")),
    ):
        if any(name.endswith(".PIC") for name in files):
            sys.exit(f"{path}: companion disk must not contain pictures")

    for directory in (ROOT / "QA/CARD/GBENCH", ROOT / "QA/MSX/GBENCH"):
        if any(directory.glob("*.PIC")):
            sys.exit(f"{directory.relative_to(ROOT)}: pictures must live under PICS")

    print(f"portable PIC distribution: {len(assets)} byte-identical pictures across CPC, MSX and PCW")


if __name__ == "__main__":
    main()
