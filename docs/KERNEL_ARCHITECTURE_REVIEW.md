# GEOBENCH Kernel Architecture Review

Date: 2026-06-28

> Historical review: this file is kept as the architectural audit trail from the
> 2026-06-28 cleanup pass. Several items called out below have since been
> implemented or partially implemented; use `docs/ARCHITECTURE.md`,
> `kernel/README.md`, `kernel/lowram.tsv`, and `lib/gbapp.inc` as the current
> contracts.

This review focuses on the resident kernel architecture, size pressure, and
modularity. It was based on the tree as it stood on the date above:
`kernel/gbkern.asm`, `lib/gbapp.inc`, `lib/gb/gblib.s`, `lib/gb/gb.h`, the
storage libraries, and the loadable kernel modules under `kernel/kc/` and
`kernel/modules/`.

## Executive Summary

GEOBENCH already has the right high-level shape for an 8-bit graphical OS:

- a small always-resident assembly nucleus at `#8000`;
- banked C apps at `#4000`;
- a fixed jump-table ABI;
- shared graphics/input/storage code in assembly;
- on-demand modules for bulky logic such as dialogs, config parsing, networking,
  and write paths;
- an optional upper-ROM offload path for low-level storage drivers.

The main architectural problem is not the concept. It is that the kernel has
outgrown its original file and contract structure. `kernel/gbkern.asm` now mixes
boot, ABI dispatch, app loading, the window manager, chrome rendering, resource
loading, module dispatch, drive state, drag-and-drop, clipboard, RTC, memory
probing, and distribution packaging. The code is readable in places, but the
boundaries are implicit and maintained by comments.

The best route to a smaller and more modular kernel is incremental:

1. Make the contracts machine-checkable: ABI table, low-RAM map, module ABI, and
   build-size budget.
2. Split `gbkern.asm` by subsystem without changing generated code.
3. Remove resident compatibility and policy paths that no current app uses.
4. Convert PIC-specific and modal-app services into smaller generic primitives.
5. Keep hot hardware/page-switch/compositor code in assembly, but continue moving
   branchy policy into C modules or apps.

## Current Architecture

The system is effectively a cooperative, banked, single-machine-owner OS:

- `kernel/gbkern.asm` lives at `#8000+`, owns boot, memory banking, input,
  pointer, screen services, app loading, window management, modules, and system
  state.
- `APP_BASE` is `#4000`, with bank pages swapped into `#4000-#7FFF`.
- `PAGE_DATA` stores font/icon assets and is also used as the load area for
  `DATA_MODTOP` modules at `#6000`.
- Apps are SDCC binaries linked against `lib/gb`.
- Apps call fixed jump table slots directly through `lib/gb/gblib.s`.
- Loadable modules communicate through fixed low-RAM transfer blocks.
- Storage is dispatched through `lib/fs.asm`; the shipped path is Albireo or M4
  plus AMSDOS floppy fallback, while IDE remains archived but buildable.

This is a strong base. The architecture only needs more explicit boundaries.

## Major Findings

### 1. The ABI authority has drifted

`lib/gbapp.inc` says it is the app ABI authority, but it stops at `GB_WMRUN`
(`#805A`). The live jump table in `kernel/gbkern.asm` continues through many
more entries: `GB_WMADD`, `GB_WMOPEN`, `GB_WMCLOSE`, `GB_WMSETPOS`,
`GB_ISDIR`, `GB_DRAGSTART`, `GB_CLIPSET`, `GB_UI`, `GB_WMMANAGED`,
`GB_BACKDROP`, `GB_RELOAD`, `GB_NET`, and others.

`lib/gb/gblib.s` therefore hardcodes addresses such as `0x80B7` and `0x80BD`
without a complete shared include. `lib/gb/gb.h` also exposes low-RAM addresses
directly.

Recommended fix:

- Make one ABI source of truth.
- Generate or include the same symbols into:
  - `kernel/gbkern.asm`;
  - `lib/gb/gblib.s`;
  - app-facing C headers;
  - architecture docs.
- Rename reused/dead slots explicitly. For example, slots that used to be
  `GB_XORFRAME` / `GB_ONREPAINT` are now `GB_PICOPEN` / `GB_PICBLIT`. If old
  apps are not supported, state that the ABI is "kernel/app set versioned",
  not stable forever.
- Add an ABI version cell or API call so an app can reject an incompatible
  kernel instead of jumping into a slot with changed meaning.

Started in `kernel-architecture-cleanup`: `lib/gbapp.inc` now lists the live
jump table through `GB_NET` instead of stopping at `GB_WMRUN`, and
`tools/check_abi_table.py` validates it against `kernel/gbkern.asm`.

### 2. The low-RAM map is too implicit

The kernel and modules use fixed low-RAM ranges for many contracts:

- config text and parsed names at `#1000..#123B`;
- RTC / boot / RAM-size cells at `#1240..#1248`;
- backdrop tile at `#1250`;
- ROM offload transfer/state cells around `#1254..#1293`;
- cursor save-under around `#1291`;
- app/window state around `#1300..#144B`;
- scratch overlays around `#1450..#14D1`;
- cursor sprite at `#1500`;
- UI dialog block at `#1700`;
- sector buffers at `#1800` and `#1A00`;
- module file/net buffers at `#2200`;
- clipboard at `#3E00`.

This map works because the code is carefully hand-managed, but it is fragile.
Several C files and apps also define these raw addresses themselves.

Recommended fix:

- Create a single low-RAM manifest with named ranges, start, end,
  owner, and lifetime.
- Generate `lib/gb/lowram.h` from it for C apps/modules.
- Add build-time overlap checks for every configuration: shipped Albireo,
  shipped M4, Albireo+ROM, and IDE recovery.
- Treat overlays as first-class. For example, `#1700` and `#2200` are valid
  module-transfer overlays because GBUI, GBFAT, FLOPPYSV, and GBNET are never live
  at the same time. The manifest should say that explicitly.

Important detail to verify:

The optional ROM build appears to have low-RAM pressure around the same addresses
used by backdrop/cursor state. In the current source:

- `BD_TILE` is `#1250..#128F`;
- `FSAM_STATE_BASE` starts at `#1256`;
- `FSAM_IO_*` runs through `#1292`;
- `cur_bg` is `#1291..#12D0`;
- Albireo ROM state uses `alb_path #1293..#12D2` and `fsalb_mounted #12D3`.

This may be protected by build assumptions, but the comments describe these as
free gaps in different places. A mechanical low-RAM range check would make this
safe and would catch future collisions immediately.

Started in `kernel-architecture-cleanup`: `kernel/lowram.tsv` records the fixed
ranges and `tools/check_lowram_map.py` validates overlap rules. The shipped
Albireo profile passes; archived/optional ROM profiles deliberately still report
the low-RAM pressure above.

### 3. `gbkern.asm` needs source-level modules

The resident binary can remain one assembled image, but the source should be
split. Today `gbkern.asm` is about 3,500 lines before included libraries, and it
contains many independent subsystems.

Recommended split, initially with no behavior change:

- `kernel/gbkern.asm`: build flags and top-level include order.
- `kernel/api_table.inc`: `org GB_KERNEL` and the fixed jump table.
- `kernel/boot.asm`: `kernel_main`, boot spike harnesses, desktop launch, and
  `GB_EXIT` return-to-BASIC path.
- `kernel/lowram.inc`: fixed low-RAM equates and ROM offload low-RAM includes.
- `kernel/lowram.tsv`: checked ownership/range manifest for those fixed cells.
- `kernel/assets.asm`: font/icon/cursor/backdrop loading, boot splash progress,
  `GB_RELOAD`, and `GB_BACKDROP`.
- `kernel/config_module.asm`: boot-time `GBCFG.MOD` loading and config defaults.
- `kernel/modules.asm`: shared `run_data_module`, `GB_UI`, and `GB_NET`.
- `kernel/app_pool.asm`: page pool allocation/free.
- `kernel/wm_core.asm`: z-order, focus, repaint, hit testing.
- `kernel/wm_chrome.asm`: managed-window frame/title/close/maximize handling.
- `kernel/fs_api.asm`: `GB_FSLOAD`, `GB_FSSAVE`, drive switching, copy/delete.
- `kernel/input_api.asm`: poll, keyboard, top-bar event dispatch.
- `kernel/clock.asm`: RTC/software clock and `GB_TIME`.
- `kernel/memdetect.asm`: RAM probing.

This does not shrink the binary by itself, but it makes later size cuts safer.

### 4. The module system is good, but should be formalized

The code already uses a solid pattern:

- module loaded to `DATA_MODTOP` (`#6000`) in `PAGE_DATA`;
- request and result in low RAM;
- resident kernel owns disk/device access and page switching;
- module handles branchy logic or bulky code.

Examples: `GBUI.MOD`, `GBNET.MOD`, `GBCFG.MOD`, `GBFAT.MOD`, `FLOPPYSV.MOD`.

The issue is that each module hand-defines its own ABI. This is still manageable,
but it will get hard as more logic moves out of the resident kernel.

Recommended fix:

- Define a small standard module header or convention:
  - magic/version;
  - operation byte;
  - result byte/word;
  - low-RAM buffer pointer/capacity;
  - clobbered registers;
  - whether the caller page remains mapped.
- Put shared module transfer addresses in one include/header.
- Move `GBCFG.MOD` toward the same `DATA_MODTOP` runner if it fits. It is now
  loaded app-style at `#4000`, while UI and network use the shared `run_data_module`
  path at `#6000`.

### 5. Some resident services are legacy compatibility

The live app set has moved to co-resident windows and kernel-managed chrome.
Several old ABI slots are stubs or no longer used:

- `GB_PRINT`;
- `GB_QUIT`;
- `GB_LAUNCH`;
- old `GB_XORFRAME`;
- old `GB_ONREPAINT`;
- old `GB_BLITE` (`GB_BLITEFULL`'s table slot has since been repurposed as
  `GB_FSFREE`, a small free-space query used by File Manager);
- old `GB_WMLAUNCH`.

The slots cost only 3 bytes each, so the table itself is not the problem. The
larger opportunity is the remaining implementation behind old models.

Concrete size candidate:

- `launch_app` still supports modal/nested apps and is used to start the desktop.
  Current apps appear to use `gb_wm_open` / `gb_wm_launch_as` instead.
- Replace the boot use with a smaller `boot_desktop` path that allocates/maps
  `PAGE_APP0`, loads `DESKTOP.APP`, and calls it.
- Keep `GB_RUN` / `GB_LAUNCH` as reserved stubs unless there is a current app or
  external-app compatibility requirement.

This should reclaim more than simply deleting dead jump-table entries.

### 6. `GB_PIC*` is too format-specific for the kernel

`k_pic_open` loads a file into a borrowed app bank and parses `.PIC` headers,
storing `PIC_WB`, `PIC_H`, and `PIC_OFF` in low RAM. The Viewer and Desktop then
use this service for large pictures and wallpaper.

This is useful, but it makes the kernel know a user file format. The Viewer
already knows how to parse `.PIC` in its in-page path.

Recommended replacement:

- Provide generic bank services:
  - allocate/free a banked page;
  - load the focused file into that page;
  - blit a rectangle from a selected bank/page to screen;
  - maybe return byte count.
- Let Viewer/Desktop parse `.PIC` in C.

The kernel stays responsible for bank ownership and fast blit mechanics, but file
format policy leaves the resident nucleus.

### 7. Kernel-managed chrome is a good tradeoff, but keep it narrow

The managed-window model is a good architectural improvement: apps supply content
and a single procedure, while the kernel owns frame/title/close/drag/resize. This
saves duplicated app code and gives a consistent UI.

However, window chrome is now one of the biggest resident policy areas. Do not move
the hot WM loop or page switching out of the kernel, but keep asking whether each
new UI feature belongs resident.

Guidelines:

- Keep resident:
  - focus/z-order/page mapping;
  - hit testing;
  - repaint sequencing;
  - cursor integrity;
  - small chrome primitives used every frame.
- Avoid resident:
  - app-specific menu policy;
  - file-type routing;
  - document behavior;
  - image/file parsing;
  - heavyweight dialogs;
  - optional features like networking frontends.

This is mostly how the tree is moving already. Continue that direction.

### 8. Packaging is mixed into the kernel assembly source

The bottom of `gbkern.asm` contains `incbin` packaging and `save` statements for
kernel, apps, modules, fonts, icons, splash, cursors, and disk images. Extra
`pack_apps*.asm` passes handle overflow.

This is practical with RASM, but it means the runtime kernel source is also a
distribution script.

Recommended fix:

- Keep `gbkern.asm` responsible for producing `GBKERN.RAW` / `GBKERN.BIN`.
- Move disk packaging into generated or dedicated packer assembly files driven by
  a manifest.
- Use a manifest for app/module names and disk placement, then generate the RASM
  `save` blocks.

This will not shrink the resident image, but it reduces accidental coupling and
makes adding/removing modules safer.

### 9. Documentation was stale in key places

Several examples from the original review have since been addressed: the kernel
README now describes the active source split, `lib/gbapp.inc` lists the live ABI
through `GB_NET`, and `tools/check_abi_table.py` validates the table. The remaining
rule is operational rather than architectural: keep `docs/ARCHITECTURE.md` as the
current-behavior document and keep older design records clearly marked as
historical.

## Concrete Size-Reduction Opportunities

The highest-value cuts are likely these:

1. Remove the modal app runner from the resident kernel if no current app needs
   it. Replace boot with a small desktop-only launcher and reserve the public
   legacy slots.

2. Replace `GB_PICOPEN` / `GB_PICBLIT` / `GB_PICCLOSE` with generic banked file
   buffer services. Move `.PIC` parsing back to Viewer/Desktop C code.

3. Move `GBCFG.MOD` to the common `DATA_MODTOP` module runner and delete special
   app-style config-module loading if the module fits.

4. Add build flags for optional resident features:
   - networking call gate if no Telnet/network distribution is wanted;
   - boot splash;
   - maximize gadget;
   - large-picture bank services.

5. Keep old ABI slots as cheap stubs, but do not keep old implementations unless
   an app actually calls them.

6. Continue moving branchy policy to C modules or apps, not into resident C.
   The existing `kernel/kc/README.md` is correct on the important point: C is
   clearer, but resident SDCC code is expensive on Z80. C belongs in paged modules
   unless the routine is tiny and cold.

## Modularity Roadmap

### Phase 1: Contract Hygiene

No behavior change.

- Create authoritative ABI include/header.
- Create low-RAM map manifest and overlap checker.
- Add a size report for resident kernel, modules, and apps.
- Update stale docs.
- Add build checks for:
  - Albireo shipped kernel;
  - Albireo + ROM;
  - M4 shipped kernel;
  - IDE recovery.

### Phase 2: Source Split

No intended binary change.

- Split `gbkern.asm` into subsystem includes.
- Move packaging-only `incbin`/`save` logic out of the runtime kernel source.
- Group module runners and transfer blocks.

### Phase 3: Resident Shrink

Behavior-preserving where possible.

- Replace modal launch path with a desktop boot path.
- Generalize the banked picture service.
- Unify config/UI/net module loading.
- Compile optional features behind explicit size profiles.
- Measure each change in resident bytes and app bytes.

### Phase 4: Cleaner External App Story

Only needed if third-party apps are a goal.

- Freeze ABI semantics or add version negotiation.
- Stop reusing old slots for new meanings.
- Publish a small app SDK: ABI constants, low-RAM public cells, module rules,
  and app fit constraints.

## Final Recommendation

Do not rewrite the kernel in C. Keep the assembly nucleus. The better split is:

- assembly for the ABI gate, banking, input polling, cursor, screen primitives,
  repaint sequencing, and storage leaf calls;
- C apps for all user-facing policy;
- C loadable modules for branch-heavy shared services;
- optional ROM for low-level drivers when resident RAM is the bottleneck.

The biggest immediate improvement is not a clever compression trick. It is making
the ABI and low-RAM map explicit and checked. After that, removing modal-launch
legacy and format-specific picture parsing should give the cleanest resident-byte
wins without destabilizing the desktop model.
