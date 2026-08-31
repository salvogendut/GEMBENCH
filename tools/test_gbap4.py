#!/usr/bin/env python3
"""Adversarial and editor round-trip tests for GBAP v4 packages."""

from __future__ import annotations

import json
from pathlib import Path
import struct
import tempfile

from embed_app_icon import (
    APP_BASE,
    MANIFEST4_SIZE,
    SEGMENT4_ENTRY_SIZE,
    SEGMENT_EXECUTABLE,
    SEGMENT_REQUIRED,
    VERSION_V4,
    _read_v4_manifest_spec,
    _v4_crc32,
    make_v4_preamble,
    parse_icon,
    parse_manifest,
    parse_resources,
    refresh_v4_crc,
    v4_preamble_size,
    valid_preamble,
)
from iconedit import load_app_icon, save_app_icon


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "apps" / "abiprobe" / "manifest.json"
ICON_PATH = ROOT / "apps" / "abiprobe" / "icon.asm"


def recalc_crc(package: bytearray, manifest_offset: int) -> None:
    """Repair the CRC without requiring the other manifest fields to be valid."""
    struct.pack_into("<I", package, manifest_offset + 56, 0)
    struct.pack_into(
        "<I", package, manifest_offset + 56,
        _v4_crc32(package, manifest_offset),
    )


def assert_rejected(package: bytearray, label: str) -> None:
    try:
        parse_manifest(package)
    except ValueError:
        return
    raise AssertionError(f"GBAP v4 accepted malformed {label}")


def mutate_valid_crc(original: bytes, manifest_offset: int, offset: int,
                     replacement: bytes, label: str) -> None:
    broken = bytearray(original)
    broken[offset:offset + len(replacement)] = replacement
    recalc_crc(broken, manifest_offset)
    assert_rejected(broken, label)


def invalid_manifest_sources(source: dict, temp: Path) -> None:
    cases = {
        "unknown-field": {**source, "machine": "msx2"},
        "unhashable-platform": {
            **source, "platforms": [{"name": "cpc"}, "msx2", "pcw"],
        },
        "duplicate-platform": {
            **source, "platforms": ["cpc", "msx2", "msx2"],
        },
        "missing-runtime-floor": {
            **source,
            "required_capabilities": [
                name for name in source["required_capabilities"]
                if name != "runtime-geometry"
            ],
        },
        "overlapping-capability": {
            **source,
            "optional_capabilities": [
                *source["optional_capabilities"], "windows",
            ],
        },
        "boolean-pages": {**source, "minimum_pages": True},
    }
    for label, specimen in cases.items():
        path = temp / f"{label}.json"
        path.write_text(json.dumps(specimen), encoding="utf-8")
        try:
            _read_v4_manifest_spec(path)
        except ValueError:
            continue
        raise AssertionError(f"GBAP v4 accepted invalid JSON manifest {label}")


def main() -> None:
    source = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    spec = _read_v4_manifest_spec(MANIFEST_PATH)
    icon = parse_icon(ICON_PATH)
    executable = bytes((0x3E, 0x2A, 0xC9)) + bytes(range(32))
    preamble_size = v4_preamble_size(False, 1)
    primary_size = preamble_size + len(executable)
    preamble = make_v4_preamble(
        icon, spec, primary_size, primary_size,
    )
    package = bytearray(preamble + executable)
    refresh_v4_crc(package)
    original = bytes(package)

    assert package[7] == VERSION_V4
    assert len(preamble) == preamble_size
    assert valid_preamble(package)
    total, resources = parse_resources(package)
    manifest = parse_manifest(package)
    assert total == preamble_size
    assert len(resources) == 1 and resources[0]["codec"] == 1
    assert manifest["application_id"] == "ABIPROBE"
    assert manifest["minimum_abi"] == (2, 0)
    assert manifest["minimum_sysinfo"] == (6, 48)
    assert manifest["entry_offset"] == preamble_size
    assert manifest["primary_image_size"] == len(package)
    assert manifest["image_size"] == len(package)
    assert manifest["segments"] == [{
        "type": 1,
        "selector_type": 0,
        "selector_value": 0,
        "flags": SEGMENT_REQUIRED | SEGMENT_EXECUTABLE,
        "compression": 0,
        "load_address": APP_BASE,
        "offset": 0,
        "stored_length": len(package),
        "unpacked_length": len(package),
    }]

    # The packer is byte-stable for the same inputs.
    duplicate = bytearray(make_v4_preamble(
        icon, spec, primary_size, primary_size,
    ) + executable)
    refresh_v4_crc(duplicate)
    assert bytes(duplicate) == original

    manifest_offset = struct.unpack_from("<H", original, 14)[0]
    segment_offset = manifest_offset + MANIFEST4_SIZE
    corruptions = (
        (1, b"\x00", "outer entry"),
        (8, b"\x00", "resource count"),
        (manifest_offset + 6, b"\x02", "profile"),
        (manifest_offset + 7, b"\x03", "platform mask"),
        (manifest_offset + 8, b"\x01", "ABI requirement"),
        (manifest_offset + 10, b"\x05", "sysinfo requirement"),
        (manifest_offset + 14, b"\x00\x00", "required high capabilities"),
        (manifest_offset + 16, b"\x01\x00", "overlapping capabilities"),
        (manifest_offset + 20, b"a", "application identity"),
        (manifest_offset + 30, b"\x00\x00", "lifecycle"),
        (manifest_offset + 32, b"\x00", "page policy"),
        (manifest_offset + 35, b"\x13", "segment entry size"),
        (manifest_offset + 36,
         struct.pack("<H", segment_offset + 1), "segment directory offset"),
        (manifest_offset + 38,
         struct.pack("<H", preamble_size + 1), "entry offset"),
        (manifest_offset + 40,
         struct.pack("<H", len(package) - 1), "primary length"),
        (manifest_offset + 42, b"\x01", "package flags"),
        (manifest_offset + 44, b"X", "ABI identity"),
        (manifest_offset + 52,
         struct.pack("<I", len(package) + 1), "package size"),
        (manifest_offset + 60, b"\x01", "reserved manifest bytes"),
        (segment_offset, b"\x03", "primary segment type"),
        (segment_offset + 1, b"\x01", "primary selector"),
        (segment_offset + 2, b"\x01", "primary flags"),
        (segment_offset + 3, b"\x01", "primary compression"),
        (segment_offset + 6, struct.pack("<H", APP_BASE + 1),
         "primary load address"),
        (segment_offset + 8, struct.pack("<I", 1), "primary file offset"),
        (segment_offset + 12, struct.pack("<I", len(package) - 1),
         "primary stored length"),
        (segment_offset + 16, struct.pack("<I", len(package) - 1),
         "primary unpacked length"),
        (16, b"\x07", "portable icon codec"),
        (17, b"\x07", "portable icon width"),
        (18, b"\x1f", "portable icon height"),
        (19, b"\x01", "portable icon flags"),
        (20, struct.pack("<H", 255), "portable icon length"),
        (22, struct.pack("<H", preamble_size), "portable icon offset"),
    )
    for offset, replacement, label in corruptions:
        mutate_valid_crc(original, manifest_offset, offset, replacement, label)

    bad_crc = bytearray(original)
    bad_crc[-1] ^= 0x01
    assert_rejected(bad_crc, "package CRC")

    # A common executable secondary page is described with a 32-bit contiguous
    # file range and does not change the primary entry image.
    secondary_spec = dict(spec)
    secondary_spec["minimum_pages"] = 2
    secondary_spec["preferred_pages"] = 2
    secondary_spec["secondary_code"] = {
        "flags": SEGMENT_REQUIRED | SEGMENT_EXECUTABLE,
        "load_address": APP_BASE,
    }
    secondary = bytes((0xC3, 0x08, 0x40)) + b"GBS4" + bytes((1, 0xC9))
    secondary_preamble_size = v4_preamble_size(False, 2)
    secondary_primary_size = secondary_preamble_size + len(executable)
    secondary_package_size = secondary_primary_size + len(secondary)
    secondary_package = bytearray(make_v4_preamble(
        icon, secondary_spec, secondary_primary_size, secondary_package_size,
        secondary=secondary,
    ) + executable + secondary)
    refresh_v4_crc(secondary_package)
    secondary_manifest = parse_manifest(secondary_package)
    assert len(secondary_manifest["segments"]) == 2
    assert secondary_manifest["segments"][1]["offset"] == secondary_primary_size
    assert secondary_manifest["segments"][1]["stored_length"] == len(secondary)

    with tempfile.TemporaryDirectory(prefix="gbap4-test-") as dirname:
        temp = Path(dirname)
        invalid_manifest_sources(source, temp)

        app_path = temp / "ABIPROBE.APP"
        app_path.write_bytes(original)
        icons, app_data = load_app_icon(app_path)
        icons[0]["grid"][0][0] ^= 3
        save_app_icon(app_path, icons, app_data)
        edited = app_path.read_bytes()
        edited_manifest = parse_manifest(edited)
        assert edited[total:] == original[total:]
        assert edited[resources[0]["offset"]:
                      resources[0]["offset"] + resources[0]["length"]] != \
            original[resources[0]["offset"]:
                     resources[0]["offset"] + resources[0]["length"]]
        assert edited_manifest["package_crc32"] != manifest["package_crc32"]
        edited_manifest = dict(edited_manifest)
        expected_manifest = dict(manifest)
        del edited_manifest["package_crc32"]
        del expected_manifest["package_crc32"]
        assert edited_manifest == expected_manifest

    print("GBAP v4 deterministic package, corruption, and editor checks passed.")


if __name__ == "__main__":
    main()
