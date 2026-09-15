#!/usr/bin/env python3
"""Create disposable Screen 6/7 images for universal FormRef qualification."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from embed_app_icon import parse_manifest


ROOT = Path(__file__).resolve().parents[1]


def put(image: Path, source: Path, target: str) -> None:
    subprocess.run(["mcopy", "-o", "-i", str(image) + "@@16384",
                    str(source), "::/" + target], check=True)


def prepare(output: Path) -> None:
    source = ROOT / "QA/MSX/GBMSX.IMG"
    card = ROOT / "QA/MSX/CARD"
    app = ROOT / "build/universal/FORMREF.APP"
    resource = ROOT / "build/universal/FORMREF.GBR"
    for path in (source, card / "GEOBENCH.CFG",
                 card / "GBENCH/FILEMGR.APP", app, resource):
        if not path.exists():
            raise ValueError("missing prerequisite: " + str(path))
    package = parse_manifest(app.read_bytes())
    if (package["version"], package["application_id"],
            len(package["segments"])) != (4, "FORMREF", 1):
        raise ValueError("expected the compile-once primary-only FormRef")
    if hashlib.sha256(resource.read_bytes()).hexdigest() != \
            "a5f473f4665e5f119bf809819e8e191d509f41bda3cd0111320e54f3750bdfc8":
        raise ValueError("FORMREF.GBR differs from the frozen fixture")
    if output.exists():
        raise ValueError("preserve existing evidence; choose a fresh output directory")

    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    output.mkdir(parents=True)
    files = {}
    for mode in (6, 7):
        stage = output / f"mode{mode}"
        stage.mkdir()
        image = stage / "filesystem.img"
        shutil.copyfile(source, image)
        config = re.sub(rb"MSXMODE=\d", f"MSXMODE={mode}".encode(),
                        (card / "GEOBENCH.CFG").read_bytes())
        (stage / "GEOBENCH.CFG").write_bytes(config)
        (stage / "AUTOEXEC.BAT").write_bytes(b"GBMSX\r\n")
        put(image, stage / "GEOBENCH.CFG", "GEOBENCH.CFG")
        put(image, stage / "AUTOEXEC.BAT", "AUTOEXEC.BAT")
        # The short root alias makes the icon position deterministic. Its bytes
        # are the exact candidate package; no test-only executable is involved.
        put(image, app, "A.APP")
        actual = subprocess.check_output(
            ["mtype", "-i", str(image) + "@@16384", "::/A.APP"])
        if actual != app.read_bytes():
            raise AssertionError("staged FormRef APP differs")
        files[f"mode{mode}"] = {
            "image": str(image),
            "image_sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
        }
    if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
        raise AssertionError("normal MSX image changed")
    (output / "manifest.json").write_text(json.dumps({
        "profile": "msx-formref-private-v1",
        "source_image": str(source),
        "source_image_sha256": source_hash,
        "source_unchanged": True,
        "app_sha256": hashlib.sha256(app.read_bytes()).hexdigest(),
        "resource_sha256": hashlib.sha256(resource.read_bytes()).hexdigest(),
        "files": files,
    }, indent=2) + "\n")
    print("PASS private Screen 6/7 FormRef fixtures: " + str(output))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.output.resolve())
