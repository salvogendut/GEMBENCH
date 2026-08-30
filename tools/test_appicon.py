#!/usr/bin/env python3
"""Round-trip checks for the optional GBAP application icon preamble."""

import os
import tempfile

from embed_app_icon import (CODEC_SCREEN7, DUAL_PREAMBLE_SIZE, PREAMBLE_SIZE,
                            VERSION_V3, _read_manifest_spec, make_preamble,
                            make_v3_preamble, parse_icon, parse_manifest,
                            parse_resources, v3_preamble_size, valid_preamble)
from iconedit import (asm_label_from_path, load_app_icon, load_asm_icon,
                      save_app_icon, save_asm_icon)


def main():
    icon = parse_icon("apps/formref/icon.asm")
    icon16 = parse_icon("apps/formref/icon16.asm", CODEC_SCREEN7)
    source_icons, source_label = load_asm_icon("apps/formref/icon.asm")
    source16_icons, source16_label = load_asm_icon("apps/formref/icon16.asm")
    assert source_label == "appicon"
    assert source16_label == "appicon16"
    assert source_icons[0]["w"] == 8 and source_icons[0]["h"] == 32
    assert source16_icons[0]["codec"] == CODEC_SCREEN7
    executable = bytes((0xCD, 0x34, 0x12, 0xC9)) + bytes(range(64))
    original = make_preamble(icon) + executable
    assert len(original[:PREAMBLE_SIZE]) == PREAMBLE_SIZE
    assert valid_preamble(original)

    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "FORMREF.APP")
        with open(path, "wb") as target:
            target.write(original)
        icons, app_data = load_app_icon(path)
        assert len(icons) == 1
        assert icons[0]["w"] == 8 and icons[0]["h"] == 32
        icons[0]["grid"][0][0] ^= 3
        save_app_icon(path, icons, app_data)
        with open(path, "rb") as source:
            edited = source.read()

        asm_path = os.path.join(tmp, "saved-icon.asm")
        source_icons[0]["grid"][0][0] ^= 3
        save_asm_icon(asm_path, source_icons, source_label)
        roundtrip_icons, roundtrip_label = load_asm_icon(asm_path)
        assert roundtrip_label == source_label
        assert roundtrip_icons == source_icons
        assert parse_icon(asm_path) != icon

        dual_path = os.path.join(tmp, "DUAL.APP")
        dual_original = make_preamble(icon, icon16) + executable
        assert len(dual_original[:DUAL_PREAMBLE_SIZE]) == DUAL_PREAMBLE_SIZE
        assert valid_preamble(dual_original)
        total, resources = parse_resources(dual_original)
        assert total == DUAL_PREAMBLE_SIZE
        assert [item["codec"] for item in resources] == [1, 7]
        reversed_directory = bytearray(dual_original)
        reversed_directory[16:24], reversed_directory[24:32] = \
            reversed_directory[24:32], reversed_directory[16:24]
        try:
            parse_resources(reversed_directory)
        except ValueError:
            pass
        else:
            raise AssertionError("GBAP v2 accepted a non-portable resource 0")
        with open(dual_path, "wb") as target:
            target.write(dual_original)
        dual_icons, dual_data = load_app_icon(dual_path)
        assert [item["codec"] for item in dual_icons] == [1, 7]
        dual_icons[0]["grid"][0][0] ^= 3
        dual_icons[1]["grid"][0][0] ^= 15
        save_app_icon(dual_path, dual_icons, dual_data)
        with open(dual_path, "rb") as source:
            dual_edited = source.read()
        assert dual_edited[:32] == dual_original[:32]
        assert dual_edited[DUAL_PREAMBLE_SIZE:] == executable
        assert dual_edited[32:DUAL_PREAMBLE_SIZE] != \
            dual_original[32:DUAL_PREAMBLE_SIZE]

        manifest_spec = _read_manifest_spec("apps/formref/manifest.json")
        secondary = bytes((0xC3, 0x08, 0x40)) + b"GBS3" + bytes((1,)) + \
            bytes((0xAF, 0xC9))
        v3_size = v3_preamble_size(True, 2)
        v3_original = make_v3_preamble(
            icon, manifest_spec, v3_size + len(executable), icon16, secondary
        ) + executable + secondary
        assert v3_original[7] == VERSION_V3
        assert valid_preamble(v3_original)
        v3_manifest = parse_manifest(v3_original)
        assert v3_manifest["application_id"] == "FORMREF"
        assert v3_manifest["platforms"] == 2
        assert v3_manifest["entry_offset"] == v3_size
        assert len(v3_manifest["segments"]) == 2
        assert v3_manifest["segments"][0]["offset"] == v3_size
        assert v3_manifest["segments"][1]["type"] == 2
        assert v3_manifest["segments"][1]["offset"] == \
            v3_size + len(executable)

        # The original M5 primary-only package remains valid after the M6
        # descriptor extension.
        m5_spec = dict(manifest_spec)
        m5_spec["secondary_code"] = None
        m5_spec["required_capabilities"] &= ~0x2000
        m5_size = v3_preamble_size(True, 1)
        m5_original = make_v3_preamble(
            icon, m5_spec, m5_size + len(executable), icon16
        ) + executable
        m5_manifest = parse_manifest(m5_original)
        assert m5_manifest["entry_offset"] == m5_size
        assert len(m5_manifest["segments"]) == 1
        assert m5_manifest["segments"][0]["type"] == 1

        v3_path = os.path.join(tmp, "V3.APP")
        with open(v3_path, "wb") as target:
            target.write(v3_original)
        v3_icons, v3_data = load_app_icon(v3_path)
        v3_icons[0]["grid"][0][0] ^= 3
        save_app_icon(v3_path, v3_icons, v3_data)
        with open(v3_path, "rb") as source:
            v3_edited = source.read()
        assert parse_manifest(v3_edited) == v3_manifest
        assert v3_edited[v3_size:] == executable + secondary

        for offset, value in (
            (7, 4),                         # unsupported outer version
            (32 + 7, 0),                    # no compatible platform
            (32 + 34, 0),                   # false image length
            (32 + 40 + 3, 1),               # unsupported primary compression
            (32 + 40 + 12 + 2, 0),          # secondary not executable/required
            (v3_size + len(executable) + 3, 0),  # bad GBS3 prefix
        ):
            broken = bytearray(v3_original)
            broken[offset] = value
            assert not valid_preamble(broken), \
                f"GBAP v3 accepted corruption at offset {offset}"

        asm16_path = os.path.join(tmp, "saved-icon16.asm")
        source16_icons[0]["grid"][0][0] ^= 15
        save_asm_icon(asm16_path, source16_icons, source16_label)
        roundtrip16, roundtrip16_label = load_asm_icon(asm16_path)
        assert roundtrip16_label == source16_label
        assert roundtrip16 == source16_icons
        assert parse_icon(asm16_path, CODEC_SCREEN7) != icon16

    assert edited[:16] == original[:16], "metadata or JP entry changed"
    assert edited[PREAMBLE_SIZE:] == original[PREAMBLE_SIZE:], \
        "application executable changed"
    assert edited[16:PREAMBLE_SIZE] != original[16:PREAMBLE_SIZE], \
        "icon edit was not stored"
    assert asm_label_from_path("/tmp/My APP Icon.asm") == "My_APP_Icon"
    assert asm_label_from_path("/tmp/1984.asm") == "icon_1984"
    try:
        save_asm_icon("/tmp/invalid.asm", source_icons, "bad:")
    except ValueError:
        pass
    else:
        raise AssertionError("invalid RASM label accepted")

    for path in ("build/FORMREF.RAW", "build/msx/FORMREF.RAW",
                 "build/pcw/FORMREF.RAW"):
        if os.path.exists(path):
            with open(path, "rb") as source:
                assert valid_preamble(source.read()), \
                    f"{path}: invalid generated preamble"
    print("GBAP v1/v2/v3 package and editor round-trip checks passed.")


if __name__ == "__main__":
    main()
