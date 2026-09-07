# CPC restart 3D-V — native file picker

Issue #77, branch `feature/77-cpc-production-adapters`, 2026-09-07.
Follows [3D-U](CPC-RESTART-STEP3D-U.md). This integrates a shared native
chooser into the private M4 runtime, **not the complete Desktop/File Manager**.

## Shared code and ownership

The UI still comes from `lib/gb/gbpick.c` and `gbdlg.c`. The existing native
extension-list/operation dispatch is extracted unchanged from `gbui_mod.c`
into `kernel/core/ui_picker.inc`, included by both targets. Optional provider
error checks let CPC abort a failed directory operation without presenting it
as an empty directory. They compile out of the existing MSX implementation.

Native UI operations 3/4 now select `GBPICK.MOD`; other supported dialogs still
use `GBUI.MOD`. Both use the existing shared module load/call/restore and modal
transactions. Modules must have exactly 6,144 bytes, including padding. Missing,
truncated or oversized modules return cancel without executing the payload.
These are trusted, build-specific native binaries: length admission is not
authentication, and MSX MOD files must not be copied into the CPC card.

The CPC binding supplies the chooser's directory primitives through the
existing filesystem-context client, shared owner/generation policy and M4
backend. It allocates one temporary context and closes it on selection, cancel
or an ordinary filesystem error. The original caller identity is captured
**before** F6 replaces the caller's bank. The private filesystem gate may use
that identity only inside the serialized modal transaction, with a valid owner;
ordinary calls derive the mapped caller. Worker calls are rejected. IRQ time
and pointer input continue while application callbacks/workers are parked.

The root diagnostic reads an accepted file through a **fresh caller-owned
context after the dialog returns**. That checks the exact path/name handoff
and subsequent M4 access, not merely the appearance of the list. It reads at
most 16 bytes and does not write files.

## Contract and retained limits

- Open retains the shared eight-parent reset, then returns an exact raw
  11-byte 8.3 name; this is not an unbounded-depth browser. Destination mode
  navigates folders and accepts `[Save here]`;
  clicking a file in that mode does not accept it.
- Folder navigation, `..`, filtering, cancellation and popup save-under are
  shared policy. The existing cap is **12 real entries**, with at most ten
  visible popup rows. This checkpoint does not implement a new large-directory
  browser or change that cap.
- The native request accepts up to seven three-character uppercase/digit
  extensions, NUL-separated and terminated by an empty string. Malformed
  requests are rejected before allocating a context or drawing. The existing
  native empty-list behavior is retained: folders only. This differs from
  calling the shared C picker directly with a NULL filter, which means all files.
- The private path handoff is 48 bytes, including NUL, and caller-tagged. A
  destination chooser can reuse the last path for the same caller; another
  owner starts at root. Non-rooted/unterminated retained paths fall back to root.
  Rejected directory activation cannot publish a partial path.
- This is **one last-caller handoff, not per-application implicit filesystem
  state**. It does not enable the old native global directory/load/save slots,
  a universal picker service, `GB_RELOAD`, or full native APP compatibility.
  Public ABI and capability bits are unchanged. The inherited context
  backend's read/error limitations are not changed here.

## Memory budget

| Allocation | Used / budget |
| --- | --- |
| Resident CPC kernel | 15,109 / 16,384 bytes |
| Root component | 5,001 / 8,192 code; 87 / 256 data bytes |
| F6 GBCFG | 2,815 / 6,144 code; 11 / 768 data bytes |
| F6 GBUI | 5,596 / 6,144 code; 4 / 768 data bytes |
| F6 GBPICK | 5,279 / 6,144 code; 433 / 768 data bytes |
| Private handoff/diagnostic cells | 1E00–1E48, within fixed adapter state |

F6 data now occupies 5800–5B00. Basic-dialog save-under moves to 5B00–6C00
(4,352 bytes; About requires 3,720). Nested popup save-under stays at
6C00–7F00 (4,864 bytes). No extra bank is reserved: **27 application pages
including root** remain available. F7 filesystem/title/icon allocations,
fixed transfer storage, stacks and framebuffer are unchanged. Assembly and
link checks enforce the bounds; neither module borrows raster gaps.

## Validation

- The actual C chooser plus CPC binding pass host tests for nested navigation,
  raw names, filtering, empty folders, parent navigation, destination selection,
  cancel, caller isolation, malformed requests, the 12-entry cap, context
  exhaustion and directory/replay/activation errors with cleanup.
- The M4/1984 picker scenario passes **34 checkpoints**, including exact full
  framebuffer restoration, successful post-dialog file readback, five repeated
  modal cycles with background Clock, parked/resumed work, context ownership,
  no context leaks, code integrity and stack guards. Maximum observed
  main/IRQ/temporary stack use is **147/4/6 bytes**.
- Basic native dialogs are rechecked: **23 checkpoints**, including prompt,
  size, About, nested popup, Clock, Calculator and filesystem recovery.
- All three picker module-failure cases (missing, short and oversized) pass
  rejection, intact screen/state and subsequent Clock/M4 recovery checks.
- Clock's **22-checkpoint** focus/occlusion/partial-damage scenario passes.
  The unchanged pointer-cadence thresholds also pass: idle 50.0 steps/s,
  focused seconds 49.24, background seconds 47.73; maximum moving gap 11 IRQ
  ticks, no stationary spans. This does not fix the previously recorded
  software-clock drift under load.
- Full `make check` passes in an isolated worktree: **235 Python tests**, no
  skips, plus native C, SDK, ABI and distribution checks.
- Before/after MSX GBUI builds in an isolated worktree are byte-identical:
  6,058 bytes, SHA-256
  `b910e359b74a1c59a26a03f7654a97228f771ba5ce9d198b8aef951616c8f4c2`
  with the same `GIT_COMMIT=d4e40e9` identity. The build cache now tracks the
  extracted include. No fresh openMSX runtime test is claimed.

The host harness passes with warnings treated as errors. An optional sanitizer
run could not link because the ASan/UBSan runtime libraries are absent; no
sanitizer-clean result is claimed.

Tests use private M4 image copies and real input with read-only snapshots;
they do not inject guest RAM. Local evidence is under `/tmp/geobench-77v-*`.
Normal MSX media, user recordings, `QA/CPC/` and sibling emulator sources are
untouched. No floppy emulator runs; Albireo and PCW are not qualified here.

## Manual check

The diagnostic M4 image has been rebuilt. Run:

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Click the blue background (arrows move the pointer, **Space** clicks), then:

- **O**: Open `.TXT` chooser. Enter `PICKTEST/`, then `INNER/`, then select
  `HELLO.TXT`. The chooser closes; the diagnostic reads its contents into
  private observation cells. This is not a document-viewer launch.
- **D**: Destination chooser, initially at that caller's last path. Navigate
  with folders/`..` and choose `[Save here]`. No file is created or overwritten.
- **Escape** cancels. `PICKTEST/EMPTY/` exercises an empty directory;
  `IGNORE.BIN` is deliberately excluded by the TXT filter.
- **F2** opens Clock; **S** toggles seconds while Clock has focus. Refocus
  the background and repeat the picker checks to exercise modal restoration.

`make diagnostic-cpc-picker-1984` rebuilds and runs the automated scenario.
`tools/test_cpc_runtime_1984.py --skip-build --picker-fault missing` selects
a private missing-module test; `short` and `oversized` are also available.

## Next

[System/Settings service integration](CPC-RESTART-STEP3D-W.md): W1 now supplies
checked configuration persistence/reload. The actual application's native
loading, filesystem and form bindings remain W2, followed by the System menu
in W3; then the complete shared Desktop/File
Manager and remaining application parity. The broader adapter gate stays open.
