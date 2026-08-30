# GBAP application preamble

GEMBENCH applications may begin with an optional `GBAP` executable preamble.
The first three bytes remain a Z80 `JP` to the relocated application entry, so
the kernel continues launching every `.APP` at `#4000`. Headerless applications
remain valid and use their mapped or generic `.IST` icon.

All embedded icons are 32x32 pixels:

- codec `1`: portable four-colour CPC Mode-1 packing, 8 bytes per row and
  256 bytes total;
- codec `7`: native MSX Screen-7 packing, two four-bit pixels per byte,
  16 bytes per row and 512 bytes total.

## GBAP v1

V1 carries one codec-1 icon:

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 3 | `JP #4110` |
| 3 | 4 | ASCII `GBAP` |
| 7 | 1 | version `1` |
| 8 | 1 | codec `1` |
| 9 | 1 | packed row width `8` |
| 10 | 1 | height `32` |
| 11 | 2 | bitmap length `256` |
| 13 | 2 | bitmap offset `16` |
| 15 | 1 | reserved |
| 16 | 256 | canonical bitmap |

`APP_ICON=path/icon.asm` continues to generate this byte-identical format.
GEOBENCH-owned applications keep this source beside `main.c`.

## GBAP v2

V2 adds an explicit resource directory:

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 3 | `JP` to `#4000 + preamble size` |
| 3 | 4 | ASCII `GBAP` |
| 7 | 1 | version `2` |
| 8 | 1 | resource count |
| 9 | 1 | directory entry size, currently `8` |
| 10 | 2 | complete preamble size |
| 12 | 2 | directory offset, currently `16` |
| 14 | 2 | reserved |

Each eight-byte directory entry is:

| Entry offset | Size | Meaning |
|---:|---:|---|
| 0 | 1 | codec |
| 1 | 1 | packed row width |
| 2 | 1 | height |
| 3 | 1 | flags, currently zero |
| 4 | 2 | bitmap length |
| 6 | 2 | bitmap offset from APP start |

Entry 0 is the required codec-1 fallback. Entry 1 may be codec 7. A dual
32x32 header is 800 bytes, relocates the entry to `#4320`, and is produced with:

```sh
APP_ICON=apps/example/icon.asm \
APP_ICON16=apps/example/icon16.asm \
tools/build_capp.sh apps/example build/EXAMPLE.RAW
```

The 16-colour ASM source declares its packing explicitly:

```asm
appicon16_mode  equ 7
appicon16_w     equ 16
appicon16_h     equ 32
appicon16
                db  #12,#34
                ; ...512 bytes total
```

File Manager selects codec 7 only while the MSX is running Screen 7. MSX
Screen 6, CPC, and PCW use codec 1. All targets preserve resources they do not
display when saving an APP.

When `APP_ICON=apps/name/icon.asm` is supplied, `build_capp.sh` automatically
uses an adjacent `apps/name/icon16.asm` on MSX builds. Adding that file later is
therefore sufficient to opt an application into a native 16-colour icon. CPC
and PCW continue to embed only the canonical fallback unless `APP_ICON16` is
passed explicitly.

## GBAP v3 manifest

V3 preserves the v2 icon directory and uses header bytes 14-15 as the offset of
a platform-neutral application manifest. The on-disk order is:

1. the common 16-byte header;
2. the eight-byte icon entries;
3. one 40-byte `GBM3` manifest;
4. one or more twelve-byte typed segment descriptors;
5. the icon payloads; and
6. the fixed-origin primary image at the outer `JP` target.

The manifest is:

| Manifest offset | Size | Meaning |
|---:|---:|---|
| 0 | 4 | ASCII `GBM3` |
| 4 | 1 | manifest size, currently `40` |
| 5 | 1 | manifest version, currently `1` |
| 6 | 1 | profile: `1` target-Z80, `2` portable-Z80 |
| 7 | 1 | platform mask: bit 0 CPC, bit 1 MSX2, bit 2 PCW |
| 8 | 2 | minimum GEMBENCH ABI major/minor |
| 10 | 2 | minimum `GB_SYSINFO` version/record size |
| 12 | 2 | required `GB_CAP_*` mask |
| 14 | 8 | stable uppercase application identity, space padded |
| 22 | 2 | provided service ID, or zero |
| 24 | 2 | lifecycle flags: windowed/windowless/accessory/service |
| 26 | 1 | minimum total 16 KiB pages |
| 27 | 1 | preferred total pages |
| 28 | 1 | segment count |
| 29 | 1 | segment entry size, currently `12` |
| 30 | 2 | segment directory offset from APP start |
| 32 | 2 | primary entry offset from `#4000` |
| 34 | 2 | complete loaded image length |
| 36 | 2 | package flags, currently zero |
| 38 | 2 | reserved, zero |

Each segment descriptor is:

| Segment offset | Size | Meaning |
|---:|---:|---|
| 0 | 1 | type: primary code, secondary code, resource, or data |
| 1 | 1 | platform mask |
| 2 | 1 | required/executable/read-only flags |
| 3 | 1 | compression (`0` = none) |
| 4 | 2 | file offset |
| 6 | 2 | stored length |
| 8 | 2 | unpacked length |
| 10 | 2 | fixed load address |

Milestone 5 accepts one required, executable, uncompressed primary descriptor.
Milestone 6 optionally appends one required, executable, uncompressed MSX2
secondary-code descriptor at fixed origin `#4000`. Its file range follows the
primary exactly, ends at the manifest image size, and begins with `JP entry`,
ASCII `GBS3`, version `1`. Startup copies it into an owned purpose-7 mapper page
and calls only validated entry offsets through the fixed-RAM gate. Resource and
data descriptors remain reserved for later runtime work.

A dual-icon v3 preamble is 852 bytes and enters at `#4354`. Build one with:

```sh
APP_ICON=apps/example/icon.asm \
APP_ICON16=apps/example/icon16.asm \
APP_MANIFEST=apps/example/manifest.json \
APPDEFS="-DGB_MSX2" \
tools/build_capp.sh apps/example build/msx/EXAMPLE.RAW
```

Adding the second descriptor makes a dual-icon M6 preamble 864 bytes and moves
the primary entry to `#4360`. An M6 package supplies the secondary source and
declares its platform/load policy in the JSON manifest:

```sh
bash tools/build_secondary.sh apps/example/secondary.s build/msx/EXAMPLE.SEC
APP_ICON=apps/example/icon.asm \
APP_ICON16=apps/example/icon16.asm \
APP_MANIFEST=apps/example/manifest.json \
APP_SECONDARY=build/msx/EXAMPLE.SEC \
APPDEFS="-DGB_MSX2" \
tools/build_capp.sh apps/example build/msx/EXAMPLE.RAW
```

The JSON source names the stable identity, target or portable profile,
platforms, minimum ABI/sysinfo, required capabilities, lifecycle, and page
policy. `tools/embed_app_icon.py` validates the complete generated package
deterministically. `check` reports its identity and segment count.

On MSX2, `APP_MANIFEST` also selects the standard guarded v3 startup. It checks
the executable manifest and primary descriptor against resident `GB_SYSINFO`
before C initialization or window/application publication. A failed guard
returns directly to the existing loader, which releases the pending owner and
primary page. Headerless/v1/v2 startup is byte-for-byte unchanged. CPC/PCW v3
execution remains deferred until those targets implement equivalent capability
and page/application services.

The `portable-z80` profile is a packaging promise, not automatic portability.
A compile-once binary must additionally restrict itself to the frozen common
ABI, runtime geometry/capabilities, portable GBR/VDI data, and a common memory
layout on every platform named in its mask.

## Resident-set impact

A portable v1 APP header costs 272 bytes. Removing one 32x32 icon from an IST
saves 260 bytes: 256 bitmap bytes and its four-byte directory entry. Moving an
application icon out of both `DEFAULT.IST` and `REFINED.IST` therefore saves a
net 248 raw distribution bytes and, more importantly, 260 bytes from the icon
set kept in the kernel data page. A dual four-/sixteen-colour header costs 800
bytes, so native variants remain optional per application.

Issue #430 moved Notepad, Icon Editor, Paint, Browser, Viewer, Telnet, Mahjong,
and Shell into app-owned headers; BASIC.APP followed from its external
repository. Removing those nine application slots recovered 2,340 bytes from
the boot-loaded set. Additional system/file-type slots were added later, so the
current `DEFAULT.IST` and `REFINED.IST` each contain **21 slots** and occupy
**5,284 bytes**. Clock, Desktop, File Manager, and shared file-type/device icons
remain resident. At the format level, before application-specific code-size
reductions, moving the nine v1 icons still reduces the combined raw distribution
payload by 2,232 bytes. A dual four-/sixteen-colour v2 header costs 800 bytes;
adding the M5 manifest and primary descriptor raises that to 852 bytes.

`tools/iconedit.py` opens either ASM source and both resources inside a v2/v3 APP.
Use Previous/Next to switch variants. `ICONED.APP` edits both variants on MSX
Screen 7; on other targets and in MSX Screen 6 it exposes the portable icon and
preserves the native resource. Its whole-document ceiling is 7,168 bytes.
ICONED borrows one expansion page while a document is open; low RAM is used only
for short filesystem and editor transfers, so File Manager repaints cannot
overwrite the document.
