#!/usr/bin/env python3
"""Audit the Gate-3 CPC media and compile-once application bytes."""

from hashlib import sha256
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UNIVERSAL = ROOT / "build" / "universal"
CPC_CARD = ROOT / "QA" / "CPC" / "CARD"
CPC_SYS = CPC_CARD / "GBENCH"
MSX_SYS = ROOT / "QA" / "MSX" / "CARD" / "GBENCH"
CPC_DSK = ROOT / "QA" / "CPC" / "Floppies" / "GEOBENCH.DSK"


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def check_amsdos(binary: Path, raw: Path, load: int) -> None:
    packed = binary.read_bytes()
    payload = raw.read_bytes()
    if len(packed) != len(payload) + 128 or packed[128:] != payload:
        raise SystemExit(f"{binary.name}: AMSDOS payload differs from {raw.name}")
    header = packed[:128]
    if int.from_bytes(header[21:23], "little") != load:
        raise SystemExit(f"{binary.name}: wrong AMSDOS load address")
    if int.from_bytes(header[26:28], "little") != load:
        raise SystemExit(f"{binary.name}: wrong AMSDOS entry address")
    if int.from_bytes(header[24:26], "little") != len(payload):
        raise SystemExit(f"{binary.name}: wrong AMSDOS logical length")
    if int.from_bytes(header[67:69], "little") != sum(header[:67]) & 0xFFFF:
        raise SystemExit(f"{binary.name}: bad AMSDOS header checksum")


def cpc_disk_stream(path: Path) -> bytes:
    """Return sectors in logical DATA-disk order, omitting EDSK track headers."""
    image = path.read_bytes()
    if not image.startswith(b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"):
        raise SystemExit(f"{path}: not an extended CPC DSK")
    sectors: list[bytes] = []
    offset = 256
    while offset < len(image):
        track = image[offset:offset + 256]
        if len(track) != 256 or not track.startswith(b"Track-Info\r\n"):
            raise SystemExit(f"{path}: malformed track at {offset:#x}")
        cursor = offset + 256
        for index in range(track[0x15]):
            descriptor = track[0x18 + index * 8:0x20 + index * 8]
            size = int.from_bytes(descriptor[6:8], "little")
            if not size:
                size = 128 << descriptor[3]
            sectors.append(image[cursor:cursor + size])
            cursor += size
        offset = cursor
    if offset != len(image):
        raise SystemExit(f"{path}: trailing or truncated track data")
    return b"".join(sectors)


def cpc_disk_files(path: Path) -> dict[str, bytes]:
    stream = cpc_disk_stream(path)
    extents: dict[str, list[tuple[int, bytes]]] = {}
    for offset in range(0, 2048, 32):
        entry = stream[offset:offset + 32]
        if entry[0] == 0xE5:
            continue
        name = entry[1:9].decode("ascii").rstrip()
        ext = entry[9:12].decode("ascii").rstrip()
        records = entry[15]
        blocks = [block for block in entry[16:32] if block]
        data = b"".join(stream[block * 1024:(block + 1) * 1024] for block in blocks)
        extents.setdefault(f"{name}.{ext}", []).append((entry[12], data[:records * 128]))
    files: dict[str, bytes] = {}
    for name, parts in extents.items():
        files[name] = b"".join(data for _, data in sorted(parts))
    return files


required = {
    "M4DETECT.BIN": (ROOT / "build" / "M4DETECT.RAW", 0x4000),
    "GBALB.BIN": (ROOT / "build" / "cpc" / "GBALB.RAW", 0x8000),
    "GBM4.BIN": (ROOT / "build" / "cpc" / "GBM4.RAW", 0x8000),
}
for name, (raw, load) in required.items():
    check_amsdos(CPC_CARD / name, raw, load)

loader = (CPC_CARD / "GB.BAS").read_bytes()
for command in (b'LOAD"M4DETECT",&4000', b'RUN"GBM4', b'RUN"GBALB'):
    if command not in loader:
        raise SystemExit(f"GB.BAS does not select both CPC card backends: {command!r}")

gate = CPC_SYS / "GBAPV4.MOD"
if gate.read_bytes() != (ROOT / "build" / "cpc" / "GBAPV4.RAW").read_bytes():
    raise SystemExit("CPC stage changed the GBAP v4 gate bytes")
if gate.stat().st_size != 1201 or gate.read_bytes()[3:5] != b"GB":
    raise SystemExit("CPC GBAP v4 gate has the wrong size or signature")
if (CPC_SYS / "GBDRAG.MOD").read_bytes() != (ROOT / "build" / "cpc" / "GBDRAG.RAW").read_bytes():
    raise SystemExit("CPC stage changed the managed-window drag module bytes")
if (CPC_SYS / "M4SAVE.MOD").read_bytes() != (ROOT / "build" / "M4SAVE.RAW").read_bytes():
    raise SystemExit("CPC stage changed the M4 save module bytes")
ui_module = (ROOT / "build" / "GBUI.RAW").read_bytes()
if (CPC_SYS / "GBUI.MOD").read_bytes() != ui_module:
    raise SystemExit("CPC card does not stage the shared GBUI module")

disk_files = cpc_disk_files(CPC_DSK)
floppy_ui = disk_files.get("GBUI.MOD")
if floppy_ui is None or floppy_ui[128:128 + len(ui_module)] != ui_module:
    raise SystemExit("CPC floppy does not stage the shared GBUI module")
refined = (ROOT / "assets" / "iconsets" / "REFINED.IST").read_bytes()
if (CPC_SYS / "REFINED.IST").read_bytes() != refined:
    raise SystemExit("CPC card does not stage the canonical REFINED.IST")
floppy_refined = disk_files.get("REFINED.IST")
if floppy_refined is None or floppy_refined[128:128 + len(refined)] != refined:
    raise SystemExit("CPC floppy does not stage the canonical REFINED.IST")
if b"ICONS=REFINED\r\n" not in (CPC_CARD / "GEOBENCH.CFG").read_bytes():
    raise SystemExit("CPC card does not select REFINED.IST")
floppy_config = disk_files.get("GEOBENCH.CFG")
if floppy_config is None or b"ICONS=REFINED\r\n" not in floppy_config[128:]:
    raise SystemExit("CPC floppy does not select REFINED.IST")

for name in ("ABIPROBE.APP", "CLOCK.APP", "CALC.APP"):
    source = UNIVERSAL / name
    staged = CPC_SYS / name
    if not source.is_file() or not staged.is_file():
        raise SystemExit(f"missing universal CPC artifact: {name}")
    if source.read_bytes() != staged.read_bytes():
        raise SystemExit(f"CPC stage changed universal bytes: {name}")
    if source.read_bytes() != MSX_SYS.joinpath(name).read_bytes():
        raise SystemExit(f"MSX2/CPC universal media differ: {name}")
    floppy = disk_files.get(name)
    if floppy is None or floppy[128:128 + source.stat().st_size] != source.read_bytes():
        raise SystemExit(f"CPC floppy changed universal bytes: {name}")
    print(f"{name}: {digest(source)} (byte-identical MSX2/CPC card and CPC floppy)")
