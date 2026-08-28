from __future__ import annotations

import json
import re
import struct
import unittest
from pathlib import Path

from tools import gbrc


ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples" / "hello-dialog.json"
HEADER_FILE = ROOT / "include" / "gembench" / "gbr.h"


class CompilerTests(unittest.TestCase):
    def compile_example(self) -> bytes:
        return gbrc.compile_document(json.loads(EXAMPLE.read_text(encoding="utf-8")))

    def test_example_layout_and_tree_links(self) -> None:
        blob = self.compile_example()
        header = gbrc.read_header(blob)

        self.assertEqual(header["magic"], b"GBR1")
        self.assertEqual(header["version"], 1)
        self.assertEqual(header["file_size"], len(blob))
        self.assertEqual(header["string_count"], 3)
        self.assertEqual(header["tree_count"], 1)
        self.assertEqual(header["object_count"], 3)

        object_offset = int(header["object_table_offset"])
        root = gbrc.OBJECT.unpack_from(blob, object_offset)
        label = gbrc.OBJECT.unpack_from(blob, object_offset + gbrc.OBJECT.size)
        button = gbrc.OBJECT.unpack_from(blob, object_offset + 2 * gbrc.OBJECT.size)

        self.assertEqual(root[0:4], (gbrc.NONE8, 1, gbrc.NONE8, gbrc.TYPE_IDS["box"]))
        self.assertEqual(label[0:4], (0, gbrc.NONE8, 2, gbrc.TYPE_IDS["text"]))
        self.assertEqual(button[0:4], (0, gbrc.NONE8, gbrc.NONE8, gbrc.TYPE_IDS["button"]))
        self.assertEqual(label[6], 1)
        self.assertEqual(button[6], 2)

    def test_checksum_covers_file_with_checksum_field_zeroed(self) -> None:
        blob = bytearray(self.compile_example())
        expected = struct.unpack_from("<H", blob, gbrc.HEADER.size - 2)[0]
        struct.pack_into("<H", blob, gbrc.HEADER.size - 2, 0)
        self.assertEqual(sum(blob) & 0xFFFF, expected)

    def test_output_is_deterministic(self) -> None:
        self.assertEqual(self.compile_example(), self.compile_example())

    def test_target_header_matches_host_compiler_constants(self) -> None:
        defines = {
            name: int(value, 0)
            for name, value in re.findall(
                r"^#define\s+(GBR_[A-Z0-9_]+)\s+(0x[0-9A-Fa-f]+|[0-9]+)u\s*$",
                HEADER_FILE.read_text(encoding="ascii"),
                re.MULTILINE,
            )
        }
        self.assertEqual(defines["GBR_VERSION"], gbrc.VERSION)
        self.assertEqual(defines["GBR_MAX_FILE_SIZE"], gbrc.MAX_FILE_SIZE)
        self.assertEqual(defines["GBR_NONE8"], gbrc.NONE8)
        self.assertEqual(defines["GBR_NONE16"], gbrc.NONE16)
        self.assertEqual(defines["GBR_HEADER_SIZE"], gbrc.HEADER.size)
        self.assertEqual(defines["GBR_TREE_RECORD_SIZE"], gbrc.TREE.size)
        self.assertEqual(defines["GBR_OBJECT_RECORD_SIZE"], gbrc.OBJECT.size)
        for name, value in gbrc.TYPE_IDS.items():
            self.assertEqual(defines[f"GBR_TYPE_{name.upper()}"], value)
        for name, value in gbrc.FLAG_BITS.items():
            self.assertEqual(defines[f"GBR_FLAG_{name.upper()}"], value)
        for name, value in gbrc.STATE_BITS.items():
            self.assertEqual(defines[f"GBR_STATE_{name.upper()}"], value)

    def test_unknown_flag_is_rejected(self) -> None:
        source = {
            "format": "GBR1",
            "trees": [
                {
                    "name": "BAD",
                    "root": {"type": "button", "flags": ["flashing"]},
                }
            ],
        }
        with self.assertRaisesRegex(gbrc.ResourceError, "unknown value 'flashing'"):
            gbrc.compile_document(source)

    def test_geometry_outside_screen_7_range_is_rejected(self) -> None:
        source = {
            "format": "GBR1",
            "trees": [{"name": "BAD", "root": {"type": "box", "x": 512}}],
        }
        with self.assertRaisesRegex(gbrc.ResourceError, "expected 0..511"):
            gbrc.compile_document(source)

    def test_non_ascii_string_is_rejected_until_charset_is_defined(self) -> None:
        source = {
            "format": "GBR1",
            "trees": [
                {
                    "name": "BAD",
                    "root": {"type": "text", "text": "cafe\N{LATIN SMALL LETTER E WITH ACUTE}"},
                }
            ],
        }
        with self.assertRaisesRegex(gbrc.ResourceError, "printable ASCII"):
            gbrc.compile_document(source)


if __name__ == "__main__":
    unittest.main()
