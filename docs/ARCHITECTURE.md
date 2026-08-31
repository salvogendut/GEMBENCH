# GEOBENCH architecture

GEOBENCH is currently an MSX2-only banked desktop. The detailed evolution of
its GEM-like services is recorded under the historical `docs/gembench/`
namespace; this document describes the active runtime and build boundaries.
The experimental compile-once MSX2/CPC/PCW boundary is separate and documented in
[UNIVERSAL-APPLICATION-ABI.md](UNIVERSAL-APPLICATION-ABI.md).

## Memory and ownership

The resident kernel starts at `0x8000`. Applications execute in a 16 KiB mapper
window at `0x4000–0x7FFF`; kernel, low-RAM contracts, and page-3 state remain
visible while application and resource segments are switched.

Mapper pages and application owners are independent objects. Generation-tagged
handles prevent stale page, window, filesystem-context, secondary-resource, and
service references from acting on reused slots. One application can own several
windows and one optional pure worker.

## Kernel

`kernel/gbkern.asm` assembles the MSX2 kernel and fixed API table. Platform code
is under `lib/msx/` and `kernel/*_msx.asm`:

- V9938/V9958 Screen 6 and Screen 7 rendering;
- hardware-sprite pointer and MSX input polling;
- MSX-DOS 2/Nextor filesystem operations;
- mapper segment allocation and page switching;
- H.TIMI-paced clock and preemptive worker scheduling.

The production build is `tools/build_kernel_msx.sh`. No CPC or PCW builder or
release media exists in the active tree yet; see [MSX2-ONLY.md](MSX2-ONLY.md).

## Applications and ABI

Applications are SDCC C programs linked with assembly trampolines from
`lib/gb/gblib.s`. They enter at `0x4000` through a guarded GBAP package and call
the fixed kernel jump table at `0x8000`. The frozen public contracts are
documented in [gembench/ABI-V1.md](gembench/ABI-V1.md).

`tools/build_capp.sh` requires `-DGB_MSX2`. Optional link profiles add bounded
documents, widgets, GBR objects/forms/menus, VDI-lite drawing, typed scrap,
shell discovery, deferred messages, filesystem contexts, shared services,
secondary resources, and timers.

GEOBENCH-2 has an experimental `GB_UNIVERSAL` SDK, runtime-geometry accessors,
a v6 sysinfo C record, a guarded startup, and a deterministic GBAP v4 packer.
The MSX2 reference runtime now exposes the append-only v6 record and admits the
primary-only v4 profile through a boot-verified, transactional pre-entry gate;
see [GEOBENCH-V2-GATE2-MSX.md](GEOBENCH-V2-GATE2-MSX.md).

## Windowing, compositor, and scheduling

The desktop root task owns the global window table and compositor. Window
records reference application owners instead of assuming one window per code
page. Kernel-owned furniture supplies move, resize, maximize/restore, close,
and focus behaviour.

Damage is represented as a rectangle and intersected with each affected
surface. A band iterator subtracts higher opaque windows, emits exact visible
fragments, and clips application repaint callbacks. Fully covered applications
receive no visual-worker CPU. Scheduler order is focused, fully visible,
partially visible, then nonvisual/background work.

## Resources and services

- GBR1 stores deterministic strings, objects, trees, menus, and forms.
- GBAP v3 packages a guarded application manifest and optional secondary data.
- GBAP v4 packages compile-once applications; MSX2 Gate 2 admits the mandatory
  common primary segment and rejects unimplemented external v4 segments.
- VDI-lite provides semantic pens, clipping, raster operations, and text.
- Typed scrap carries text, bitmap, icon, and file-list payloads.
- Shell services discover, activate, open, close, and quit live applications.
- Deferred messages use a bounded owner-safe FIFO.
- Filesystem contexts retain independent drive, path, directory, and offset.
- Shared services use generation-safe provider and client leases.
- Timers publish bounded compositor damage from app-owned workers.

All queues, tables, strings, transfers, and iteration budgets are fixed and
bounded; no runtime heap is required.

## Distribution

`QA/MSX/CARD` is the committed loose release tree. The build also creates a
bootable FAT16 hard-disk image and two FAT12 floppy images. System files live in
`GBENCH/`, pictures in `PICS/`, and development programs in `DIAG/`.

Canonical four-pen assets retain the inherited Mode-1 byte packing and are
converted by the MSX2 renderer. This is a file-format choice, not another
hardware target. Screen 7 resources may add native sixteen-colour variants.
