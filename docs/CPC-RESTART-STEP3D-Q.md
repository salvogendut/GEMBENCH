# Restart step 3D-Q: shared Desktop root and Desk menu

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`, following `b756153` (3D-P).
Parent: [restart plan](CPC-RESTART-PLAN.md).

Status: the actual Desktop Desk-menu component is integrated into the private
M4 runtime. **This is not the complete Desktop, a portable Desktop.APP, or
closure of the production-adapter gate.** System/Settings, assets and File
Manager remain gated until their native service and memory dependencies are
bound. MSX2 remains the release target.

## Shared implementation

The existing Desktop accessory action, menu registration and post-popup
activation blocks are extracted into `apps/desktop/core/{accessory_menu,
menu_init,accessory_pending}.inc`. Both the MSX Desktop and CPC root include
them. The catalog, exact-instance activation, launch and full-capacity behavior
remain the existing shared policy. F2/F7 remain diagnostic shortcuts, but are
no longer the only way to launch Clock/Calculator.

The native root links the actual `gbdoc.c` title/event/modal/dispatch machinery
and `gbdlg.c` save-under popup. `GBDOC_MENU_ONLY` excludes document/file actions;
it does not supply fake filesystem implementations or another menu renderer.
The normal MSX profile is unchanged. `DESKTOP_SYSTEM_MENU=0` explicitly gates
the unbound System actions in the CPC component only.

Root events now enter `gb_doc_event`; root frames enter `gb_doc_frame` and
process the shared pending accessory action after the popup has restored its
pixels and released input. A Desk action does not invalidate the blank root
backdrop: launch/activation supplies its own window damage. The full MSX
Desktop's existing repaint behavior is unchanged.

## Memory decision

The complete production MSX Desktop was measured before choosing an allocation:
15,147 loaded bytes, ending at `7B2B`; mutable data at `7D90..7ECE` occupies
318 bytes, leaving only **50 bytes below the `7F00` snapshot boundary**. The
portable filesystem client alone needs a 32-byte request plus a 512-byte
transfer buffer. Those 544 bytes cannot simply be appended to that data area.
The old native `gb_copybuf=2200` also overlaps the CPC shared architecture
tables/scheduler; using it for popups would corrupt the runtime.

For this bounded integration component, move code out of the fixed high kernel
into the root's already-owned C0 page. No extra owner page is consumed. End
addresses below are exclusive:

| C0 allocation | Range | Used / budget |
|---|---|---:|
| Root menu/bar code and constants | `4000..6000` | 3,947 / 8,192 bytes |
| Root mutable state, explicitly zeroed at boot | `6000..6100` | 87 / 256 bytes |
| Existing diagnostic scratch | `6100..6300` | 512-byte reservation |
| Unallocated gap | `6300..6400` | 256 bytes |
| Native popup save-under | `6400..7F00` | 6,912-byte capacity |
| Existing context snapshot | `7F00..8000` | unchanged 256-byte reservation |

`GB_POPUP_BUFFER`/`GB_POPUP_CAPACITY` provide the root-owned popup allocation.
Normal MSX builds still use `gb_copybuf`/`GB_COPYMAX`. F7 filesystem scratch
and C0 root state may share CPU addresses, but have distinct physical owners;
the existing service gate restores the caller's mapping.

The build checks linked code/data bounds, excludes CRT initializer sections,
and pads `ROOTUI.BIN` to exactly 8,192 bytes. Assembly rejects code/data,
scratch/popup and popup/snapshot overlap. The existing bounded M4 reader loads
`/GBENCH/ROOTUI.BIN` into C0 before any root component callback runs. Its
transfer envelope is `4000..7F00`; an oversized input can occupy uninitialized
root-owned data, but must never reach the snapshot. Any length other than
8,192, missing file or read failure stops boot before initialization/execution.
This is trusted native code, not a new public APP format or security sandbox.

| Other linked allocation | Used / budget, bytes |
|---|---:|
| Fixed high kernel | 11,639 / 16,384 |
| Low support | 1,832 / 3,072 |
| Hardware leaves | 1,130 / 1,536 |
| Scheduler | 1,446 / 1,536 |
| F7 filesystem module | 4,502 / 7,168 |

The fixed kernel is 1,468 bytes smaller than 3D-P. The Desk and Clock scenarios
observe main/IRQ/temporary stack use of 99/4/6 bytes; guards remain unchanged.
The full Desktop needs a separate measured code/data/provider plan, not an
extension into snapshot or framebuffer memory.

## Remaining Desktop service ledger

| Dependency | State / next binding |
|---|---|
| Root loop, bar, Desk, menus, accessories, workers and timer damage | Composed and tested here and in 3D-N/O/P. |
| Configuration and System/Settings actions | Still gated. Desktop reads config text at `1000`, length at `1200`; provide owned storage and accessors instead of assuming the MSX layout. |
| General native dialog/UI module | Native `GB_UI` at `80AE` remains unavailable. Allocate the module, request state and transfer scratch explicitly; the legacy F7 module address `6000` conflicts with current M4 I/O scratch. The linked Desk popup does not imply this service exists. |
| Theme, icons, wallpaper/picture and reload services | Resolve their loaders, shared state and buffers before enabling full Desktop rendering. The current font/chrome proof is not a complete assets pass. |
| Desktop/File Manager M4 navigation | Bind native shell/storage users to qualified providers, including caller-owned portable FS buffers, then test real directory/open workflows. Neither native application is made universal by this checkpoint. |

Do not grow the private launcher into a second CPC Desktop. The next work is
these native service/memory bindings, followed by the full shared Desktop and
File Manager. General application parity and Albireo qualification still follow.

## Validation

- The real Desk path passes **26 M4/1984 checkpoints**: title/popup/hover,
  cancel and save-under restoration, Calculator arithmetic, Clock seconds and
  background updates, modal stability over a live Clock, title-reclick and
  click-away cancel, exact reactivation, close/fresh-owner relaunch,
  full-table activation, real capacity alert/dismissal and M4 service recovery.
- The observer independently constructs the entire expected z-ordered frame,
  including native popup text highlighting. It checks stable completed frames,
  code/font/root-module integrity, focus/owner state and stack guards. Input is
  real keyboard/pointer interaction, never guest-RAM injection. Menu clicks
  wait for press/release acknowledgement so Clock drawing cannot swallow a
  short test pulse.
- Missing, truncated and oversized root modules are separately rejected before
  execution, with stable halted state, intact kernel code and stack guards.
- Existing ordinary-window (11), Clock (22), application-menu (10),
  Calculator/accessory (19) and portable-filesystem (46) scenarios pass with
  the relocated root component. The filesystem run observes a 127-byte main
  stack high-water mark; Calculator observes 103 bytes.
- Host tests exercise the actual shared document-less menu and Desktop blocks
  at CPC and MSX widths, including bounds, cancellation, deferred dispatch,
  modal toggling, title capacity and reinitialization. Layout tests reject
  undersized code budgets and overlapping root code/data.
- Full `make check` passes in the isolated worktree
  `/tmp/geobench-77q-reference.8WykAX`: **215 Python tests without skips**,
  plus native C, SDK/ABI and distribution checks. Log:
  `/tmp/geobench-77q-check-final.log`.
- MSX Desktop extraction output is byte-identical in both the previous
  extraction profile (15,144 bytes) and the production preemptive profile
  (15,147 bytes). The normal 6,063-byte `GBUI` build is also byte-identical.
- Fresh openMSX Screen 6 and 7 Desk/Clock lifecycle regressions pass on private
  hard-disk media with the rebuilt Desktop/UI binaries and matching 3D-P
  kernels/gate. Each observes 48 timer-source fragments and 24 clipped rim
  repairs, with no source mismatch, stack fault or service lifecycle failure.

Emulator logs: `/tmp/geobench-77q-desk-final.log`,
`/tmp/geobench-77q-root-faults.log`,
`/tmp/geobench-77q-{runtime,clock,menus,accessories,fs}.log`, and
`/tmp/geobench-77q-msx{6,7}.log`.

Production MSX Desktop SHA256:
`552199b90097c7a6c5ee398152c0f1c0b15ea952f986a7e86d747ddc10e1abe5`.
Root module SHA256:
`e1b57c56c733f223eb0360d4330cd3332db3c22d7ca2cd261f2a7c2990610651`.
Clock (7,580 bytes) and Calculator (7,825 bytes) retain their 3D-P APP hashes;
there are no universal APP/ABI changes in this checkpoint.

No emulator changes, floppy runtime tests, working MSX release-media changes,
PCW enablement or Albireo qualification. The user's `QA/CPC/` and recordings
are preserved. 1984 executable SHA256 remains
`00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`.

## Manual test

The rebuilt private M4 card is under `QA/Diagnostics/CPC-runtime`:

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

ABI Probe initially has focus. Close it with **Escape**, or click the empty
background, to see **Desk** in the top bar. Use arrows to move the pointer and
Space to click. Select **Desk → Clock** or **Desk → Calculator**. Press **S**
in Clock to toggle seconds; enter a calculation, then select each accessory
again through Desk: it should bring back the same instance and its state.
Drag and overlap them to check focus/exposure/background Clock updates.
The pointer is still the keyboard/joystick test adapter, not a qualified CPC
mouse hardware driver. F2/F7 remain available as diagnostic shortcuts.

Rebuild and run the automated Desk scenario:

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-desk-1984
```

`make diagnostic-cpc-runtime` builds only. Additional scenarios use
`tools/test_cpc_runtime_1984.py --skip-build` with `--clock`, `--menus`,
`--accessories`, `--filesystem`, or `--root-fault missing` (also `short` and
`oversized`). Fault scenarios modify private copies of the M4 image only.
