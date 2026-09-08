# Restart step 3D-L: unified CPC runtime and first universal APP

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`, following `e896e08`.
Parent: [production adapter gate](CPC-RESTART-STEP3D.md) and
[restart plan](CPC-RESTART-PLAN.md).

Status: **experimental unified M4 launcher implemented and validated in 1984**.
The unchanged universal ABI Probe now runs through the shared kernel rather
than a scripted window fixture. This is an early first-window integration
proof, not the Desktop distribution, complete ABI conformance, application
parity, or closure of the production adapter gate.

Follow-up: [3D-M](CPC-RESTART-STEP3D-M.md) supersedes the portable-filesystem
gap and adds F5 to launch its filesystem probe. This document retains the
original 3D-L measurements and evidence.

## What is composed

`kernel/cpc_runtime.asm` links the previously qualified CPC hardware leaves and
the same shared owner/page, window registration, lifetime, focus, visibility,
damage, routing, deferred-message and loader code used on MSX2. It includes no
production-test driver or substitute CPC window manager. Existing diagnostic
compositions remain available for their more exhaustive subsystem regressions.

M4 firmware loads the small bootstrap, which takes over, disables ROMs, sets up
guarded stacks and loads the resident core through the low fixed loader. The
kernel admits 512 KiB, creates an owned root launch surface, installs the font
and filesystem module in reserved page F7, then loads `/GBENCH/ABIPROBE.APP`
through the shared package-validation and owner-allocation transaction.

The launcher is deliberately kernel-owned and minimal. It is not a rewritten
Desktop: it supplies a background, a labelled bar and test controls while the
real application receives the shared event, paint, focus and close behavior.

The public jump table retains all 72 frozen addresses through `80D5`. Bound
leaves cover the APP's window/drawing/input/lifetime requirements and the
caller-owned ABI 2.1 parameter receiver. Important integration boundaries:

- Managed geometry is published at the SDK's frozen `1448` observation record;
  pointer/input observations use `1306..1308`. Private diagnostic addresses
  were not public SDK bindings.
- Native text is copied below the application aperture before mapping F7 for
  the font. Drawing keeps the shared compositor clip and excludes only an
  intersecting software pointer.
- CPC Mode 1 save-under bytes are already canonical two-bit semantic pixels.
  The bound save/restore leaves accept nonempty, entirely in-bounds rectangles
  and validated primary-page buffers. This is not clipped partial-save support.
- The admission leaf rejects old native packages, ABI 2.0 framebuffer-mailbox
  packages and unsupported required capability masks after shared validation.
  The new runtime's positive APP path is emulator-tested; its new rejection
  branches are not a separately exercised negative-runtime matrix yet.
- A private sysinfo view advertises only this experimental subset. Filesystem,
  shell/service discovery, public page allocation, resources/secondary code and
  background-timer capabilities remain off. Unbound entries return failure;
  the complete typed optional-service contract remains a qualification task.
- The FS module is linked and exercised through its fixed private gate, but
  `GB_FSCTX` is not exposed. The existing MSX client uses `C3D0`/`C400` buffers,
  which overlap CPC pixels. A portable client/marshalling boundary is still
  required; saving the framebuffer around those mailboxes is not an ABI fix.

No universal SDK, APP source, public ABI constant or shared MSX policy changes
are introduced here. The MSX2 release target/media and the user's parked
`QA/CPC/` remain untouched.

## Measured composition

The existing checked production memory map remains authoritative. All budgets
below are independent allocations, not additive claims of spare kernel RAM.

| Section | Base | Actual bytes | Allocation bytes |
|---|---|---:|---:|
| Resident kernel, including launcher/font payload | `8000` | 10,949 | 16,384 |
| Low universal support | `0400` | 1,673 | 3,072 |
| Bank/M4/IRQ/input hardware | `3800` | 1,130 | 1,536 |
| Shared context/visibility scheduler | `2900` | 1,437 | 1,536 |
| Paged shared FS-context module | F7:`4400` | 4,502 | 7,168 |

The font occupies F7:`4000..4330`; I/O scratch starts at F7:`6000`. F7 is
excluded from the owner pool. Main/IRQ/temporary stacks keep their existing
256/256/128-byte allocations and 16-byte guards on both sides. Observed
high-water marks are 53/4/0 bytes. The temporary context-copy stack is unused
in this APP test, not proven by a zero measurement. Real-worker context depth
remains covered by the separate routing regression below.

The full `C000..FFFF` page, including raster gaps, belongs to the framebuffer.
No command buffers, M4 responses, fixed architecture state or stacks are placed
there. Remaining Desktop/services/modules have not yet been budgeted in this
link; current headroom is not a promise that the final distribution fits.

## Validation

1984 main includes the FAT/M4 protection fix
[PR #292](https://github.com/salvogendut/1984/pull/292), merged at `0851004`.
The executable used here has SHA-256
`00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`.
Toolchain: RASM 3.2.1 and SDCC/SDAS under `../sdcc/bin`, in `my-distrobox`.

Every runtime boot uses a fresh private copy of the generated FAT16 M4 image,
actual firmware/bootstrap loading and actual emulator keyboard input. Snapshots
observe state only; there is no floppy boot, snapshot restore or RAM injection.
An independent compositor oracle checks all 16,384 framebuffer bytes, including
background exposure, chrome, text, content, pointer and raster gaps.

Eleven checkpoints pass:

1. The real APP opens and gets focus, with correct native frame and content.
2. Clicking content changes its stripe without damaging the rest of the screen.
3. Title dragging moves it and cleans the old position.
4. Private root-owned FS open/free/close works while the window remains live;
   reported free space matches an independent FAT scan and no context leaks.
5. F3 loads another real instance, with the correct overlapping z-order.
6. Clicking the exposed first instance raises it and restores its exposed pixels.
7. Closing that instance reveals the second correctly.
8. Closing the second restores the root and reclaims owners/pages.
9. The public keyboard entry returns ASCII `a` for an actual A key press.
10. A root-only S command calls public cursor hide, save, fill, caller-owned
    line, restore and cursor show entries; saved bytes and final pixels match.
11. F3 reopens the APP using the reclaimed slot/page.

Checks also require intact code/font/module bytes, all stack guards, correct
ROM/mode/IM state, no scheduler fault, no pending storage/pointer lock, exact
window geometry/order and unchanged media bytes after the read-only run.
The loaded APP is compared byte-for-byte with the staged artifact:

`ABIPROBE.APP`: 2,571 bytes, SHA-256
`a6a696cc0bef9caf69c38b6c44f8d8e50dbb7dd560c88e99feb9595993e0adfc`.

Final runtime log: `/tmp/geobench-77l-runtime-final.log`; artifacts:
`/tmp/geobench-cpc-runtime-fprtujql`, containing console log, read-only snapshots,
screenshots and `result.json`. These are local evidence, not committed generated
assets.

The earlier routing/worker composition also passes its 14 checkpoints after
these provider changes: real worker publication, focus/visibility scheduling,
menu/deferred delivery, move/resize/maximise and close notifications. It records
64 I/O rounds, 717 M4 commands, and main/IRQ/temporary stack depths 26/4/6 bytes.
Log: `/tmp/geobench-77l-routing-regression.log`; artifacts:
`/tmp/geobench-cpc-production-m9ey5o9k`. This does not substitute for a future
real Clock/Calculator worker test in the unified runtime.

Three added host tests verify deterministic linking, the full jump-table shape,
fixed SDK observations, capability limits, allocation-overflow rejection and
pixel-oracle mutation detection. Host-synthetic RAM is checker input only.

Full `make check` passes (exit 0): **201 Python tests without skips**, native
library checks, deterministic universal SDK builds, ABI/layout and distribution
audits. Log: `/tmp/geobench-77l-check.log`; isolated detached worktree:
`/tmp/geobench-77l-check.6FYSSm`, containing the implementation but not the user's
untracked parked `QA/CPC/`. The MSX2-only distribution audit was not weakened.
No new MSX2 emulator session or release-media rebuild was needed for these
CPC-only bindings; the full host checks include the MSX build contracts.

## Build and try it

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-runtime

distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

The builder stages `CARD/`, `RUNTIME.IMG`, a section/hash manifest and a private
`1984.conf` under `QA/Diagnostics/CPC-runtime/`. It does not mount an existing
user card or change the normal emulator configuration. Rebuild after relocating
the checkout, since the generated configuration contains the absolute image path.

Controls: arrow keys move the software pointer; Space presses/releases the
button (hold it while using arrows to drag a title). Escape closes the focused
APP. F3 opens another ABI Probe; F4 checks private M4 free-space/context cleanup.
After closing the APP windows, S exercises save-under/line/restore on the empty
root surface. It restores the original pixels, so no persistent change is expected.
This checkpoint uses keyboard pointer emulation, not a qualified mouse driver.

For the automated regression, use the same toolchain environment with
`make diagnostic-cpc-runtime-1984`. The runner also accepts `--emulator` and
`--skip-build` when invoked as `python3 tools/test_cpc_runtime_1984.py`.

## Next gate and remaining limits

Next: bind the public filesystem client safely, budget the remaining service
and resource adapters, and connect real Desktop/File Manager and their Desk/menu
behavior to this same shared root loop. Do not replace that policy with a CPC
shell. Then qualify real universal Clock/Calculator timers/workers, followed by
the application-parity ledger.

This first launcher has no Desktop menus, themed title tiles, file browser or
application picker. Keyboard repeat and Caps Lock are not implemented; the
Shift/Ctrl table needs broader runtime coverage. Time is software uptime from
the existing 16-bit seconds counter, not a qualified wall clock or RTC service.
The test does not cover its wraparound or long-duration accuracy. FS namespace,
synchronous IRQ-excluded M4 I/O and failure-mode limits from 3D-I/J/K remain.
No physical CPC/M4, Albireo or alternate-emulator qualification is claimed.
