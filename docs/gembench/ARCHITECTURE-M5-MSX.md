# Architecture Milestone 5: MSX2 GBAP v3 manifests

Status: **implemented on the MSX2 target in issue
[#39](https://github.com/salvogendut/GEMBENCH/issues/39)**.

Milestone 5 implements the uncompressed-primary slice of improvement 6 from the SymbOS-inspired architecture
review. It turns GBAP from an optional icon header into a versioned application
package contract while preserving headerless, v1, and v2 applications. The
format is platform-neutral; guarded execution is deliberately MSX2-only in
this milestone.

## Package contract

GBAP v3 retains the outer Z80 `JP` and v2 icon directory, then adds a fixed
40-byte `GBM3` manifest and twelve-byte typed segment descriptors. It records:

- target-Z80 or portable-Z80 profile and a CPC/MSX2/PCW platform mask;
- minimum GEMBENCH ABI and `GB_SYSINFO` contract;
- required capabilities;
- stable eight-character application identity and optional service ID;
- windowed, windowless, accessory, and service lifecycle flags;
- minimum and preferred 16 KiB page counts;
- entry, complete image length, and typed primary/secondary/resource/data
  segment bounds; and
- stored/unpacked lengths, compression, flags, and fixed load addresses.

The M5 loader accepts exactly one uncompressed fixed-origin primary segment.
The descriptor vocabulary is intentionally wider so future mapper-backed
resources and the secondary-code call gate do not require GBAP v4. ZX0,
secondary execution, and relocation were not implemented or advertised in M5;
Milestone 6 now activates one optional MSX2 secondary-code descriptor without
changing the M5 primary-only package contract.

`tools/embed_app_icon.py` is the canonical generator and strict parser. Its
source JSON validation rejects unknown names, invalid identities, page-policy
inversions, and unsupported profiles. Its finished-package pass rejects bad
entry/image bounds, overlapping icon or segment payloads, compression/length
mismatches, duplicate codecs, and anything other than one valid M5 primary.

## Guarded MSX2 publication

The Screen-7 resident kernel remains 16,125/16,128 bytes, so adding even one
jump is unsafe. V3 applications instead link `crt0_v3_msx.s` as their standard
entry. The primary page must first be allocated and loaded so the manifest is
available; before global initialization or `main`, the guard validates:

- v3/`GBM3` identity and deterministic manifest placement;
- MSX2 platform availability;
- manifest/segment directory, entry, image, and primary bounds;
- uncompressed required/executable primary semantics;
- minimum sysinfo size/version and ABI;
- required capabilities; and
- minimum pages using current free pages plus the already loaded primary.

Only a successful guard reaches application code. On failure it returns to the
existing `wm_open_go` transaction without registering or publishing a window.
That loader already releases the pending generation-tagged owner and its
primary page, restores the caller mapping, and leaves focus/z-order unchanged.
Thus rejection is pre-publication and rollback requires no new resident state.

This is compatibility validation, not a secure executable sandbox. Legacy
headerless/v1/v2 applications already execute arbitrary code at their first
byte, and a corrupted outer JP can bypass any app-resident guard. Distribution
and installation tooling must therefore continue using the strict host parser.

## First application

MSX2 `FORMREF.APP` is the v3 reference package:

- stable identity `FORMREF`;
- target-Z80 profile and MSX2 platform mask;
- ABI 1.0 and the stable 20-byte sysinfo prefix;
- windows, events, GBR, runtime-video, and application capabilities;
- windowed lifecycle and one required/preferred page; and
- one uncompressed primary descriptor.

Its dual icon/manifest preamble is 852 bytes and enters at `0x4354`. The
strict finished package is 16,120 bytes, 8 bytes below the unchanged MSX
loader ceiling. Moving FormRef data to `0x7F00` leaves its 79 data/initializer/
BSS bytes below `0x8000`. CPC and PCW FormRef builds remain v2 and retain their
existing startup and application code.

File Manager, the in-system Icon Editor, the paged APP picker, and the host icon
editor recognize the shared v2/v3 icon directory. Editing a v3 icon preserves
the manifest, segment directory, and executable byte-for-byte.

## Validation

```sh
make gembench-m5-manifest
python3 tools/test_appicon.py
make geobench-msx
make gembench-m5-openmsx
```

Host tests round-trip v1, v2, and v3 through the icon editor and reject corrupt
version, platform, image-length, and compression fields. The openMSX test
launches FormRef through the real Desktop application path, then repeats with
its platform mask zeroed. The valid package reaches `main` and adds one
owner/page/window. The incompatible package reaches the guard but not `main`;
window/owner counts remain at one, the free-page count returns exactly to its
initial value, and the pending owner is zero.

## Portability boundary and follow-up

V3 makes compile-once applications representable, not automatic. A true
`portable-z80` package must use only the frozen common ABI, runtime
geometry/capabilities, portable GBR/VDI resources, and an agreed fixed memory
layout on every target in its mask. CPC/PCW still need the M1-M5 service
backports before they can truthfully accept such a binary.

Architecture Milestone 6 implements the application-owned secondary-code call
gate against these descriptor/owner/page contracts, initially on MSX2 and
without expanding the primary application into a relocatable model. See
[ARCHITECTURE-M6-MSX.md](ARCHITECTURE-M6-MSX.md).
