#!/usr/bin/env python3
"""Stage a fresh, disposable MSX stability image and artifact inventory.

Requires a completed isolated distribution build. Never overwrites a directory,
changes the accepted CARD, or recompiles applications differently per mode.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def inventory(card):
    records = []
    for path in sorted((card/"GBENCH").iterdir()):
        if path.suffix not in (".APP", ".SAV", ".MOD", ".BIN"):
            continue
        data = path.read_bytes()
        package = data[7] if len(data) >= 16 and data[3:7] == b"GBAP" else None
        records.append(dict(name=path.name, size=len(data), package=package,
                            universal_candidate=package == 4,
                            sha256=hashlib.sha256(data).hexdigest()))
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--built-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", type=int, choices=(6, 7), required=True)
    args = parser.parse_args()
    root, output = args.built_root.resolve(), args.output.resolve()
    if output.exists():
        parser.error("output already exists; choose a new disposable directory")
    if not (root/"build/msx/gbkernm7.sym").is_file():
        parser.error("matching build symbols missing; build the distribution first")
    output.mkdir(parents=True)
    card = output/"card"
    shutil.copytree(root/"QA/MSX/CARD", card)
    config = card/"GEOBENCH.CFG"
    original = config.read_bytes()
    if original.count(b"MSXMODE=7") != 1:
        parser.error("expected exactly one default MSXMODE=7 in the built card")
    config.write_bytes(original.replace(b"MSXMODE=7", f"MSXMODE={args.mode}".encode()))
    image = output/"GEOBENCH.IMG"
    subprocess.run(["bash", "tools/build_msx_img.sh", str(card), str(image)],
                   cwd=root, check=True)
    record = dict(mode=args.mode, image_sha256=hashlib.sha256(image.read_bytes()).hexdigest(),
                  source=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
                  artifacts=inventory(card))
    (output/"manifest.json").write_text(json.dumps(record, indent=2)+"\n")
    print(image)


if __name__ == "__main__":
    main()
