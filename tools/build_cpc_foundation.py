#!/usr/bin/env python3
"""Build isolated step-3A/3B/3C CPC/M4 diagnostics, never release media.

AMSDOS header fields and FAT16/sector-32 layout follow the archived CPC
tools/amsdos_header.py and tools/build_card_img.sh (56478578).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from cpc_graphics_fixture import GRAPHICS_VARIANTS, emit_vectors
from cpc_storage_fixture import STORAGE_VARIANTS, FILES, emit_vectors as emit_storage

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = {"normal": None, "bad-bank": "FAULT_RESTORE",
            "bad-register": "FAULT_REGISTER", "bad-stack": "FAULT_STACK",
            **GRAPHICS_VARIANTS, **STORAGE_VARIANTS}


def headed(raw: bytes, load: int) -> bytes:
    if not raw or not 0 <= load < load + len(raw) <= 0x10000:
        raise ValueError("binary must fit in the Z80 address space")
    header = bytearray(128)
    header[1:12] = b"FOUND   BIN"
    header[18] = 2
    for offset, value in ((21, load), (24, len(raw)), (26, load)):
        header[offset:offset + 2] = value.to_bytes(2, "little")
    header[64:67] = len(raw).to_bytes(3, "little")
    header[67:69] = sum(header[:67]).to_bytes(2, "little")
    return bytes(header) + raw


def build(variant: str) -> Path:
    assembler = os.environ.get("RASM", "rasm")
    for tool in (assembler, "sfdisk", "mkfs.fat", "mcopy"):
        if not shutil.which(tool):
            raise SystemExit(f"missing {tool}; use distrobox my-distrobox")
    work = ROOT / "build/cpc-foundation" / variant
    media = ROOT / "QA/Diagnostics/CPC-foundation" / variant
    card = media / "CARD"
    work.mkdir(parents=True, exist_ok=True)
    card.mkdir(parents=True, exist_ok=True)
    source = "probe.asm"
    if variant in GRAPHICS_VARIANTS:
        emit_vectors(work / "graphics_vectors.inc")
        source = "graphics_probe.asm"
    if variant in STORAGE_VARIANTS:
        emit_storage(work / "storage_vectors.inc", variant)
        source = "storage_probe.asm"
    command = [assembler, str(ROOT / "debug/cpc_foundation" / source),
               "-s", "-sq", "-o", "foundation", f"-I{work}"]
    if VARIANTS[variant]:
        command.append(f"-D{VARIANTS[variant]}=1")
    subprocess.run(command, cwd=work, check=True)
    raw = (work / "FOUND.RAW").read_bytes()
    (card / "FOUND.BIN").write_bytes(headed(raw, 0x8000))
    boot = (ROOT / "debug/cpc_foundation/BOOT.BAS").read_text()
    (card / "BOOT.BAS").write_bytes(boot.replace("\n", "\r\n").encode("ascii"))
    inputs = []
    if variant in STORAGE_VARIANTS:
        for name, data in FILES.items():
            (card / name).write_bytes(data)
            inputs.append(str(card / name))
    # Build a fresh image and replace only this diagnostic's own output.
    # Never copy arbitrary files left over in the staging directory.
    image = media / "FOUNDATION.IMG"
    fd, temporary = tempfile.mkstemp(prefix="foundation-", suffix=".img", dir=media)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.truncate(32 * 1024 * 1024)
        subprocess.run(["sfdisk", "-q", temporary],
                       input="label: dos\nlabel-id: 0x43504333\nstart=32, type=06\n",
                       text=True, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["mkfs.fat", "--invariant", "-F16", "--offset", "32",
                        "-n", "CPCPROBE", temporary], check=True)
        subprocess.run(["mcopy", "-i", temporary + "@@16384",
                        str(card / "BOOT.BAS"), str(card / "FOUND.BIN"), *inputs, "::/"],
                       env={**os.environ, "MTOOLS_SKIP_CHECK": "1"}, check=True)
        Path(temporary).replace(image)
    finally:
        Path(temporary).unlink(missing_ok=True)
    config = media / "1984.conf"
    config.write_text(
        "[machine]\nmodel=6128\nmemory=512\n\n[hardware]\n"
        f"mx4=true\nm4=true\nm4_path=\nm4_image={image}\n"
        "albireo=false\nsymbiface_ide=false\n\n[advanced]\ndebug=true\n")
    manifest = {
        "variant": variant,
        "source_revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in [*sorted((ROOT / "debug/cpc_foundation").iterdir()),
                         ROOT / "tools/cpc_graphics_fixture.py",
                         ROOT / "tools/cpc_storage_fixture.py"] if path.is_file()
        },
        "raw_bytes": len(raw), "raw_sha256": hashlib.sha256(raw).hexdigest(),
        "image_sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
        "image": str(image), "config": str(config),
        "symbols": str(work / "foundation.sym"),
    }
    (media / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {image.relative_to(ROOT)} ({variant}, M4 only)", flush=True)
    return media


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=VARIANTS, default="normal")
    build(parser.parse_args().variant)
