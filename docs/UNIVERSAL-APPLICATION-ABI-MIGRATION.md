# Universal application ABI migration plan

This plan implements the experimental GEOBENCH-2 ABI in
[`UNIVERSAL-APPLICATION-ABI.md`](UNIVERSAL-APPLICATION-ABI.md). Issue #54 (CPC
reintegration) remains parked until the common SDK, loader contract, and proof
application exist, so the CPC port does not recreate target-specific app builds.

## Gate 0: accept and freeze the proposal

Status: complete for the experimental implementation. The major version remains
unfrozen until the MSX2 and CPC reference kernels run the identical proof file.

- Review `abi/geobench-v2.json`, especially the common `#4000-#7EFF` image,
  four-pixel columns, semantic PCW rendering, v6 sysinfo suffix, and GBAP v4.
- Resolve changes in the proposal rather than in three kernel ports.
- Change the authority from `proposed` to `experimental` only when the first
  implementation lands. Freeze major version 2 only after MSX2 and CPC run the
  same proof artifact.

Exit: the design checker passes and issue #55 records the accepted choices.

## Gate 1: universal SDK and package tools

Status: implemented for host conformance in issue #56. Run
`make geobench-v2-sdk-check`; it produces
`build/universal/ABIPROBE.APP`. The artifact is deliberately not staged into
MSX media until the transactional Gate-2 loader exists.

- Add `GB_UNIVERSAL` libgb headers and one common trampoline set.
- Replace public compile-time extents with sysinfo-backed accessors such as
  `gb_screen_columns()`, `gb_screen_lines()`, and `gb_screen_width_pixels()`.
- Hide the documented resident mailbox behind accessors; expose no other
  low-RAM or page-3 address.
- Add a portable line/surface path where current applications touch firmware,
  VDP glue, or a framebuffer.
- Extend `embed_app_icon.py` (or a dedicated packer) to emit and validate GBAP
  v4, 64-byte GBM4 manifests, 20-byte segments, and CRC-32.
- Add a source/map audit that rejects target defines, firmware/BIOS calls,
  direct I/O, framebuffer ranges, and unapproved absolute kernel calls in a
  universal build.

Exit: one host command deterministically produces a valid v4 artifact twice
with the same hash, and malformed-package tests cover every offset/length edge.

## Gate 2: MSX2 reference implementation

Status: implemented by issue #58 for the mandatory primary-only package
profile. Portable filesystem/package-resource capability bits and external v4
segments remain intentionally unadvertised for a later gate.

- Append the v6 sysinfo suffix without changing its 32-byte prefix.
- Make the current MSX slots through `GB_FSCTX` unconditional at their fixed
  addresses and give every optional service a typed unsupported result.
- Implement transactional GBAP v4 validation/loading and the universal startup
  guard.
- Normalise rectangle buffers and graphics calls to semantic pen packing even
  when Screen 7 uses a native renderer internally.
- Do not advertise universal capability bits until all MSX conformance tests
  pass.

Start with a small responsive-window proof rather than a synthetic return-only
program. It must use runtime geometry, text/fill/frame, input, managed repaint,
filesystem load/save, owner identity, and clean close. Calculator or a reduced
Notepad is a suitable first candidate.

Exit: openMSX and 1983 run `build/universal/ABIPROBE.APP`; rejection tests leak
no mapper pages, windows, owners, or filesystem contexts.

## Gate 3: CPC reintegration against the ABI

- Resume issue #54 from its parked branch, rebasing only after the v2 SDK is
  stable.
- Restore the CPC kernel, M4/Albireo CARD staging, and 512 KiB bank allocator,
  but do not restore per-target application compilation.
- Provide all 71 inherited slots, sysinfo v6, opaque owner/page/application
  services, capability-typed stubs, canonical rectangle packing, and the v4
  loader.
- Render four semantic pens in CPC Mode 1 and calculate the 80x200 logical
  geometry at runtime.
- Copy the already-built universal proof `.APP` into the CPC image.

Exit: the MSX2 and CPC media contain byte-identical proof files (verified by
SHA-256), and the same interaction script passes in openMSX/1983 and 1984.

This is the point at which GEOBENCH-2 major version 2 can be frozen. Until then,
the manifest is experimental and no compatibility claim is made outside the
development branches.

## Gate 4: migrate ordinary applications by dependency tier

Move applications only when their source passes the universal audit:

1. **Portable UI:** Calculator, GBR demo/FormRef, Notepad, Clock after the line
   helper, and similarly conventional managed-window apps.
2. **Portable storage and shell:** File Manager, Settings, document workflows,
   clipboard, drag-and-drop, and service clients.
3. **Paged/resource-heavy:** Viewer, Icon Editor, BASIC, secondary-code apps,
   and multi-page documents.
4. **Hardware-bound:** Paint, Telnet/browser networking, graphics savers, sound,
   and diagnostic tools. These need real portable services or remain explicitly
   target-specific; preprocessor branches are not accepted as a universal port.

GB-PAINT is the decisive multi-window proof. Its common source must stop
touching mapper tables, platform line mailboxes, firmware, and native picture
banks. Canvas storage becomes a canonical document surface accessed through
portable page/resource operations. Only after that refactor should PAINT be
labelled GBAP v4 universal.

Exit: distribution assembly copies universal apps from one build directory;
there are no `build/msx/APP.RAW` versus `build/cpc/APP.RAW` variants for migrated
apps.

## Gate 5: PCW kernel and monochrome proof

- Restore the PCW target on top of the frozen v2 ABI, with at least 512 KiB RAM.
- Keep the same `#4000` app page, `#8000` table, v6 sysinfo, loader transaction,
  handle model, and package hash.
- Translate semantic pens and canonical two-bit rectangle buffers to the PCW
  one-bit display with stable, position-independent dither.
- Ensure damage/repaint clipping is performed in logical coordinates before
  monochrome conversion, so partial windows do not flash or corrupt overlays.
- Copy the existing MSX2/CPC universal artifacts; do not invoke the C compiler.

Exit: the proof and tier-1 applications have the same SHA-256 on all three
media and pass equivalent input, focus, damage, file, and lifecycle checks.

## Release acceptance matrix

| Requirement | MSX2 | CPC | PCW |
|---|:---:|:---:|:---:|
| 512 KiB bank/page pool | required | required | required |
| all inherited slots physically present | required | required | required |
| v6 sysinfo, unchanged v5 prefix | required | required | required |
| transactional GBAP v4 loader | required | required | required |
| runtime geometry | 128x212 | 80x200 | 90x248 |
| four semantic pens | palette | palette | monochrome/dither |
| canonical save/restore rectangles | required | required | required |
| identical universal `.APP` hash | required | required | required |
| legacy target apps still load | required | required | required |

No target may set `GB_CAP_UNIVERSAL_LOADER` merely because it recognises the
magic. The complete loader transaction, v6 record, portable drawing/input
semantics, and byte-identical artifact test are the minimum claim.
