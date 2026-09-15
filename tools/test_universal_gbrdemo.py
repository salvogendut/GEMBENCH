#!/usr/bin/env python3
"""Build-level gate for the private compile-once GBRDEMO vertical slice."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def build(output: Path) -> bytes:
    subprocess.run(
        ["bash", "tools/build_ugbrdemo.sh", str(output)],
        cwd=ROOT,
        check=True,
    )
    return output.read_bytes()


def main() -> None:
    manifest = json.loads(
        (ROOT / "apps/ugbrdemo/manifest.json").read_text(encoding="ascii")
    )
    assert manifest["profile"] == "universal-z80"
    assert manifest["platforms"] == ["cpc", "msx2", "pcw"]
    required = set(manifest["required_capabilities"])
    assert {"caller-parameters", "portable-filesystem",
            "runtime-geometry", "portable-drawing"} <= required
    assert "gbr" not in required and "package-resources" not in required

    source = (ROOT / "apps/ugbrdemo/main.c").read_text(encoding="ascii")
    assert "gb_fsctx_adopt_launch()" in source
    assert "gbr_open(&resource" in source
    assert "GB_MSX2" not in source and "PLATFORM_CPC" not in source

    first = build(ROOT / "build/universal/GBRDEMO.APP")
    with tempfile.TemporaryDirectory(prefix="universal-gbrdemo-") as dirname:
        second = build(Path(dirname) / "rebuilt.APP")
    assert first == second, "universal GBRDEMO build is not deterministic"
    assert first[0:3] == b"\xc3\x6c\x41" and first[7] == 4
    assert b"GBRDEMO " in first[:128]
    print(f"Universal GBRDEMO: {len(first)} identical bytes; "
          "portable external GBR1 build gate PASS")


if __name__ == "__main__":
    main()
