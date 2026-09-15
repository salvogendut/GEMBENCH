#!/usr/bin/env python3
"""Verify universal GBRDEMO identity in both canonical distribution images."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess

from cpc_desktop_media import validate
from embed_app_icon import parse_manifest


ROOT = Path(__file__).resolve().parents[1]
APP_SHA256 = "4ec6f034ed396c51fcf5d573c548acfd7df53f077e9f14a718a7cd8cc762b4ff"
RESOURCE_SHA256 = "49b42e9268ad4f4208d70f591f9d3f6b6ad7bee2dcf6f008a773ece968febf12"


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def image_file(image: Path, name: str, *, partitioned: bool = True) -> bytes:
    return subprocess.check_output(
        ["mtype", "-i", str(image) + ("@@16384" if partitioned else ""),
         "::/" + name]
    )


def main() -> None:
    app = (ROOT / "build/universal/GBRDEMO.APP").read_bytes()
    resource = (ROOT / "QA/MSX/CARD/HELLO.GBR").read_bytes()
    package = parse_manifest(app)
    assert digest(app) == APP_SHA256
    assert digest(resource) == RESOURCE_SHA256
    assert (package["version"], package["profile"],
            package["application_id"], package["minimum_pages"],
            len(package["segments"])) == (4, 3, "GBRDEMO", 1, 1)

    paths = (
        ROOT / "QA/MSX/CARD/GBENCH/GBRDEMO.APP",
        ROOT / "QA/CPC-Desktop/CARD/GBENCH/GBRDEMO.APP",
    )
    resources = (
        ROOT / "QA/MSX/CARD/HELLO.GBR",
        ROOT / "QA/CPC-Desktop/CARD/HELLO.GBR",
    )
    assert all(path.read_bytes() == app for path in paths)
    assert all(path.read_bytes() == resource for path in resources)

    for image, partitioned in (
            (ROOT / "QA/MSX/GBMSX.IMG", True),
            (ROOT / "QA/MSX/Floppies/GEOBENCH.DSK", False),
            (ROOT / "QA/CPC-Desktop/GEOBENCH.IMG", True)):
        assert image_file(image, "GBENCH/GBRDEMO.APP",
                          partitioned=partitioned) == app
        assert image_file(image, "HELLO.GBR", partitioned=partitioned) == resource

    manifest = validate(ROOT / "QA/CPC-Desktop", pristine=True)
    assert manifest["profile"] in ("cpc-desktop-m4-v5", "cpc-desktop-m4-v6")
    section = manifest["sections"]["gbrdemo"]
    assert section["app_sha256"] == APP_SHA256
    assert section["resource_sha256"] == RESOURCE_SHA256
    print("PASS universal GBRDEMO and HELLO.GBR in canonical MSX HD/floppy and CPC M4 media")


if __name__ == "__main__":
    main()
