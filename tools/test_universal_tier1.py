#!/usr/bin/env python3
"""Determinism and policy checks for the first production GBAP v4 apps."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from embed_app_icon import parse_manifest  # noqa: E402


APPS = (
    ("apps/ucalculator", "build/universal/CALC.APP", "CALC", {
        "UNIVERSAL_WINDOW_KIND": "1",
        "UNIVERSAL_ACCESSORY": "1",
        "UNIVERSAL_MENU": "1",
        "DATA_LOC": "0x7600",
    }),
    ("apps/uclock", "build/universal/CLOCK.APP", "CLOCK", {
        "UNIVERSAL_TASK": "1",
        "UNIVERSAL_WINDOW_KIND": "1",
        "UNIVERSAL_ACCESSORY": "1",
        "UNIVERSAL_MENU": "1",
        "DATA_LOC": "0x7300",
    }),
)


def build(app: str, output: Path, extra: dict[str, str]) -> None:
    env = dict(os.environ)
    env.update(extra)
    subprocess.run(
        ["bash", "tools/build_uapp.sh", app, str(output)],
        cwd=ROOT,
        env=env,
        check=True,
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="universal-tier1-") as dirname:
        temp = Path(dirname)
        for app, canonical_name, identity, extra in APPS:
            canonical = ROOT / canonical_name
            build(app, canonical, extra)
            rebuilt = temp / canonical.name
            build(app, rebuilt, extra)
            assert canonical.read_bytes() == rebuilt.read_bytes(), \
                f"{identity} universal build is not deterministic"
            manifest = parse_manifest(canonical.read_bytes())
            assert manifest["application_id"] == identity
            assert manifest["profile"] == 3
            assert manifest["platforms"] == 0x07
            assert len(manifest["segments"]) == 1
            assert manifest["image_size"] == canonical.stat().st_size
            if identity == "CLOCK":
                assert manifest["required_capabilities"] & 0x00400000
    print("Universal Calculator/Clock are deterministic primary-only GBAP v4 apps.")


if __name__ == "__main__":
    main()
