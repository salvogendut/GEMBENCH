"""Clipboard ABI/build contracts; real service execution uses emulator probes."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_universal_app import check_source, check_generated_asm
from embed_app_icon import CAPABILITIES_V4

SDCC = os.environ.get("SDCC", "sdcc")


class ClipboardContracts(unittest.TestCase):
    def test_append_only_capability_and_record(self):
        abi = json.loads((ROOT / "abi/geobench-v2.json").read_text())
        self.assertEqual(abi["version"], [2, 1])
        self.assertEqual(abi["caller_parameters"]["record_size"], 16)
        self.assertEqual(abi["sysinfo"]["record_size"], 48)
        self.assertEqual(abi["caller_parameters"]["operations"]["filesystem"], 8)
        self.assertEqual(abi["caller_parameters"]["operations"]["clipboard"], 9)
        self.assertEqual(abi["capabilities"]["high_word_v2"]["typed-clipboard"], 0x01000000)
        self.assertEqual(CAPABILITIES_V4["typed-clipboard"], 0x01000000)
        spec = abi["typed_clipboard"]
        self.assertEqual(spec["header_size"], 8)
        self.assertEqual(spec["capacity"], 510)
        self.assertEqual([(f["offset"], f["size"]) for f in spec["header_fields"]],
                         [(0, 1), (1, 1), (2, 1), (3, 1), (4, 2), (6, 2)])

    def test_receivers_use_one_policy_and_keep_raw_msx_tag(self):
        policy = (ROOT / "kernel/core/parameters.asm").read_text()
        self.assertEqual(policy.count('include "parameters_clipboard.asm"'), 1)
        for target in ("msx", "cpc"):
            provider = (ROOT / f"kernel/{target}_parameter_provider.inc").read_text()
            for name in ("PARAM_SCRAP_LENGTH", "PARAM_SCRAP_DATA", "PARAM_SCRAP_TYPE"):
                self.assertIn(name+" equ ", provider)
        msx = (ROOT / "kernel/msx_parameter_provider.inc").read_text()
        self.assertIn("PARAM_SCRAP_TYPE equ SCRAP_TYPE", msx)
        raw = (ROOT / "kernel/gbkern.asm").read_text()
        self.assertIn("ld    (SCRAP_TYPE),a", raw[raw.index("\nk_clip_set\n"):raw.index("\nk_clip_get\n")])
        cpc = (ROOT / "kernel/cpc_runtime_boot.asm").read_text()
        self.assertIn("ld (CPC_CLIPBOARD_BASE),hl", cpc)
        self.assertIn("ld (CPC_SCRAP_TYPE),a", cpc)
        shared = (ROOT / "kernel/core/parameters_clipboard.asm").read_text()
        code = "\n".join(line.split(";", 1)[0] for line in shared.splitlines())
        self.assertNotRegex(code, r"\b(?:MSX_|CPC_|PLATFORM_)\w+")

    def test_no_new_native_application_dependencies(self):
        errors = []
        for path in ("apps/scrapprobe/main.c", "lib/gembench/gbscrap_universal.c"):
            check_source(ROOT / path, errors)
        self.assertEqual(errors, [])
        spec = json.loads((ROOT / "apps/scrapprobe/manifest.json").read_text())
        self.assertIn("typed-clipboard", spec["required_capabilities"])

    @unittest.skipUnless(shutil.which(SDCC), "SDCC required")
    def test_sdk_object_has_only_eight_bytes_of_state(self):
        with tempfile.TemporaryDirectory(prefix="geobench-scrap-sdk-") as temp:
            obj = Path(temp) / "gbscrap_universal.rel"
            subprocess.run([SDCC, "-mz80", "--std-c99", "--opt-code-size",
                            "--fomit-frame-pointer", "-DGB_UNIVERSAL",
                            "-I", str(ROOT / "lib/gb"), "-I", str(ROOT / "include/gembench"),
                            "-c", str(ROOT / "lib/gembench/gbscrap_universal.c"),
                            "-o", str(obj)], check=True)
            areas = {name: int(size, 16) for name, size in
                     re.findall(r"^A (\S+) size ([0-9A-Fa-f]+)", obj.read_text(), re.M)}
            self.assertEqual(areas["_DATA"], 8)
            self.assertLessEqual(areas["_CODE"], 512)
            errors = []
            check_generated_asm(obj.with_suffix(".asm"), errors)
            self.assertEqual(errors, [])
            print(f"portable clipboard SDK: {areas['_CODE']} code + 8 data bytes")

    @unittest.skipUnless(shutil.which(SDCC), "SDCC required")
    def test_builder_rejects_missing_capability_and_invalid_flag(self):
        with tempfile.TemporaryDirectory(prefix="geobench-scrap-flags-") as temp:
            for flag, manifest, message in (
                ("1", "apps/fsprobe/manifest.json", "UNIVERSAL_SCRAP requires typed-clipboard"),
                ("2", "apps/scrapprobe/manifest.json", "feature flags must be 0 or 1"),
            ):
                result = subprocess.run(["bash", "tools/build_uapp.sh", "apps/scrapprobe",
                                         str(Path(temp) / "probe.APP")], cwd=ROOT,
                    env={**os.environ, "UNIVERSAL_SCRAP": flag,
                         "APP_MANIFEST": manifest, "APP_ICON": "apps/abiprobe/icon.asm"},
                    capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
