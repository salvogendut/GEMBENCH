# CPC restart 3D-W2-A — Settings platform boundary

Issue #77, branch `feature/77-cpc-production-adapters`, following W1 commit
`abbe251`. 2026-09-07.

**Implemented: source isolation, compile-time dependency/layout audit and host
tests of the actual Settings application/widgets. Not implemented: native CPC
Settings launch, its complete service bindings, or System-menu integration.**
The diagnostic M4 image remains the validated W1 image; no rebuild is needed.

## Changes

`apps/settings/main.c` remains the application, including its current picker
state machine, colour editor, defaults and saver behavior. Its fixed config,
appearance and saver state references now come from a platform provider. The
existing ink and saver calls live in small include files at their original
compilation positions. The legacy profile retains the MSX addresses and calls.
The row table uses typed name pointers instead of integer addresses; it remains
the same Z80 layout. The null task-worker field is now explicit.

New providers must be selected explicitly with `GB_SETTINGS_PROVIDER` and
declare contract version 1. `GB_CPC_RESTART` without a provider fails compilation
instead of silently selecting the old firmware/low-RAM profile. The original
build script still requires MSX2; this checkpoint does not weaken that guard.
Its cache tracks the extracted legacy files.

The **unbound** profile is a compile-only inventory: memory cells and ink/saver
operations become unresolved external symbols. It has no fake implementation,
linker address assignment, APP header or loader exception. The audit additionally
classifies every external reference from the actual SDCC object and rejects
unreviewed dependencies or direct numeric state/service accesses in its assembly.
It is a regression tripwire, not a general Z80 safety verifier or sandbox.
An unused legacy `gbcfg` reader is excluded in custom-provider builds so its
fixed-address code is not carried into the audit. Default MSX output retains it.

## Measured requirements

The preemptive CPC geometry profile compiles the application's `main.c` to
**10,132 bytes of code and 952 bytes of data** with the project SDCC compiler
and size flags. These are **object sizes, not a final linked application size**.
Shared helpers, compiler routines, CRT/header, alignment and provider storage
are additional; the report does not claim that the complete app fits.

- The old data base `0x7C40` plus the app's own 952 bytes reaches `0x7FF8`:
  **248 bytes past CPC's `0x7F00` reserved snapshot boundary**. Before helper
  data, the latest possible data base would be `0x7B48`. Final placement must
  account for all linked objects and cannot be chosen from this figure alone.
- Settings still assumes a **6,656-byte legacy copy buffer**. Its old `0x2200`
  location overlaps live CPC runtime allocations. IST validation only needs
  its header/count; use bounded owned reads when binding it instead of
  reserving that whole buffer or borrowing unrelated fixed RAM.
- Twelve native filesystem functions remain unbound: drive/path/enumeration,
  selected entry/name and file load/save. Their global-style API must bind to
  owned contexts, preserving picker enumeration across frame callbacks.
- `gb_reload`, title/gadget installation, popup/save-under, palette and saver
  dispatch still require their complete native contracts. Reuse the qualified
  renderer/module machinery; do not substitute the old CPC firmware calls.
- The existing Settings `cfg_set` still publishes its in-memory text after a
  best-effort save. A CPC provider must use W1's verified persistence path and
  propagate failures before publication. W1 currently accepts six appearance
  keys only; colours, wallpaper, saver values and whole-default reset are **not**
  qualified by that gate.
- Saver configuration uses operation 26 through the arbitrary-module selector
  `A=0x80`; W1 uses private operation 26 with selector zero. CPC currently
  rejects the arbitrary selector, so this is not an enabled dispatch collision.
  It must remain distinct when saver modules are introduced, not be routed into
  `GBEDIT.MOD` simply because the operation byte matches.

The generated report enumerates the exact symbols by class. A class called
`shared_*` identifies code to reuse, not a claim that its allocation/callback
contract is already linked and qualified in a native Settings application.

## Checks

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  make diagnostic-cpc-settings-audit
```

Outputs: `build/cpc-settings-audit/settings.rel`, assembly/listing and
`report.json`. **No executable, M4 image or floppy is produced.**

`tests/test_settings_platform.py` compiles the actual Settings source and
`gbselect.c`, `gbstepper.c`, `gbactions.c` against host-owned state/device
leaves. It exercises row pointers, config preservation/publication, raw asset
names, palette/frame-pen decisions, all appearance selectors and saver/default
labels, the asynchronous picker state and the colour editor. Geometry checks
use CPC's 320x200 dimensions. These are host checks, not emulator confirmation
or tests of a working native filesystem provider.

The four platform tests pass, including rejection of an unknown external
symbol, numeric firmware/RAM accesses and a missing explicit provider. The
existing W1 host persistence tests also pass. Both final MSX Settings binaries
are byte-identical to the pre-extraction baseline:

- Cooperative: 15,011 bytes, SHA-256
  `150acb7b5a64558ac523b3a06d2c7e1209d3479a68bc1a9699dd9d4be0755221`.
- Production preemptive: 15,276 bytes, SHA-256
  `c08dd22060b83e23bfe77462ba5f522bb817359af526de962ccbd07d64d21387`.

Full `make check` passes in an isolated worktree: **241 Python tests**, no
skips, plus the native C, SDK, ABI and distribution checks. Normal MSX media
and the existing diagnostic M4 image remain unchanged.

Evidence and isolated build/check trees are under `/tmp/geobench-77w2-*`.
No new openMSX, 1984, Albireo or PCW runtime qualification is claimed for this
compile-only gate.

## Next checkpoint

The [desktop-first delivery update](CPC-RESTART-PLAN.md#desktop-first-delivery-update--2026-09-07)
now prioritizes the actual Desktop/File Manager dependency audit and minimum
native filesystem/loading bindings. Reuse this Settings inventory and W1 where
they unblock that path; completing every Settings or saver feature is not a
prerequisite for the first usable desktop.

W2 remains open. Its eventual Settings integration still requires owned
filesystem operations, bounded IST header reads, explicit I/O errors and W1
verified publication, plus the complete linked memory, launch, modal and asset
profile. Validate that profile on private M4 copies before enabling Settings.
W3's qualified System actions can be integrated incrementally with Desktop.
