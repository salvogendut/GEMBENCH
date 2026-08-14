#!/usr/bin/env python3
"""Validate the committed two-disk MSX2 distribution."""

from __future__ import annotations

import hashlib
import shutil
import struct
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "QA/MSX/Floppies/GEOBENCH.DSK"
EXTRAS = ROOT / "QA/MSX/Floppies/EXTRAS.DSK"
BOOT = ROOT / "assets/msx/MSXDOS2.BIN"
NEXTOR_LICENSE = ROOT / "docs/licenses/NEXTOR.md"
UNAPI_LICENSE = ROOT / "docs/licenses/OPENMSXNET.md"
UNAPINET_SHA256 = (
    "86e7bb27d1f020e235929a6806f5f2dc"
    "8188c458119041c4017afd93a3c13227"
)


def fail(message: str) -> None:
    raise SystemExit(message)


def run_mtools(arguments: list[str]) -> bytes:
    try:
        result = subprocess.run(
            arguments,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        fail(f"missing {arguments[0]}; install mtools")
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", "replace").strip()
        fail(f"{' '.join(arguments)} failed: {detail}")
    return result.stdout


def listing(image: Path) -> set[str]:
    output = run_mtools(["mdir", "-b", "-s", "-i", str(image), "::"])
    return {
        line.removeprefix("::/").rstrip("/").upper()
        for line in output.decode("utf-8", "replace").splitlines()
        if line.startswith("::/")
    }


def payload(image: Path, path: str) -> bytes:
    return run_mtools(["mtype", "-i", str(image), f"::{path}"])


def validate_geometry(image: Path, label: bytes) -> None:
    data = image.read_bytes()
    if len(data) != 720 * 1024:
        fail(f"{image.relative_to(ROOT)}: expected a 720K image")
    boot = BOOT.read_bytes()
    if data[:11] != boot[:11] or data[30:512] != boot[30:512]:
        fail(f"{image.relative_to(ROOT)}: MSX-DOS 2 boot sector differs")

    values = struct.unpack_from("<HBHBHHBHH", data, 11)
    expected = (512, 2, 1, 2, 112, 1440, 0xF9, 3, 9)
    if values != expected:
        fail(f"{image.relative_to(ROOT)}: unexpected FAT12 geometry {values}")
    root_offset = (1 + 2 * 3) * 512
    labels = {
        data[offset:offset + 11].rstrip()
        for offset in range(root_offset, root_offset + 112 * 32, 32)
        if data[offset + 11] == 0x08
    }
    if labels != {label}:
        fail(f"{image.relative_to(ROOT)}: unexpected volume label")


def staged_files(directory: Path) -> set[str]:
    return {
        str(path.relative_to(directory)).replace("\\", "/").upper()
        for path in directory.rglob("*")
        if path.is_file()
    }


def main() -> None:
    for command in ("mdir", "mtype"):
        if not shutil.which(command):
            fail(f"missing {command}; install mtools")
    for path in (MAIN, EXTRAS, BOOT, NEXTOR_LICENSE, UNAPI_LICENSE):
        if not path.is_file():
            fail(f"missing {path.relative_to(ROOT)}")

    validate_geometry(MAIN, b"GBMSX")
    validate_geometry(EXTRAS, b"GBEXTRAS")
    main_files = listing(MAIN)
    extras_files = listing(EXTRAS)

    required_root = {
        "NEXTOR.SYS",
        "COMMAND2.COM",
        "NEXTOR.TXT",
        "UNAPINET.COM",
        "UNAPI.TXT",
        "AUTOEXEC.BAT",
        "GBMSX.COM",
        "GBMSX6.COM",
        "GBMSX7.COM",
        "GEOBENCH.CFG",
        "WELCOME.TXT",
        "GBENCH",
        "DIAG",
    }
    missing = required_root - main_files
    if missing:
        fail(f"{MAIN.relative_to(ROOT)}: missing {', '.join(sorted(missing))}")
    forbidden = {"MSXDOS.SYS", "MSXDOS2.SYS"} & main_files
    if forbidden:
        fail(
            f"{MAIN.relative_to(ROOT)}: proprietary DOS files must not be "
            f"distributed: {', '.join(sorted(forbidden))}"
        )

    for directory in ("GBENCH", "DIAG"):
        expected = {
            f"{directory}/{name}"
            for name in staged_files(ROOT / f"QA/MSX/{directory}")
        }
        actual = {
            name for name in main_files if name.startswith(f"{directory}/")
        }
        if actual != expected:
            fail(f"{MAIN.relative_to(ROOT)}: {directory} file set is stale")

    if payload(MAIN, "/NEXTOR.TXT") != NEXTOR_LICENSE.read_bytes():
        fail(f"{MAIN.relative_to(ROOT)}: Nextor notice differs from source")
    if payload(MAIN, "/UNAPI.TXT") != UNAPI_LICENSE.read_bytes():
        fail(f"{MAIN.relative_to(ROOT)}: openMSXnet notice differs from source")
    if payload(MAIN, "/AUTOEXEC.BAT") != b"UNAPINET\r\nGBMSX\r\n":
        fail(f"{MAIN.relative_to(ROOT)}: AUTOEXEC must start UNAPINET before GBMSX")
    unapinet = payload(MAIN, "/UNAPINET.COM")
    if hashlib.sha256(unapinet).hexdigest() != UNAPINET_SHA256:
        fail(f"{MAIN.relative_to(ROOT)}: unexpected UNAPINET.COM release")
    for name in ("NEXTOR.SYS", "COMMAND2.COM"):
        dependency = ROOT / f"QA/MSXDEPS/{name}"
        if dependency.is_file() and payload(MAIN, f"/{name}") != dependency.read_bytes():
            fail(f"{MAIN.relative_to(ROOT)}: {name} differs from fetched dependency")
    dependency = ROOT / "QA/MSXDEPS/UNAPINET.COM"
    if dependency.is_file() and unapinet != dependency.read_bytes():
        fail(f"{MAIN.relative_to(ROOT)}: UNAPINET.COM differs from fetched dependency")

    pictures = {
        path.name.upper(): path.read_bytes()
        for path in sorted((ROOT / "assets/pictures").glob("*.PIC"))
    }
    actual_pictures = {
        name.removeprefix("PICS/")
        for name in extras_files
        if name.startswith("PICS/")
    }
    if actual_pictures != set(pictures):
        fail(f"{EXTRAS.relative_to(ROOT)}: picture catalogue is stale")
    expected_extras = {"PICS"} | {f"PICS/{name}" for name in pictures}
    unexpected = extras_files - expected_extras
    if unexpected:
        fail(
            f"{EXTRAS.relative_to(ROOT)}: unexpected files: "
            f"{', '.join(sorted(unexpected))}"
        )
    for name, expected in pictures.items():
        if payload(EXTRAS, f"/PICS/{name}") != expected:
            fail(f"{EXTRAS.relative_to(ROOT)}: PICS/{name} differs from asset")

    print("MSX floppy distribution: OK")


if __name__ == "__main__":
    main()
