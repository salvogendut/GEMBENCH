from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RASM = shutil.which(os.environ.get("RASM", "rasm"))

# This fixture supplies the core interface without MSX glue, mapper services,
# or the resident kernel. Layouts are deliberately independent of the MSX map.
STATE_FIELDS = (
    ("CORE_ALLOC_HANDLE", 2),
    ("CORE_ALLOC_INDEX", 1),
    ("CORE_ALLOC_NATIVE", 1),
    ("CORE_ALLOC_OWNER", 2),
    ("CORE_ALLOC_PURPOSE", 1),
    ("CORE_APP_ACCESSORY", 8),
    ("CORE_APP_CODE_GEN", 8),
    ("CORE_APP_CODE_NATIVE", 8),
    ("CORE_APP_CODE_PAGE", 8),
    ("CORE_APP_FLAGS", 8),
    ("CORE_APP_PRIMARY_WIN", 8),
    ("CORE_APP_SERVICE", 8),
    ("CORE_APP_WINDOW_COUNT", 8),
    ("CORE_APP_WORKER_WIN", 8),
    ("CORE_DEFER_HANDLER_HI", 8),
    ("CORE_DEFER_HANDLER_LO", 8),
    ("CORE_OWNER_ACTIVE", 8),
    ("CORE_OWNER_GEN", 8),
    ("CORE_PAGE_FREE", 1),
    ("CORE_PAGE_GEN", 32),
    ("CORE_PAGE_NATIVE", 32),
    ("CORE_PAGE_OWNER", 32),
    ("CORE_PAGE_OWNER_GEN", 32),
    ("CORE_PAGE_PURPOSE", 32),
    ("CORE_PAGE_STATE", 32),
    ("CORE_PAGE_TOTAL", 1),
    ("CORE_PENDING_OWNER", 2),
    ("CORE_WIN_OWNER", 8),
    ("CORE_WIN_OWNER_GEN", 8),
    ("CORE_LEGACY_BUSY", 8),
)


@unittest.skipUnless(RASM, "RASM is required for owner/page assembly contracts")
class OwnerPageCoreTests(unittest.TestCase):
    def assemble(self, base: int, overrides: dict[str, int] | None = None
                 ) -> tuple[subprocess.CompletedProcess[str], bytes | None]:
        cells = {}
        cursor = base
        for name, size in STATE_FIELDS:
            if (cursor & 255) + size > 256:
                cursor = (cursor + 255) & ~255
            cells[name] = cursor
            cursor += size
        cells.update({
            "CORE_PAGE_CAPACITY": 32,
            "CORE_OWNER_CAPACITY": 8,
            "CORE_WINDOW_MAX": 8,
        })
        cells.update(overrides or {})
        source = [
            "GB_OWNER_MAX equ 8",
            "GB_PAGE_RESOURCE equ 2",
            "GB_PAGE_ERR_STALE equ 2",
            "GB_PAGE_ERR_OWNER equ 3",
            "GB_PAGE_ERR_FREE equ 4",
            "OWNER_PAGE_CURRENT_OWNER equ #F000",
            "OWNER_PAGE_PURGE_MESSAGES equ #F003",
            "OWNER_PAGE_CLOSE_CONTEXTS equ #F006",
            *[f"{name} equ {value}" for name, value in cells.items()],
            "macro OWNER_PAGE_PUBLISH_FREE",
            f"ld ({base + 0x3F0}),a",
            "mend",
            'include "' + str(ROOT / "kernel/core/owner_page_contract.inc") + '"',
            "org #8000",
            "owner_core_begin",
        ]
        for file in ("page_count.asm", "owner_identity.asm",
                     "page_pool.asm", "owner_reclaim.asm"):
            source.append('include "' + str(ROOT / "kernel/core" / file) + '"')
        source += [
            "owner_core_end",
            'save "owner-core.bin",owner_core_begin,owner_core_end-owner_core_begin',
        ]
        with tempfile.TemporaryDirectory(prefix="geobench-owner-page-") as tmp:
            path = Path(tmp) / "core.asm"
            path.write_text("\n".join(source) + "\n")
            result = subprocess.run(
                [RASM, str(path), "-o", str(Path(tmp) / "out")],
                cwd=tmp, capture_output=True, text=True, check=False,
            )
            binary = Path(tmp) / "owner-core.bin"
            return result, binary.read_bytes() if binary.exists() else None

    def test_core_assembles_with_low_and_high_fixed_state(self) -> None:
        low_result, low = self.assemble(0x2000)
        high_result, high = self.assemble(0xD800)
        for result, binary in ((low_result, low), (high_result, high)):
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIsNotNone(binary, result.stdout + result.stderr)
        self.assertGreater(len(low), 0)
        self.assertEqual(len(low), len(high))
        self.assertNotEqual(low, high, "state operands must follow the supplied layout")

    def test_indexed_table_crossing_a_byte_page_is_rejected(self) -> None:
        result, binary = self.assemble(0x2000, {"CORE_PAGE_STATE": 0x20F0})
        self.assertIsNone(binary, result.stdout + result.stderr)
        self.assertIn("CORE_PAGE_STATE crosses", result.stdout + result.stderr)

    def test_banked_application_memory_is_rejected(self) -> None:
        for field, address in (("CORE_PAGE_NATIVE", 0x4000),
                               ("CORE_ALLOC_OWNER", 0x3FFF)):
            with self.subTest(field=field):
                result, binary = self.assemble(0x2000, {field: address})
                self.assertIsNone(binary, result.stdout + result.stderr)
                self.assertIn(field + " must remain", result.stdout + result.stderr)

    def test_invalid_pool_capacities_are_rejected(self) -> None:
        for capacity in (0, 256):
            with self.subTest(capacity=capacity):
                result, binary = self.assemble(0x2000, {"CORE_PAGE_CAPACITY": capacity})
                self.assertIsNone(binary, result.stdout + result.stderr)
                self.assertIn("capacity must fit", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
