from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CC = shutil.which(os.environ.get("CC", "cc"))
RASM = shutil.which(os.environ.get("RASM", "rasm"))


class StorageServiceBoundaryTests(unittest.TestCase):
    def test_shared_policy_has_no_native_memory_or_transport(self):
        fs = (ROOT / "kernel/core/fsctx_policy.inc").read_text()
        self.assertNotRegex(fs, r"\b(?:gb_\w+|gbfs_msx_\w+|MSX_\w+|FS_LOAD_OFS|FS_XFLAGS|ACTIVE_FIB)\b")
        self.assertNotRegex(fs, r"0x[0-9A-Fa-f]{4}")
        service = (ROOT / "lib/gembench/core/service_internal.h").read_text()
        self.assertNotRegex(service, r"0x[0-9A-Fa-f]{4}|\b(?:MSX_\w+|gb_net_\w+)\b")
        cleanup = (ROOT / "kernel/core/fsctx_cleanup.asm").read_text()
        code = "\n".join(line.split(";", 1)[0] for line in cleanup.splitlines())
        self.assertNotRegex(code, r"\b(?:MSX_\w+|BDOS|call|di|ei|in|out|sp)\b")

    def test_single_placement_and_incremental_dependencies(self):
        wrapper = (ROOT / "kernel/kc/gbfsctx_mod.c").read_text()
        self.assertEqual(wrapper.count('#include "../core/fsctx_policy.inc"'), 1)
        pool = (ROOT / "kernel/msx_page_pool.asm").read_text()
        token = 'include "core/fsctx_cleanup.asm"'
        self.assertEqual(pool.count(token), 1)
        self.assertGreater(pool.index(token), pool.index("ifdef GB_DEFER_LATE"))
        builder = (ROOT / "tools/build_fsctxmod.sh").read_text()
        deps = builder[builder.index("deps=("):builder.index('stamp="$OUT.stamp"')]
        for filename in ("msx_fsctx.h", "fsctx_layout.h", "fsctx_contract.h", "fsctx_policy.inc"):
            self.assertIn(filename, deps)
        builder = (ROOT / "tools/build_capp.sh").read_text()
        deps = builder[builder.index('deps+='):builder.index('stamp="$OUT.stamp"')]
        for filename in ("msx_service.h", "core/service_contract.h", "core/service_internal.h"):
            self.assertIn(filename, deps)
        service = (ROOT / "lib/gembench/gbservice_internal.h").read_text()
        self.assertIn("#include GB_SERVICE_PLATFORM_HEADER", service)
        self.assertIn("#ifdef GB_MSX2", service)
        self.assertIn('#error "Select an explicit', service)

    def test_msx_bindings_and_cleanup_match_authoritative_layout(self):
        glue = (ROOT / "lib/msx/glue.inc").read_text()
        def native(name):
            return int(re.search(rf"^{name}\s+equ\s+#([0-9A-F]+)", glue, re.M)[1], 16)
        for path, pairs in (
            ("kernel/kc/msx_fsctx.h", (("FSCTX_REQUEST_ADDRESS", "MSX_FSCTX_REQ"),
              ("FSCTX_TRANSFER_ADDRESS", "MSX_FSCTX_TRANSFER"), ("FSCTX_TABLE_ADDRESS", "MSX_FSCTX_TABLE"),
              ("FSCTX_PENDING_ADDRESS", "MSX_FSCTX_PENDING"), ("FSCTX_DIAG_ADDRESS", "MSX_FSCTX_DIAG"),
              ("FSCTX_CURSOR_ADDRESS", "MSX_FSCTX_FIB"))),
            ("lib/gembench/msx_service.h", (("GB_SERVICE_PROVIDER_ADDRESS", "MSX_SERVICE_PROVIDERS"),
              ("GB_SERVICE_LEASE_ADDRESS", "MSX_SERVICE_LEASES"), ("GB_SERVICE_LOCK_ADDRESS", "MSX_SERVICE_LOCK"),
              ("GB_SERVICE_DIAG_ADDRESS", "MSX_SERVICE_DIAG")))):
            source = (ROOT / path).read_text()
            for portable, msx in pairs:
                value = int(re.search(rf"#define {portable}\s+0x([0-9A-F]+)", source)[1], 16)
                self.assertEqual(value, native(msx), portable)
        layout = (ROOT / "kernel/core/fsctx_layout.h").read_text()
        for field, msx in (("CTX_SIZE", "MSX_FSCTX_RECORD_SIZE"), ("CTX_MAX", "MSX_FSCTX_MAX")):
            value = int(re.search(rf"#define {field}\s+(\d+)u", layout)[1])
            self.assertEqual(value, int(re.search(rf"^{msx}\s+equ\s+(\d+)", glue, re.M)[1]))
        binding = (ROOT / "kernel/msx_fsctx_cleanup.inc").read_text()
        for field, shared in (("ACTIVE", "CTX_ACTIVE"), ("OWNER", "CTX_OWNER")):
            value = int(re.search(rf"CORE_FSCTX_{field} equ (\d+)", binding)[1])
            self.assertEqual(value, int(re.search(rf"#define {shared}\s+(\d+)u", layout)[1]))


@unittest.skipUnless(CC, "host C compiler required for actual policy tests")
class StorageServiceExecutionTests(unittest.TestCase):
    def compile(self, filename, base, extra=(), execute=True):
        with tempfile.TemporaryDirectory(prefix="geobench-storage-service-") as tmp:
            output = Path(tmp) / "test"
            command = [CC, "-std=c99", "-Wall", "-Wextra", "-Werror", f"-DFIXTURE_BASE={base}",
                       "-I", str(ROOT / "lib/gb"), "-I", str(ROOT / "include/gembench"),
                       "-I", str(ROOT / "tests/fixtures"), *extra,
                       str(ROOT / "tests" / filename), "-o", str(output)]
            result = subprocess.run(command, text=True, capture_output=True)
            if execute:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                result = subprocess.run([str(output)], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("core: PASS", result.stdout)
            return result

    def test_actual_filesystem_policy_with_independent_low_high_state(self):
        for base in ("0x2000", "0xD800"):
            self.compile("test_fsctx_core.c", base)

    def test_actual_service_policy_with_independent_low_high_state(self):
        for base in ("0x2000", "0xD800"):
            self.compile("test_service_core.c", base)

    def test_fixed_span_and_overlap_rejections(self):
        for filename in ("test_fsctx_core.c", "test_service_core.c"):
            for base in ("-1", "0x3FF8", "0x4000", "0xFFFC"):
                result = self.compile(filename, base, execute=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("must fit fixed", result.stderr)
        for filename, override, message in (
            ("test_fsctx_core.c", "-DFSCTX_TABLE_ADDRESS=0x2000", "overlaps"),
            ("test_fsctx_core.c", "-DFSCTX_TRANSFER_ADDRESS=0x3F00", "must fit fixed"),
            ("test_service_core.c", "-DGB_SERVICE_PROVIDER_ADDRESS=0x200E", "overlaps")):
            result = self.compile(filename, "0x2000", (override,), execute=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)


@unittest.skipUnless(RASM, "RASM required for resident cleanup provider fixtures")
class FilesystemCleanupAssemblyTests(unittest.TestCase):
    def assemble(self, overrides=None):
        values = dict(CORE_FSCTX_TABLE=0x2000, CORE_FSCTX_MAX=4,
                      CORE_FSCTX_RECORD_SIZE=144, CORE_FSCTX_ACTIVE=0,
                      CORE_FSCTX_OWNER=2, CORE_ALLOC_OWNER=0x2300)
        values.update(overrides or {})
        source = [*[f"{key} equ {value}" for key, value in values.items()],
                  f'include "{ROOT}/kernel/core/fsctx_cleanup_contract.inc"', "org #8000",
                  f'include "{ROOT}/kernel/core/fsctx_cleanup.asm"',
                  'save "cleanup.bin",#8000,$-#8000']
        with tempfile.TemporaryDirectory(prefix="geobench-fsctx-cleanup-") as tmp:
            asm = Path(tmp) / "cleanup.asm"
            asm.write_text("\n".join(source) + "\n")
            result = subprocess.run([RASM, str(asm)], cwd=tmp, text=True, capture_output=True)
            binary = Path(tmp) / "cleanup.bin"
            return result, binary.read_bytes() if binary.exists() else None

    def test_independent_state_and_record_layouts(self):
        low = self.assemble()
        high = self.assemble(dict(CORE_FSCTX_TABLE=0xD800, CORE_ALLOC_OWNER=0xDB00))
        alternate = self.assemble(dict(CORE_FSCTX_RECORD_SIZE=16, CORE_FSCTX_ACTIVE=3, CORE_FSCTX_OWNER=6))
        for result, binary in (low, high, alternate):
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIsNotNone(binary)
        self.assertEqual(len(low[1]), len(high[1]))
        self.assertEqual(len(low[1]), len(alternate[1]))
        self.assertNotEqual(low[1], high[1])
        self.assertEqual(low[1], self.assemble()[1])

    def test_fixed_state_and_indexed_field_contract(self):
        for name, values in (("CORE_FSCTX_TABLE", (-1, 0x3FFF, 0x4000, 0xFF00)),
                             ("CORE_ALLOC_OWNER", (0x4000, 0xFFFF, 0x2000)),
                             ("CORE_FSCTX_MAX", (0, 256)),
                             ("CORE_FSCTX_RECORD_SIZE", (3, 256)),
                             ("CORE_FSCTX_ACTIVE", (-1, 2, 128)),
                             ("CORE_FSCTX_OWNER", (-1, 0, 127))):
            for value in values:
                result, binary = self.assemble({name: value})
                self.assertIsNone(binary, (name, value))
                self.assertIn("ASSERT", (result.stdout + result.stderr).upper())


if __name__ == "__main__":
    unittest.main()
