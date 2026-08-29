from __future__ import annotations

import json
import re
import struct
import unittest
from pathlib import Path

from tools import gbrc


ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples" / "hello-dialog.json"
FORMREF_SOURCE = ROOT / "apps" / "formref" / "formref.json"
FORMREF_HEADER = ROOT / "apps" / "formref" / "formref_gbr.h"
CALCULATOR_SOURCE = ROOT / "apps" / "calculator" / "calculator.json"
CALCULATOR_HEADER = ROOT / "apps" / "calculator" / "calculator_gbr.h"
FILEMGR_MENU_SOURCE = ROOT / "apps" / "filemgr" / "view_menu.json"
FILEMGR_MENU_HEADER = ROOT / "apps" / "filemgr" / "view_menu_gbr.h"
HEADER_FILE = ROOT / "include" / "gembench" / "gbr.h"
GOLDEN_FILE = ROOT / "tests" / "fixtures" / "hello-dialog.gbr.inc"


class CompilerTests(unittest.TestCase):
    def compile_example(self) -> bytes:
        return gbrc.compile_document(json.loads(EXAMPLE.read_text(encoding="utf-8")))

    def golden_example(self) -> bytes:
        values = re.findall(r"0x([0-9a-fA-F]{2})", GOLDEN_FILE.read_text(encoding="ascii"))
        return bytes(int(value, 16) for value in values)

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

    def test_generated_header_can_omit_the_embedded_blob(self) -> None:
        header = gbrc.render_c_header(self.compile_example(), {}, "HELLO")
        self.assertIn("#ifndef GEMBENCH_GBR_METADATA_ONLY", header)
        self.assertIn("static const unsigned char hello_gbr[]", header)
        self.assertIn("#endif /* GEMBENCH_GBR_METADATA_ONLY */", header)

    def test_example_matches_committed_golden_binary(self) -> None:
        self.assertEqual(self.compile_example(), self.golden_example())

    def test_strict_verifier_accepts_the_golden_binary(self) -> None:
        header = gbrc.verify_blob(self.golden_example())
        self.assertEqual(header["tree_count"], 1)
        self.assertEqual(header["object_count"], 3)

    def test_strict_verifier_rejects_corruptions(self) -> None:
        def repaired(blob: bytearray) -> bytes:
            struct.pack_into("<H", blob, gbrc.HEADER.size - 2, 0)
            struct.pack_into("<H", blob, gbrc.HEADER.size - 2, sum(blob) & 0xFFFF)
            return bytes(blob)

        corruptions: list[tuple[str, int, int, str]] = [
            ("layout", 16, 0x1F, "canonical v1 layout"),
            ("string", 0x52, 0xFF, "payload exceeds"),
            ("tree", 0x1E, 3, "invalid object range"),
            ("object type", 0x22 + 3, 10, "unknown object type"),
            ("text reference", 0x32 + 8, 3, "text string is out of range"),
            ("root parent", 0x22, 0, "root links"),
        ]
        for name, offset, value, message in corruptions:
            with self.subTest(name=name):
                blob = bytearray(self.golden_example())
                blob[offset] = value
                with self.assertRaisesRegex(gbrc.ResourceError, message):
                    gbrc.verify_blob(repaired(blob))

        blob = bytearray(self.golden_example())
        blob[-1] ^= 1
        with self.assertRaisesRegex(gbrc.ResourceError, "checksum mismatch"):
            gbrc.verify_blob(bytes(blob))

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

    def test_text_and_raw_specs_are_type_safe(self) -> None:
        text_on_box = {
            "format": "GBR1",
            "trees": [{"name": "BAD", "root": {"type": "box", "text": "no"}}],
        }
        with self.assertRaisesRegex(gbrc.ResourceError, "box objects do not carry text"):
            gbrc.compile_document(text_on_box)

        raw_button = {
            "format": "GBR1",
            "trees": [{"name": "BAD", "root": {"type": "button", "spec": 1}}],
        }
        with self.assertRaisesRegex(gbrc.ResourceError, "button objects require text"):
            gbrc.compile_document(raw_button)

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

    def test_formref_ids_are_source_only_and_header_is_current(self) -> None:
        document = json.loads(FORMREF_SOURCE.read_text(encoding="utf-8"))
        blob, object_ids = gbrc.compile_document_with_ids(document)
        self.assertEqual(
            object_ids,
            {
                "FORMREF_ROOT": 0,
                "FORMREF_NAME": 2,
                "FORMREF_AUTOSAVE": 3,
                "FORMREF_LAYOUT_CLASSIC": 4,
                "FORMREF_LAYOUT_REFINED": 5,
                "FORMREF_SAVE": 6,
                "FORMREF_CANCEL": 7,
            },
        )

        def remove_ids(obj: object) -> None:
            if isinstance(obj, dict):
                obj.pop("id", None)
                for value in obj.values():
                    remove_ids(value)
            elif isinstance(obj, list):
                for value in obj:
                    remove_ids(value)

        without_ids = json.loads(json.dumps(document))
        remove_ids(without_ids)
        self.assertEqual(blob, gbrc.compile_document(without_ids))
        self.assertEqual(
            FORMREF_HEADER.read_text(encoding="ascii"),
            gbrc.render_c_header(blob, object_ids, "FORMREF"),
        )

        header = gbrc.read_header(blob)
        object_offset = int(header["object_table_offset"])
        name_field = gbrc.OBJECT.unpack_from(
            blob, object_offset + object_ids["FORMREF_NAME"] * gbrc.OBJECT.size
        )
        save = gbrc.OBJECT.unpack_from(
            blob, object_offset + object_ids["FORMREF_SAVE"] * gbrc.OBJECT.size
        )
        self.assertEqual(name_field[3], gbrc.TYPE_IDS["field"])
        self.assertEqual(name_field[4], gbrc.FLAG_BITS["selectable"])
        self.assertEqual(
            save[4],
            gbrc.FLAG_BITS["selectable"]
            | gbrc.FLAG_BITS["default"]
            | gbrc.FLAG_BITS["exit"],
        )

    def test_object_ids_must_be_unique_c_identifiers(self) -> None:
        source = {
            "format": "GBR1",
            "trees": [
                {
                    "name": "BAD",
                    "root": {
                        "id": "not-c",
                        "type": "box",
                    },
                }
            ],
        }
        with self.assertRaisesRegex(gbrc.ResourceError, "uppercase C identifier"):
            gbrc.compile_document(source)

        source["trees"][0]["root"] = {
            "id": "SAME",
            "type": "box",
            "children": [{"id": "SAME", "type": "text", "text": "x"}],
        }
        with self.assertRaisesRegex(gbrc.ResourceError, "duplicate object id SAME"):
            gbrc.compile_document(source)

    def test_calculator_panel_header_and_button_order_are_current(self) -> None:
        document = json.loads(CALCULATOR_SOURCE.read_text(encoding="utf-8"))
        blob, object_ids = gbrc.compile_document_with_ids(document)
        self.assertEqual(len(object_ids), 21)
        self.assertEqual(object_ids["CALCULATOR_ROOT"], 0)
        self.assertEqual(object_ids["CALCULATOR_CLEAR"], 1)
        self.assertEqual(object_ids["CALCULATOR_EQUALS"], 20)
        self.assertEqual(
            CALCULATOR_HEADER.read_text(encoding="ascii"),
            gbrc.render_c_header(blob, object_ids, "CALCULATOR"),
        )
        header = gbrc.read_header(blob)
        object_offset = int(header["object_table_offset"])
        equals = gbrc.OBJECT.unpack_from(
            blob,
            object_offset + object_ids["CALCULATOR_EQUALS"] * gbrc.OBJECT.size,
        )
        self.assertEqual(equals[3], gbrc.TYPE_IDS["button"])
        self.assertEqual(
            equals[4],
            gbrc.FLAG_BITS["selectable"] | gbrc.FLAG_BITS["default"],
        )

    def test_file_manager_menu_metadata_is_source_only_and_current(self) -> None:
        document = json.loads(FILEMGR_MENU_SOURCE.read_text(encoding="utf-8"))
        blob, object_ids = gbrc.compile_document_with_ids(document)
        without_shortcuts = json.loads(json.dumps(document))

        def remove_shortcuts(obj: object) -> None:
            if isinstance(obj, dict):
                obj.pop("shortcut", None)
                for value in obj.values():
                    remove_shortcuts(value)
            elif isinstance(obj, list):
                for value in obj:
                    remove_shortcuts(value)

        remove_shortcuts(without_shortcuts)
        self.assertEqual(blob, gbrc.compile_document(without_shortcuts))
        rendered = gbrc.render_menu_header(document, object_ids, "FILEMGR_VIEW")
        self.assertEqual(FILEMGR_MENU_HEADER.read_text(encoding="ascii"), rendered)
        descriptor = bytes(
            int(value, 16) for value in re.findall(r"0x([0-9a-f]{2})", rendered)
        )
        self.assertEqual(descriptor[:7], b"GBRM\x01\x03\x04")
        self.assertEqual(descriptor[7:11], b"View")
        self.assertEqual(descriptor[11:15], b"\x01\x08F\x0a")
        self.assertEqual(descriptor[25:29], b"\x02\x06I\x05")
        self.assertEqual(descriptor[34:38], b"\x03\x04L\x04")

    def test_menu_metadata_rejects_ambiguous_shortcuts_and_shapes(self) -> None:
        document = json.loads(FILEMGR_MENU_SOURCE.read_text(encoding="utf-8"))
        blob, object_ids = gbrc.compile_document_with_ids(document)
        document["trees"][0]["root"]["children"][2]["shortcut"] = "i"
        with self.assertRaisesRegex(gbrc.ResourceError, "duplicate menu shortcut"):
            gbrc.render_menu_header(document, object_ids, "FILEMGR_VIEW")

        document = json.loads(FILEMGR_MENU_SOURCE.read_text(encoding="utf-8"))
        document["trees"][0]["root"]["children"][0]["children"] = [
            {"type": "button", "text": "Nested", "flags": ["selectable"]}
        ]
        _, nested_ids = gbrc.compile_document_with_ids(document)
        with self.assertRaisesRegex(gbrc.ResourceError, "nested menu items"):
            gbrc.render_menu_header(document, nested_ids, "FILEMGR_VIEW")

        self.assertEqual(gbrc.verify_blob(blob)["version"], 1)


if __name__ == "__main__":
    unittest.main()
