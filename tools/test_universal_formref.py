#!/usr/bin/env python3
"""Build-level gate for universal FormRef and its sealed computation leaf."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from embed_app_icon import parse_manifest


ROOT = Path(__file__).resolve().parents[1]


def build(output: Path) -> bytes:
    subprocess.run(["bash", "tools/build_uformref.sh", str(output)],
                   cwd=ROOT, check=True)
    return output.read_bytes()


def main() -> None:
    native_resource = ROOT / "build/msx/FORMREF.GBR"
    subprocess.run(["python3", "tools/gbrc.py", "apps/formref/formref.json",
                    "--output", str(native_resource)], cwd=ROOT, check=True)
    first = build(ROOT / "build/universal/FORMREF.APP")
    with tempfile.TemporaryDirectory(prefix="universal-formref-") as dirname:
        second = build(Path(dirname) / "FORMREF.APP")
    assert first == second, "universal FormRef build is not deterministic"
    resource = (ROOT / "build/universal/FORMREF.GBR").read_bytes()
    assert resource == native_resource.read_bytes()
    assert len(resource) == 231
    assert hashlib.sha256(resource).hexdigest() == \
        "a5f473f4665e5f119bf809819e8e191d509f41bda3cd0111320e54f3750bdfc8"
    package = parse_manifest(first)
    assert (package["version"], package["profile"],
            package["application_id"], package["minimum_pages"],
            len(package["segments"])) == (4, 3, "FORMREF", 2, 2)
    primary, secondary = package["segments"]
    assert (primary["type"], secondary["type"]) == (1, 2)
    secondary_image = (ROOT / "build/universal/FORMREF.BIN").read_bytes()
    assert first[secondary["offset"]:
                 secondary["offset"] + secondary["stored_length"]] == \
        secondary_image
    audit = json.loads((ROOT / "build/universal/FORMREF.BIN.audit.json").read_text())
    assert audit["profile"] == "gbs4-computation-v1"
    assert audit["sha256"] == hashlib.sha256(secondary_image).hexdigest()
    spec = json.loads((ROOT / "apps/uformref/manifest.json").read_text())
    assert spec["platforms"] == ["cpc", "msx2", "pcw"]
    assert "portable-secondary-calls" in spec["required_capabilities"]
    assert spec["secondary_code"] == {"required": True}
    source = (ROOT / "apps/uformref/main.c").read_text()
    assert "GB_MSX2" not in source and "PLATFORM_CPC" not in source
    assert "gbr_form_click" in source and "gbr_form_key" in source
    assert "GBR_KEY_BACKTAB" in source
    assert "gb_form_modal_run" in source
    assert "gb_compute" in source
    print(f"Universal FormRef: {len(first)} identical package bytes, "
          f"{len(secondary_image)} sealed computation bytes; frozen embedded "
          "GBR1 and complete build gate PASS")


if __name__ == "__main__":
    main()
