#!/usr/bin/env python3
"""Verify the committed MSX2 distribution against canonical visual assets."""

import sys
from pathlib import Path

from picture_catalog import picture_mode


ROOT = Path(__file__).resolve().parents[1]
CARD = ROOT / "QA/MSX/CARD"
SYSTEM = CARD / "GBENCH"
PICTURES = CARD / "PICS"


def compare_payload(label: str, actual: bytes, expected: bytes) -> None:
    if actual != expected:
        raise ValueError(f"{label}: payload differs from canonical asset")


def catalog(directory: Path, suffix: str) -> dict[str, bytes]:
    return {
        path.name.upper(): path.read_bytes()
        for path in sorted(directory.glob(f"*{suffix}"))
    }


def main() -> None:
    try:
        source_pictures = sorted((ROOT / "assets/pictures").glob("*.PIC"))
        if not source_pictures:
            raise ValueError("assets/pictures: no pictures found")
        for path in source_pictures:
            picture_mode(path)
        pictures = {path.name.upper(): path.read_bytes() for path in source_pictures}
        logo = ROOT / "assets/msx/GEMLOGO.PIC"
        if not logo.is_file():
            raise ValueError("assets/msx/GEMLOGO.PIC: missing GEMBENCH wallpaper")
        pictures["LOGO.PIC"] = logo.read_bytes()

        backdrops = catalog(ROOT / "assets/backdrops", ".BDP")
        titlebars = catalog(ROOT / "assets/titlebars", ".TBR")
        gadgets = catalog(ROOT / "assets/gadgets", ".GDT")
        if not backdrops or not titlebars or not gadgets:
            raise ValueError("visual asset catalog is incomplete")
        for name, payload in backdrops.items():
            if len(payload) != 64:
                raise ValueError(f"assets/backdrops/{name}: expected 64 bytes")
        for name, payload in titlebars.items():
            if len(payload) not in (56, 106):
                raise ValueError(f"assets/titlebars/{name}: expected 56 or 106 bytes")
        for name, payload in gadgets.items():
            if len(payload) != 50:
                raise ValueError(f"assets/gadgets/{name}: expected 50 bytes")

        for label, directory, expected, suffix in (
            ("QA/MSX/CARD/PICS", PICTURES, pictures, ".PIC"),
            ("QA/MSX/CARD/GBENCH", SYSTEM, backdrops, ".BDP"),
            ("QA/MSX/CARD/GBENCH", SYSTEM, titlebars, ".TBR"),
            ("QA/MSX/CARD/GBENCH", SYSTEM, gadgets, ".GDT"),
        ):
            actual = catalog(directory, suffix)
            if set(actual) != set(expected):
                missing = sorted(set(expected) - set(actual))
                extra = sorted(set(actual) - set(expected))
                raise ValueError(f"{label} {suffix}: missing={missing}, extra={extra}")
            for name, payload in expected.items():
                compare_payload(f"{label}/{name}", actual[name], payload)

        compare_payload(
            "QA/MSX/CARD/GBENCH/GBTITLE.MOD",
            (SYSTEM / "GBTITLE.MOD").read_bytes(),
            (ROOT / "build/msx/GBTITLE.RAW").read_bytes(),
        )
        compare_payload(
            "QA/MSX/CARD/GBENCH/DEFAULT.CFG",
            (SYSTEM / "DEFAULT.CFG").read_bytes(),
            (CARD / "GEOBENCH.CFG").read_bytes(),
        )
        config = (CARD / "GEOBENCH.CFG").read_bytes()
        for setting in (b"TITLEBAR=ORIGINAL\r\n", b"GADGETS=ORIGINAL\r\n"):
            if setting not in config:
                raise ValueError(f"QA/MSX/CARD/GEOBENCH.CFG: missing {setting!r}")
        required_saver_modules = {"XMATRIX.MOD", "MOUNTAIN.MOD", "STARFLD.MOD"}
        names = {path.name for path in SYSTEM.iterdir()}
        if not required_saver_modules <= names:
            raise ValueError("QA/MSX/CARD/GBENCH: missing saver configuration module")
        if any(SYSTEM.glob("*.PIC")):
            raise ValueError("QA/MSX/CARD/GBENCH: pictures must live under PICS")
    except (OSError, ValueError) as error:
        sys.exit(str(error))

    print(f"MSX2 pictures: {len(pictures)} staged (GEMBENCH LOGO override active)")
    print(
        f"MSX2 visual catalogs: {len(backdrops)} backdrops, "
        f"{len(titlebars)} title bars, {len(gadgets)} gadget themes"
    )
    print("MSX2 defaults: staged GBTITLE and pristine configuration match generated sources")


if __name__ == "__main__":
    main()
