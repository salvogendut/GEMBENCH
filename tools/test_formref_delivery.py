#!/usr/bin/env python3
"""Verify the same two-bank FormRef in canonical MSX and CPC media."""
from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess

from cpc_desktop_media import validate
from embed_app_icon import parse_manifest


ROOT = Path(__file__).resolve().parents[1]
APP_SHA256 = "9960e96cf4efdb60003d73cbb70b04cd155ae2bf998ad7de4783716222c679ce"
RESOURCE_SHA256 = "a5f473f4665e5f119bf809819e8e191d509f41bda3cd0111320e54f3750bdfc8"
SECONDARY_SHA256 = "4814e49ce5b1521148d9f28bf36b6174d75d0125f28b351afd93dd0daa6d63c0"


def image_file(image: Path, name: str, *, partitioned: bool = True) -> bytes:
    return subprocess.check_output([
        "mtype", "-i", str(image) + ("@@16384" if partitioned else ""),
        "::/" + name,
    ])


def main() -> None:
    app = (ROOT / "build/universal/FORMREF.APP").read_bytes()
    package = parse_manifest(app)
    assert hashlib.sha256(app).hexdigest() == APP_SHA256
    assert (package["version"], package["profile"],
            package["application_id"], package["minimum_pages"],
            len(package["segments"])) == (4, 3, "FORMREF", 2, 2)
    secondary = package["segments"][1]
    secondary_bytes = app[secondary["offset"]:
                          secondary["offset"] + secondary["stored_length"]]
    assert hashlib.sha256(secondary_bytes).hexdigest() == SECONDARY_SHA256

    paths = (
        ROOT / "QA/MSX/CARD/GBENCH/FORMREF.APP",
        ROOT / "QA/CPC-Desktop/CARD/GBENCH/FORMREF.APP",
    )
    assert all(path.read_bytes() == app for path in paths)
    for image, partitioned in (
            (ROOT / "QA/MSX/GBMSX.IMG", True),
            (ROOT / "QA/MSX/Floppies/GEOBENCH.DSK", False),
            (ROOT / "QA/CPC-Desktop/GEOBENCH.IMG", True)):
        assert image_file(image, "GBENCH/FORMREF.APP",
                          partitioned=partitioned) == app

    manifest = validate(ROOT / "QA/CPC-Desktop", pristine=True)
    assert manifest["profile"] == "cpc-desktop-m4-v6"
    section = manifest["sections"]["formref"]
    assert section["app_sha256"] == APP_SHA256
    assert section["resource_sha256"] == RESOURCE_SHA256
    assert section["secondary_sha256"] == SECONDARY_SHA256
    print("PASS universal two-bank FormRef in canonical MSX HD/floppy and CPC M4 media")


if __name__ == "__main__":
    main()
