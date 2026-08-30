#!/usr/bin/env python3
"""Build and inspect the optional GEMBENCH GBAP application preamble.

GBAP v1 contains one canonical four-colour icon. GBAP v2 adds a resource
directory so an APP can carry both the portable four-colour icon and an
optional native MSX Screen-7 sixteen-colour variant. GBAP v3 retains that icon
directory and adds a platform-neutral application manifest plus typed segment
descriptors. Headerless, v1, and v2 applications remain valid.

The common v2/v3 header is:

    0..2    Z80 JP to the application entry point
    3..6    "GBAP"
    7       format version
    8       icon resource count
    9       directory entry size (8)
    10..11  complete preamble size, little-endian
    12..13  directory offset (16), little-endian
    14..15  reserved in v2; manifest offset in v3
    16..    icon resource directory

Each eight-byte icon entry contains codec, packed row width, height, flags,
payload length (word), and payload offset (word). Codec 1 is canonical CPC
Mode-1 packing (four pixels per byte); codec 7 is native Screen-7 packing (two
four-bit pixels per byte).

V3 places a 40-byte ``GBM3`` manifest immediately after the icon directory,
followed by twelve-byte typed segment descriptors and then the icon payloads.
The first descriptor describes the fixed-origin primary image. Architecture
Milestone 6 optionally appends one uncompressed fixed-origin secondary-code
image to the same file. The complete package still fits the existing loader;
startup copies the appended bytes into an owned mapper page before publication.
"""

import json
import re
import struct
import sys

MAGIC = b"GBAP"
VERSION_V1 = 1
VERSION_V2 = 2
VERSION_V3 = 3
CODEC_MODE1 = 1
CODEC_SCREEN7 = 7
HEADER_SIZE = 16
DIR_ENTRY_SIZE = 8
ICON_WB = 8
ICON7_WB = 16
ICON_H = 32
ICON_SIZE = ICON_WB * ICON_H
ICON7_SIZE = ICON7_WB * ICON_H
PREAMBLE_SIZE = HEADER_SIZE + ICON_SIZE
DUAL_PREAMBLE_SIZE = HEADER_SIZE + 2 * DIR_ENTRY_SIZE + ICON_SIZE + ICON7_SIZE
APP_BASE = 0x4000
ENTRY = APP_BASE + PREAMBLE_SIZE

MANIFEST_MAGIC = b"GBM3"
MANIFEST_VERSION = 1
MANIFEST_SIZE = 40
SEGMENT_ENTRY_SIZE = 12
PROFILE_TARGET_Z80 = 1
PROFILE_PORTABLE_Z80 = 2
PLATFORM_CPC = 0x01
PLATFORM_MSX2 = 0x02
PLATFORM_PCW = 0x04
SEGMENT_PRIMARY = 1
SEGMENT_SECONDARY_CODE = 2
SEGMENT_RESOURCE = 3
SEGMENT_DATA = 4
SEGMENT_REQUIRED = 0x01
SEGMENT_EXECUTABLE = 0x02
COMPRESSION_NONE = 0

PROFILES = {
    "target-z80": PROFILE_TARGET_Z80,
    "portable-z80": PROFILE_PORTABLE_Z80,
}
PLATFORMS = {
    "cpc": PLATFORM_CPC,
    "msx2": PLATFORM_MSX2,
    "pcw": PLATFORM_PCW,
}
CAPABILITIES = {
    "windows": 0x0001,
    "events": 0x0002,
    "filesystem": 0x0004,
    "shell": 0x0008,
    "network": 0x0010,
    "gbr": 0x0020,
    "page-allocator": 0x0040,
    "owner-identity": 0x0080,
    "runtime-video": 0x0100,
    "applications": 0x0200,
    "multi-window": 0x0400,
    "deferred-messages": 0x0800,
    "filesystem-contexts": 0x1000,
    "secondary-code": 0x2000,
}
LIFECYCLE = {
    "windowed": 0x0001,
    "windowless": 0x0002,
    "accessory": 0x0004,
    "service": 0x0008,
}


def _asm_value(text):
    text = text.strip()
    if text.startswith(("#", "$")):
        return int(text[1:], 16)
    if text.lower().startswith("0x"):
        return int(text[2:], 16)
    return int(text, 10)


def parse_icon(path, codec=CODEC_MODE1):
    width = height = None
    mode = 1
    data = bytearray()
    with open(path, encoding="ascii") as source:
        for line in source:
            text = line.split(";", 1)[0].strip()
            match = re.match(r"\w+_(w|h|mode)\s+equ\s+(\S+)", text,
                             re.IGNORECASE)
            if match:
                kind, value = match.groups()
                value = _asm_value(value)
                if kind.lower() == "w":
                    width = value
                elif kind.lower() == "h":
                    height = value
                else:
                    mode = value
            if re.match(r"^db\s+", text, re.IGNORECASE):
                for value in text[2:].split(","):
                    data.append(_asm_value(value))

    want_w = ICON_WB if codec == CODEC_MODE1 else ICON7_WB
    want_mode = 1 if codec == CODEC_MODE1 else 7
    want_size = want_w * ICON_H
    if codec not in (CODEC_MODE1, CODEC_SCREEN7):
        raise ValueError(f"unsupported APP icon codec {codec}")
    if (width != want_w or height != ICON_H or mode != want_mode
            or len(data) != want_size):
        description = "canonical Mode-1" if codec == CODEC_MODE1 \
            else "native MSX Screen-7"
        raise ValueError(
            f"{path}: APP icon must be a 32x32 {description} bitmap "
            f"(mode {want_mode}, {want_w}x{ICON_H} bytes); got mode {mode}, "
            f"{width}x{height}, {len(data)} bytes"
        )
    return bytes(data)


def _v1_preamble(icon):
    header = bytearray(HEADER_SIZE)
    header[0:3] = bytes((0xC3, ENTRY & 0xFF, ENTRY >> 8))
    header[3:7] = MAGIC
    header[7] = VERSION_V1
    header[8] = CODEC_MODE1
    header[9] = ICON_WB
    header[10] = ICON_H
    struct.pack_into("<HH", header, 11, ICON_SIZE, HEADER_SIZE)
    return bytes(header) + icon


def _v2_preamble(icon, icon16):
    resources = (
        (CODEC_MODE1, ICON_WB, icon),
        (CODEC_SCREEN7, ICON7_WB, icon16),
    )
    directory = bytearray(len(resources) * DIR_ENTRY_SIZE)
    payload = bytearray()
    offset = HEADER_SIZE + len(directory)
    for index, (codec, width, bitmap) in enumerate(resources):
        entry = index * DIR_ENTRY_SIZE
        directory[entry:entry + 4] = bytes((codec, width, ICON_H, 0))
        struct.pack_into("<HH", directory, entry + 4, len(bitmap), offset)
        payload.extend(bitmap)
        offset += len(bitmap)

    total = HEADER_SIZE + len(directory) + len(payload)
    header = bytearray(HEADER_SIZE)
    entry = APP_BASE + total
    header[0:3] = bytes((0xC3, entry & 0xFF, entry >> 8))
    header[3:7] = MAGIC
    header[7] = VERSION_V2
    header[8] = len(resources)
    header[9] = DIR_ENTRY_SIZE
    struct.pack_into("<HH", header, 10, total, HEADER_SIZE)
    return bytes(header + directory + payload)


def _read_manifest_spec(path):
    with open(path, encoding="utf-8") as source:
        spec = json.load(source)
    if not isinstance(spec, dict):
        raise ValueError(f"{path}: manifest root must be an object")

    app_id = spec.get("application_id", "")
    if (not isinstance(app_id, str) or not 1 <= len(app_id) <= 8
            or not re.fullmatch(r"[A-Z0-9_]+", app_id)):
        raise ValueError(
            f"{path}: application_id must be 1-8 uppercase ASCII letters, "
            "digits, or underscores"
        )
    profile_name = spec.get("profile")
    if profile_name not in PROFILES:
        raise ValueError(
            f"{path}: profile must be one of {', '.join(sorted(PROFILES))}"
        )

    platform_names = spec.get("platforms")
    if not isinstance(platform_names, list) or not platform_names:
        raise ValueError(f"{path}: platforms must be a non-empty array")
    unknown = [name for name in platform_names if name not in PLATFORMS]
    if unknown:
        raise ValueError(f"{path}: unknown platforms: {', '.join(map(str, unknown))}")
    platform_mask = 0
    for name in platform_names:
        platform_mask |= PLATFORMS[name]
    if (profile_name == "portable-z80"
            and platform_mask & (platform_mask - 1) == 0):
        raise ValueError(
            f"{path}: portable-z80 must name at least two targets"
        )

    minimum_abi = spec.get("minimum_abi", [1, 0])
    minimum_sysinfo = spec.get("minimum_sysinfo", [1, 20])
    for key, pair in (("minimum_abi", minimum_abi),
                      ("minimum_sysinfo", minimum_sysinfo)):
        if (not isinstance(pair, list) or len(pair) != 2
                or any(not isinstance(value, int) or not 0 <= value <= 255
                       for value in pair)):
            raise ValueError(f"{path}: {key} must contain two bytes")

    capability_names = spec.get("required_capabilities", [])
    lifecycle_names = spec.get("lifecycle", ["windowed"])
    if not isinstance(capability_names, list):
        raise ValueError(f"{path}: required_capabilities must be an array")
    if not isinstance(lifecycle_names, list) or not lifecycle_names:
        raise ValueError(f"{path}: lifecycle must be a non-empty array")
    capabilities = 0
    lifecycle = 0
    try:
        for name in capability_names:
            capabilities |= CAPABILITIES[name]
        for name in lifecycle_names:
            lifecycle |= LIFECYCLE[name]
    except (KeyError, TypeError) as error:
        raise ValueError(f"{path}: unknown manifest name {error.args[0]!r}") from None

    service_id = spec.get("service_id", 0)
    minimum_pages = spec.get("minimum_pages", 1)
    preferred_pages = spec.get("preferred_pages", minimum_pages)
    if not isinstance(service_id, int) or not 0 <= service_id <= 0xFFFF:
        raise ValueError(f"{path}: service_id must be a 16-bit integer")
    if (not isinstance(minimum_pages, int) or not 1 <= minimum_pages <= 255
            or not isinstance(preferred_pages, int)
            or not minimum_pages <= preferred_pages <= 255):
        raise ValueError(
            f"{path}: page counts must satisfy 1 <= minimum_pages <= "
            "preferred_pages <= 255"
        )
    secondary = spec.get("secondary_code")
    secondary_spec = None
    if secondary is not None:
        if not isinstance(secondary, dict):
            raise ValueError(f"{path}: secondary_code must be an object")
        unknown_keys = set(secondary) - {"platforms", "required", "load_address"}
        if unknown_keys:
            raise ValueError(
                f"{path}: unknown secondary_code fields: "
                f"{', '.join(sorted(unknown_keys))}"
            )
        secondary_platforms = secondary.get("platforms", platform_names)
        if (not isinstance(secondary_platforms, list)
                or not secondary_platforms):
            raise ValueError(
                f"{path}: secondary_code platforms must be a non-empty array"
            )
        unknown = [name for name in secondary_platforms if name not in PLATFORMS]
        if unknown:
            raise ValueError(
                f"{path}: unknown secondary_code platforms: "
                f"{', '.join(map(str, unknown))}"
            )
        secondary_mask = 0
        for name in secondary_platforms:
            secondary_mask |= PLATFORMS[name]
        if secondary_mask & ~platform_mask:
            raise ValueError(
                f"{path}: secondary_code platforms must be in the package mask"
            )
        required = secondary.get("required", True)
        load_address = secondary.get("load_address", APP_BASE)
        if not isinstance(required, bool):
            raise ValueError(f"{path}: secondary_code required must be boolean")
        if not required:
            raise ValueError(f"{path}: M6 secondary_code must be required")
        if load_address != APP_BASE:
            raise ValueError(
                f"{path}: M6 secondary_code load_address must be 0x4000"
            )
        secondary_spec = {
            "platforms": secondary_mask,
            "flags": SEGMENT_EXECUTABLE | SEGMENT_REQUIRED,
            "load_address": load_address,
        }

    return {
        "application_id": app_id,
        "profile": PROFILES[profile_name],
        "platforms": platform_mask,
        "minimum_abi": tuple(minimum_abi),
        "minimum_sysinfo": tuple(minimum_sysinfo),
        "required_capabilities": capabilities,
        "service_id": service_id,
        "lifecycle": lifecycle,
        "minimum_pages": minimum_pages,
        "preferred_pages": preferred_pages,
        "secondary_code": secondary_spec,
    }


def _v3_layout(icon_count, segment_count=1):
    manifest_offset = HEADER_SIZE + icon_count * DIR_ENTRY_SIZE
    segment_offset = manifest_offset + MANIFEST_SIZE
    payload_offset = segment_offset + segment_count * SEGMENT_ENTRY_SIZE
    return manifest_offset, segment_offset, payload_offset


def v3_preamble_size(icon16=False, segment_count=1):
    count = 2 if icon16 else 1
    _, _, payload_offset = _v3_layout(count, segment_count)
    return payload_offset + ICON_SIZE + (ICON7_SIZE if icon16 else 0)


def _v3_preamble(icon, icon16, spec, primary_size, secondary=None):
    resources = [(CODEC_MODE1, ICON_WB, icon)]
    if icon16 is not None:
        resources.append((CODEC_SCREEN7, ICON7_WB, icon16))
    secondary_spec = spec["secondary_code"]
    if (secondary_spec is None) != (secondary is None):
        raise ValueError(
            "manifest secondary_code and supplied secondary payload must agree"
        )
    segment_count = 1 + (1 if secondary is not None else 0)
    manifest_offset, segment_offset, payload_offset = _v3_layout(
        len(resources), segment_count
    )
    total = payload_offset + sum(len(bitmap) for _, _, bitmap in resources)
    secondary_size = len(secondary) if secondary is not None else 0
    image_size = primary_size + secondary_size
    if (primary_size < total or image_size > 0xFFFF
            or secondary is not None and not secondary):
        raise ValueError("linked image has an invalid GBAP v3 length")
    if (secondary is not None
            and (len(secondary) < 8 or secondary[0] != 0xC3
                 or secondary[3:7] != b"GBS3" or secondary[7] != 1)):
        raise ValueError("secondary payload lacks the GBS3 v1 entry prefix")

    directory = bytearray(len(resources) * DIR_ENTRY_SIZE)
    payload = bytearray()
    offset = payload_offset
    for index, (codec, width, bitmap) in enumerate(resources):
        pos = index * DIR_ENTRY_SIZE
        directory[pos:pos + 4] = bytes((codec, width, ICON_H, 0))
        struct.pack_into("<HH", directory, pos + 4, len(bitmap), offset)
        payload.extend(bitmap)
        offset += len(bitmap)

    manifest = bytearray(MANIFEST_SIZE)
    manifest[0:4] = MANIFEST_MAGIC
    manifest[4:8] = bytes((MANIFEST_SIZE, MANIFEST_VERSION,
                           spec["profile"], spec["platforms"]))
    manifest[8:12] = bytes((*spec["minimum_abi"],
                            *spec["minimum_sysinfo"]))
    struct.pack_into("<H", manifest, 12, spec["required_capabilities"])
    manifest[14:22] = spec["application_id"].encode("ascii").ljust(8, b" ")
    struct.pack_into("<HH", manifest, 22, spec["service_id"], spec["lifecycle"])
    manifest[26:30] = bytes((spec["minimum_pages"], spec["preferred_pages"],
                             segment_count, SEGMENT_ENTRY_SIZE))
    struct.pack_into("<HHHH", manifest, 30, segment_offset, total, image_size, 0)

    segments = bytearray(segment_count * SEGMENT_ENTRY_SIZE)
    segments[0:4] = bytes((SEGMENT_PRIMARY, spec["platforms"],
                           SEGMENT_REQUIRED | SEGMENT_EXECUTABLE,
                           COMPRESSION_NONE))
    code_length = primary_size - total
    struct.pack_into("<HHHH", segments, 4, total, code_length, code_length,
                     APP_BASE + total)
    if secondary is not None:
        pos = SEGMENT_ENTRY_SIZE
        segments[pos:pos + 4] = bytes((
            SEGMENT_SECONDARY_CODE, secondary_spec["platforms"],
            secondary_spec["flags"], COMPRESSION_NONE,
        ))
        struct.pack_into(
            "<HHHH", segments, pos + 4, primary_size, secondary_size,
            secondary_size, secondary_spec["load_address"]
        )

    header = bytearray(HEADER_SIZE)
    entry = APP_BASE + total
    header[0:3] = bytes((0xC3, entry & 0xFF, entry >> 8))
    header[3:7] = MAGIC
    header[7:10] = bytes((VERSION_V3, len(resources), DIR_ENTRY_SIZE))
    struct.pack_into("<HHH", header, 10, total, HEADER_SIZE, manifest_offset)
    return bytes(header + directory + manifest + segments + payload)


def make_preamble(icon, icon16=None):
    if len(icon) != ICON_SIZE:
        raise ValueError("invalid four-colour APP icon length")
    if icon16 is None:
        return _v1_preamble(icon)
    if len(icon16) != ICON7_SIZE:
        raise ValueError("invalid sixteen-colour APP icon length")
    return _v2_preamble(icon, icon16)


def make_v3_preamble(icon, manifest, primary_size, icon16=None, secondary=None):
    if len(icon) != ICON_SIZE:
        raise ValueError("invalid four-colour APP icon length")
    if icon16 is not None and len(icon16) != ICON7_SIZE:
        raise ValueError("invalid sixteen-colour APP icon length")
    return _v3_preamble(icon, icon16, manifest, primary_size, secondary)


def _parse_package(data):
    if len(data) < HEADER_SIZE or data[0] != 0xC3 or data[3:7] != MAGIC:
        raise ValueError("missing GBAP executable preamble")
    version = data[7]
    if version == VERSION_V1:
        if len(data) < PREAMBLE_SIZE:
            raise ValueError("truncated GBAP v1 preamble")
        if (data[1] != (ENTRY & 0xFF) or data[2] != (ENTRY >> 8)
                or data[8] != CODEC_MODE1 or data[9] != ICON_WB
                or data[10] != ICON_H
                or struct.unpack_from("<H", data, 11)[0] != ICON_SIZE
                or struct.unpack_from("<H", data, 13)[0] != HEADER_SIZE):
            raise ValueError("invalid GBAP v1 metadata")
        return PREAMBLE_SIZE, [{
            "codec": CODEC_MODE1, "wbytes": ICON_WB, "height": ICON_H,
            "length": ICON_SIZE, "offset": HEADER_SIZE,
        }], None
    if version not in (VERSION_V2, VERSION_V3):
        raise ValueError(f"unsupported GBAP version {version}")

    count = data[8]
    entry_size = data[9]
    total, directory_offset = struct.unpack_from("<HH", data, 10)
    if (count == 0 or count > 8 or entry_size != DIR_ENTRY_SIZE
            or directory_offset != HEADER_SIZE
            or total < HEADER_SIZE + count * DIR_ENTRY_SIZE
            or len(data) < total):
        raise ValueError(f"invalid GBAP v{version} header")
    entry = APP_BASE + total
    if data[1] != (entry & 0xFF) or data[2] != (entry >> 8):
        raise ValueError(f"GBAP v{version} entry point does not follow its preamble")

    manifest = None
    resource_floor = directory_offset + count * entry_size
    if version == VERSION_V3:
        manifest_offset = struct.unpack_from("<H", data, 14)[0]
        if manifest_offset != resource_floor or manifest_offset + MANIFEST_SIZE > total:
            raise ValueError("invalid GBAP v3 manifest offset")
        block = data[manifest_offset:manifest_offset + MANIFEST_SIZE]
        if (block[0:4] != MANIFEST_MAGIC or block[4] != MANIFEST_SIZE
                or block[5] != MANIFEST_VERSION
                or block[6] not in (PROFILE_TARGET_Z80, PROFILE_PORTABLE_Z80)
                or not block[7] or block[7] & ~0x07
                or (block[6] == PROFILE_PORTABLE_Z80
                    and block[7] & (block[7] - 1) == 0)):
            raise ValueError("invalid GBAP v3 manifest prefix")
        segment_count, segment_size = block[28], block[29]
        segment_offset, entry_offset, image_size, flags = struct.unpack_from(
            "<HHHH", block, 30
        )
        if (segment_count == 0 or segment_count > 8
                or segment_size != SEGMENT_ENTRY_SIZE
                or segment_offset != manifest_offset + MANIFEST_SIZE
                or segment_offset + segment_count * segment_size > total
                or entry_offset != total or image_size != len(data) or flags
                or block[38] or block[39]):
            raise ValueError("invalid GBAP v3 manifest bounds")
        capabilities = struct.unpack_from("<H", block, 12)[0]
        lifecycle = struct.unpack_from("<H", block, 24)[0]
        if (capabilities & ~0x3FFF or not lifecycle or lifecycle & ~0x000F
                or block[26] == 0 or block[27] < block[26]
                or not bytes(block[14:22]).strip(b" ")
                or any(value not in range(0x20, 0x7F) for value in block[14:22])):
            raise ValueError("invalid GBAP v3 identity or page policy")

        segments = []
        primary = 0
        secondary = 0
        occupied_segments = []
        for index in range(segment_count):
            pos = segment_offset + index * segment_size
            kind, platforms, segflags, compression = data[pos:pos + 4]
            file_offset, stored, unpacked, load_address = struct.unpack_from(
                "<HHHH", data, pos + 4
            )
            if (kind not in (SEGMENT_PRIMARY, SEGMENT_SECONDARY_CODE,
                             SEGMENT_RESOURCE, SEGMENT_DATA)
                    or not platforms or platforms & ~block[7]
                    or segflags & ~0x07
                    or compression != COMPRESSION_NONE or stored != unpacked
                    or not stored or file_offset < total
                    or file_offset + stored > image_size):
                raise ValueError(f"invalid GBAP v3 segment {index}")
            if any(file_offset < end and file_offset + stored > start
                   for start, end in occupied_segments):
                raise ValueError("overlapping GBAP v3 segments")
            occupied_segments.append((file_offset, file_offset + stored))
            if kind == SEGMENT_PRIMARY:
                primary += 1
                required_exec = SEGMENT_REQUIRED | SEGMENT_EXECUTABLE
                if ((segflags & required_exec) != required_exec
                        or file_offset != total
                        or load_address != APP_BASE + total):
                    raise ValueError("invalid GBAP v3 primary segment")
            elif kind == SEGMENT_SECONDARY_CODE:
                secondary += 1
                required_exec = SEGMENT_REQUIRED | SEGMENT_EXECUTABLE
                if ((segflags & required_exec) != required_exec
                        or load_address != APP_BASE or stored < 8
                        or data[file_offset] != 0xC3
                        or data[file_offset + 3:file_offset + 7] != b"GBS3"
                        or data[file_offset + 7] != 1):
                    raise ValueError("invalid GBAP v3 secondary-code segment")
            segments.append({
                "type": kind, "platforms": platforms, "flags": segflags,
                "compression": compression, "offset": file_offset,
                "stored_length": stored, "unpacked_length": unpacked,
                "load_address": load_address,
            })
        if primary != 1 or secondary > 1:
            raise ValueError(
                "GBAP v3 requires one primary and at most one secondary-code segment"
            )
        occupied_segments.sort()
        cursor = total
        for start, end in occupied_segments:
            if start != cursor:
                raise ValueError("GBAP v3 segment image is not contiguous")
            cursor = end
        if cursor != image_size:
            raise ValueError("GBAP v3 segments do not cover the package image")
        resource_floor = segment_offset + segment_count * segment_size
        manifest = {
            "profile": block[6], "platforms": block[7],
            "minimum_abi": tuple(block[8:10]),
            "minimum_sysinfo": tuple(block[10:12]),
            "required_capabilities": capabilities,
            "application_id": bytes(block[14:22]).decode("ascii").rstrip(),
            "service_id": struct.unpack_from("<H", block, 22)[0],
            "lifecycle": lifecycle,
            "minimum_pages": block[26], "preferred_pages": block[27],
            "entry_offset": entry_offset, "image_size": image_size,
            "segments": segments,
        }

    resources = []
    occupied = []
    for index in range(count):
        pos = directory_offset + index * entry_size
        codec, width, height, flags = data[pos:pos + 4]
        length, offset = struct.unpack_from("<HH", data, pos + 4)
        expected_width = ICON_WB if codec == CODEC_MODE1 else \
            ICON7_WB if codec == CODEC_SCREEN7 else 0
        if (not expected_width or width != expected_width or height != ICON_H
                or flags != 0 or length != width * height
                or offset < resource_floor or offset + length > total):
            raise ValueError(f"invalid GBAP v{version} resource {index}")
        if any(offset < end and offset + length > start
               for start, end in occupied):
            raise ValueError(f"overlapping GBAP v{version} resources")
        occupied.append((offset, offset + length))
        resources.append({
            "codec": codec, "wbytes": width, "height": height,
            "length": length, "offset": offset,
        })
    if resources[0]["codec"] != CODEC_MODE1:
        raise ValueError(
            f"GBAP v{version} resource 0 must be the portable four-colour icon"
        )
    if len({item["codec"] for item in resources}) != len(resources):
        raise ValueError(f"duplicate GBAP v{version} icon codec")
    return total, resources, manifest


def parse_resources(data):
    """Return (preamble_size, icon resource dictionaries), or raise ValueError."""
    total, resources, _ = _parse_package(data)
    return total, resources


def parse_manifest(data):
    """Return the GBAP v3 manifest dictionary, or raise ValueError."""
    _, _, manifest = _parse_package(data)
    if manifest is None:
        raise ValueError("application does not carry a GBAP v3 manifest")
    return manifest


def valid_preamble(data):
    try:
        parse_resources(data)
        return True
    except (ValueError, struct.error):
        return False


def inject(icon_path, raw_path, out_path, icon16_path=None):
    icon = parse_icon(icon_path, CODEC_MODE1)
    icon16 = parse_icon(icon16_path, CODEC_SCREEN7) if icon16_path else None
    preamble = make_preamble(icon, icon16)
    with open(raw_path, "rb") as source:
        raw = bytearray(source.read())
    if len(raw) < len(preamble):
        raise ValueError(f"{raw_path}: linked image is shorter than the APP preamble")
    padding = raw[:len(preamble)]
    if padding[0] not in (0x00, 0xFF) or any(value != padding[0] for value in padding):
        raise ValueError(
            f"{raw_path}: linked image does not reserve {len(preamble)} bytes at 0x4000"
        )
    raw[:len(preamble)] = preamble
    with open(out_path, "wb") as target:
        target.write(raw)


def inject_v3(manifest_path, icon_path, raw_path, out_path, icon16_path=None,
              secondary_path=None):
    icon = parse_icon(icon_path, CODEC_MODE1)
    icon16 = parse_icon(icon16_path, CODEC_SCREEN7) if icon16_path else None
    manifest = _read_manifest_spec(manifest_path)
    with open(raw_path, "rb") as source:
        raw = bytearray(source.read())
    secondary = None
    if secondary_path:
        with open(secondary_path, "rb") as source:
            secondary = source.read()
    preamble = make_v3_preamble(
        icon, manifest, len(raw), icon16, secondary
    )
    if len(raw) < len(preamble):
        raise ValueError(f"{raw_path}: linked image is shorter than the APP preamble")
    padding = raw[:len(preamble)]
    if padding[0] not in (0x00, 0xFF) or any(value != padding[0] for value in padding):
        raise ValueError(
            f"{raw_path}: linked image does not reserve {len(preamble)} bytes at 0x4000"
        )
    raw[:len(preamble)] = preamble
    package = raw + (secondary or b"")
    parse_manifest(package)
    with open(out_path, "wb") as target:
        target.write(package)


def main(argv):
    if argv[1:2] == ["size"] and len(argv) in (3, 4):
        icon = parse_icon(argv[2], CODEC_MODE1)
        icon16 = parse_icon(argv[3], CODEC_SCREEN7) if len(argv) == 4 else None
        print(len(make_preamble(icon, icon16)))
        return
    if argv[1:2] == ["size-v3"] and len(argv) in (4, 5):
        manifest = _read_manifest_spec(argv[2])
        parse_icon(argv[3], CODEC_MODE1)
        if len(argv) == 5:
            parse_icon(argv[4], CODEC_SCREEN7)
        segment_count = 1 + (manifest["secondary_code"] is not None)
        print(v3_preamble_size(len(argv) == 5, segment_count))
        return
    if argv[1:2] == ["inject"] and len(argv) in (5, 6):
        if len(argv) == 5:
            inject(argv[2], argv[3], argv[4])
        else:
            inject(argv[2], argv[4], argv[5], argv[3])
        return
    if argv[1:2] == ["inject-v3"]:
        args = argv[2:]
        secondary_path = None
        if "--secondary" in args:
            index = args.index("--secondary")
            if index + 1 >= len(args):
                raise ValueError("--secondary requires a payload path")
            secondary_path = args[index + 1]
            del args[index:index + 2]
        if len(args) == 4:
            inject_v3(args[0], args[1], args[2], args[3],
                      secondary_path=secondary_path)
        elif len(args) == 5:
            inject_v3(args[0], args[1], args[3], args[4], args[2],
                      secondary_path)
        else:
            raise ValueError("invalid inject-v3 arguments")
        return
    if argv[1:2] == ["check"] and len(argv) == 3:
        with open(argv[2], "rb") as source:
            data = source.read()
        total, resources = parse_resources(data)
        codecs = "/".join(str(item["codec"]) for item in resources)
        detail = ""
        if data[7] == VERSION_V3:
            manifest = parse_manifest(data)
            detail = (f", app {manifest['application_id']}, "
                      f"segments {len(manifest['segments'])}")
        print(f"{argv[2]}: GBAP v{data[7]}, codecs {codecs}{detail}, "
              f"entry 0x{APP_BASE + total:04X}")
        return
    raise SystemExit(
        "usage: embed_app_icon.py size <icon4.asm> [icon16.asm]\n"
        "       embed_app_icon.py inject <icon4.asm> [icon16.asm] "
        "<linked.raw> <out.APP>\n"
        "       embed_app_icon.py size-v3 <manifest.json> <icon4.asm> "
        "[icon16.asm]\n"
        "       embed_app_icon.py inject-v3 <manifest.json> <icon4.asm> "
        "[icon16.asm] <linked.raw> <out.APP> "
        "[--secondary <segment.raw>]\n"
        "       embed_app_icon.py check <file.APP>"
    )


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (IndexError, OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(error)
