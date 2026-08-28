#!/usr/bin/env python3
"""Round-trip checks for the optional GBAP application icon preamble."""

import os
import tempfile

from embed_app_icon import (CODEC_SCREEN7, DUAL_PREAMBLE_SIZE, PREAMBLE_SIZE,
                            make_preamble, parse_icon, parse_resources,
                            valid_preamble)
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
    print("GBAP v1/v2 icon preamble and editor round-trip checks passed.")


if __name__ == "__main__":
    main()
