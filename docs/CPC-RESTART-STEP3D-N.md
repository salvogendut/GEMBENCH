# Restart step 3D-N: shared Desktop bar and application menus

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`. Follows
[3D-M portable filesystem](CPC-RESTART-STEP3D-M.md).

Status: **the existing Desktop bar and native menu publication now run in the
composed CPC/M4 runtime**. This is an initial Desktop integration checkpoint,
not the complete Desktop, Desk accessory service, File Manager or CPC release.
The preceding 3D-L/M work was committed and pushed as `5943b05` before this work.

Follow-up: [3D-O](CPC-RESTART-STEP3D-O.md) adds the shared accessory service and
unchanged Calculator, using F7 for exact activation. Clock and full Desk/Desktop
integration remain open; sizes and capability limits below describe 3D-N.

## Reuse, not a second shell

`kernel/core/menu_state.asm` is the existing MSX `k_menu`, `menu_install` and
`menu_clear`, extracted without changing instructions. CPC now uses the same
per-window menu pointer and resident title snapshot, instead of retaining a
pointer that no bar renderer consumed. The snapshot occupies `1310..1334`
(37 bytes), below the compositor clip at `1338`. Focus maps the owning page
before installing its definition; no application pointer is dereferenced by
the root renderer after switching banks.

`apps/desktop/core/bar_render.inc` and `bar_refresh.inc` contain the existing
Desktop rendering and refresh policy. Both the MSX Desktop and the CPC native
root binding compile these exact fragments. They retain RAM text, the focused
window's titles, HH:MM, binary/BCD conversion, fullscreen suppression and the
existing menu checksum optimization. Idle iterations perform no drawing or
pointer hide/show; minute changes update the time, and menu changes clear only
the title strip. This does not redesign that inherited checksum algorithm.

Until the full Desktop can become root, `kernel/kc/cpc_root_bar.c` binds those
fragments to native CPC geometry/time/presentation. It is a temporary **kernel
component**, not another Desktop application or a new ABI. Its resident code
is linked into `CORE.BIN` once; its 11 bytes of mutable state live in the
kernel root's C0 page. Only root DRAW and the existing root-loop bar hook enter
it, with C0 mapped. Ordinary content exposure does not invalidate the bar.
The build checks both allocations and rejects CRT-initialized data. Remove
this binding when the real Desktop supplies the bar hook itself.

The private launcher still supplies the plain background and F3/F4/F5 test
controls. F6 now loads `MENUPRBE.APP` through the normal M4 package transaction.
This compile-once test client uses `gb_menu`, actual menu events and the
existing `gb_universal_popup` implementation. It adds no menu policy to the
kernel and does not advertise the still-missing `shell` capability. The ABI
version, jump table and capability masks remain unchanged.

## Bounds and results

| Allocation | Used | Budget |
|---|---:|---:|
| Resident CPC kernel, including the reserved bar slot | 12,528 | 16,384 |
| Shared bar code within that kernel allocation | 648 | 1,536 |
| Bar data in root C0 at `4000` | 11 | 32 |
| Low support | 1,832 | 3,072 |
| Hardware leaves | 1,130 | 1,536 |
| Scheduler | 1,437 | 1,536 |
| FS module in F7 | 4,502 | 7,168 |

The bar slot includes 888 padding bytes for a stable two-pass C/assembly link;
it is already counted in the kernel total, not additional memory. Nothing is
allocated in the CPC framebuffer or its raster gaps. M4 file load limits,
application pages, scheduler reservation and all stack guards are unchanged.

The real-input M4 test passes ten exact-framebuffer checkpoints: initial APP,
menu APP launch, first popup, hover, selection/save-under restoration, focus
away, focus return, second popup, Escape cancellation and close exposure. It
also checks actual loaded APP bytes, recipient/action counters, menu snapshots,
window geometry/z-order, immutable resident/module/font bytes, bank/mode and
stack guards. It never injects guest RAM or boots a snapshot. The pixel oracle
constructs menu/popup contents independently rather than accepting the observed
title snapshot as its expected value. The menu run leaves its M4 image unchanged.

The ordinary 11-checkpoint window regression and all 46 portable-filesystem
checks also pass with the bar present. Observed main-stack use is 53 bytes for
ordinary windows, 96 for menus, and 127 for filesystem work, out of 256. IRQ
use remains 4 bytes; these root-only tests do not newly qualify worker switching.

MSX extraction comparisons are byte-identical:

- Native Desktop: 15,144 bytes, SHA256
  `69eb5134b1326aaa42465a9c2fff94eaf522d286cf60a62d3b9cc89327baf302`.
  Both builds used `TASK_ROOT=1`, 256-byte stack reservation, `DATA_LOC=0x7D90`,
  `DOC=1`, `TITLEBAR=1`, deferred/service/timer collectors and
  `APPDEFS='-DGB_MSX2 -DGB_DESK_ACCESSORIES'`.
- Screen-7 kernel: 15,534 bytes, SHA256
  `fd2503a22c56cde6d5de53e916058eead5906d06f6571ac722521620928e9b4d`,
  with `PLATFORM_MSX=1`, `PREEMPTIVE=1`, `PREEMPTIVE_CONTEXT=1`,
  `TITLEBAR_TILE=1`, `MSX_SCREEN7=1`.

Fresh openMSX Screen 6 and 7 runs of the existing Desktop-launched filesystem
regression pass all 46 calls and restoration checks using the extracted kernel
and private hard disks. Release `QA/MSX/` media were not restaged. The new menu
APP itself is runtime-qualified on CPC here, not claimed as an additional
MSX/PCW application regression.

Host checks execute the actual bar fragments at 80 and 128 columns for initial,
idle, minute, menu clearing, fullscreen/exit and BCD behavior. Runtime assembly
checks cover repeatability, allocation overflow rejection, shared menu binding
and the independent pixel observer. Build-cache dependencies include both new
Desktop fragments.

Full `make check` passes in an isolated worktree: 206 Python tests with no
skips, plus the native C, ABI/SDK and distribution checks. Log:
`/tmp/geobench-77n-check.log`. The isolated copy excludes the preserved
user-owned `QA/CPC/` tree.

Local evidence: `/tmp/geobench-77n-{menus-final,runtime-final,fs-final,unit}.log`,
`/tmp/geobench-77n-msx{6,7}.log`, the `desktop-{before,after}` and
`kernel-{before,after}` logs under the same prefix. Menu snapshots and the
machine-readable result are in `/tmp/geobench-cpc-runtime-1p75zrof/`.
Compiler: SDCC 4.6.2, RASM 3.2.1. The 1984 executable SHA256 is
`00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`
(merged main `0851004`). No emulator changes were needed.

## Manual check

Use the installed tools in `my-distrobox`:

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-runtime
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Press **F6**. The `Menu ABI` window should gain focus and publish `Probe` and
`Tools` on the white top bar. Use arrows to move the pointer and Space to click.
Choose `Toggle` from either menu to change its content stripe; Escape cancels
a popup. Focus the exposed `Universal ABI` window: its empty menu replaces
those titles. Focus `Menu ABI` again: its titles return. Escape outside a popup
closes the focused app. F3 still opens ABI Probe; F5 runs the filesystem test.

For the automated checks:

```sh
make diagnostic-cpc-menus-1984
make diagnostic-cpc-runtime-1984
make diagnostic-cpc-portablefs-1984
```

These use private M4 images under `QA/Diagnostics/CPC-runtime`, not floppy boot
or the preserved user-owned `QA/CPC/`. Albireo and other CPC emulators remain
separate qualification work; PCW is not enabled.

## Remaining Desktop integration, in dependency order

1. Bind the existing shell/accessory registration and exact activation service,
   then qualify unchanged Calculator through it. Qualify Clock's real
   worker/timer path before enabling its required background capabilities.
   Do not lower APP manifest requirements to make either launch prematurely.
2. Bind the shared Desktop's native root, settings and menu/dialog services.
   The measured Desktop profile has data at `7D90..7ECD`, only 50 bytes below
   the `7F00` reservation. The 544-byte portable FS transport cannot simply be
   appended at that data location: rebudget code/data and service placement.
3. Connect existing icon/font/theme and wallpaper providers, not substitute
   artwork. Desktop directly reads picture/clip/UI/boot-path state; File Manager
   still has native file-loader fields and MSX screen-mode accesses alongside
   its context-based scanning. Give these explicit providers and retain shared
   policy before attempting their complete build. Loading and resource I/O
   must remain outside repaint callbacks.
4. Boot the real shared Desktop/File Manager from M4; prove Disk/Desk/System,
   navigation, launch, focus/exposure and error/cancel paths. Replace the
   temporary root/bar binding, then advance the wider application parity ledger.

This checkpoint closes only the shared bar/application-menu slice. It does
not close #77 or the overall production-adapter/Desktop gates.
