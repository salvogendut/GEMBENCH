#!/usr/bin/env python3
"""Round-trip checks for the optional GBAP application icon preamble."""

import os
import tempfile

from embed_app_icon import (PREAMBLE_SIZE, make_preamble, parse_icon,
                            valid_preamble)
from iconedit import load_app_icon, save_app_icon


def main():
    icon = parse_icon("apps/formref/icon.asm")
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

    assert edited[:16] == original[:16], "metadata or JP entry changed"
    assert edited[PREAMBLE_SIZE:] == original[PREAMBLE_SIZE:], \
        "application executable changed"
    assert edited[16:PREAMBLE_SIZE] != original[16:PREAMBLE_SIZE], \
        "icon edit was not stored"

    for path in ("build/FORMREF.RAW", "build/msx/FORMREF.RAW",
                 "build/pcw/FORMREF.RAW"):
        if os.path.exists(path):
            with open(path, "rb") as source:
                assert valid_preamble(source.read(PREAMBLE_SIZE)), \
                    f"{path}: invalid generated preamble"
    print("APP icon preamble and editor round-trip checks passed.")


if __name__ == "__main__":
    main()
