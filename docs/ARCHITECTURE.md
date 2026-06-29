# GEOBENCH Architecture

This is the current system shape, not a speculative design note. The quick
summary lives in the top-level README; this file describes the actual runtime
boundaries and the places where the current implementation is intentionally
constrained.

## Layer cake

GEOBENCH is organised as layers, lowest (closest to hardware) at the bottom:

```
┌─────────────────────────────────────────────┐
│  apps/  desktop·filemgr·notepad·iconed·       │  ← banked binaries, run on demand
│         paint·viewer·clock (C)                │
├─────────────────────────────────────────────┤
│  libgb  C bindings -> the kernel jump table,  │  ← lib/gb/ (gb.h + trampolines,
│         window + dialog helpers               │     gbwin.c, gbdlg.c/gbprompt.c)
├─────────────────────────────────────────────┤
│  kernel/   boot · API table · banking · fs ·  │  ← resident; Z80 asm
│            assets · modules · input · WM       │
├─────────────────────────────────────────────┤
│  Amstrad CPC hardware  (Z80, CRTC, gate array, AMSDOS)│
└─────────────────────────────────────────────┘
```

Each layer only calls **down** through documented entry points. Apps never touch
video, storage or input hardware directly. They go through the kernel ABI in
`lib/gbapp.inc`, reached from C via `libgb`. The desktop is itself an app; it is
the first one booted and the one other apps return to.

## Memory model

128K+ only (the banked app model needs the expansion banks). The gate-array
RAM-config port pages a 16K block into the `#4000–#7FFF` window:

- The **kernel is resident** in always-mapped RAM at `#8000+`. So are the stack,
  the screen, fixed low-RAM contracts, and the firmware.
- The kernel's **data buffers** (font, icon set, directory scratch) live in a
  bank page (`PAGE_DATA`); a service swaps that page in, touches the buffer, and
  restores the caller's page.
- **Apps are loaded into bank pages** (`PAGE_APP0+`) at `#4000` and run there.
  They nest: desktop -> filemgr -> (notepad/paint/viewer/...), each in its own
  page; the launcher keeps the caller's page on the stack and restores it on quit.

## Kernel source layout

The resident binary is still one assembled image, but the source is now split by
subsystem so responsibilities are explicit:

- `kernel/gbkern.asm` — top-level assembly order and build flags.
- `kernel/api_table.inc` — the fixed kernel jump table.
- `kernel/lowram.inc` / `kernel/lowram.tsv` — absolute low-RAM ownership and the
  checked manifest used by `tools/check_lowram_map.py`.
- `kernel/boot.asm` — boot path, desktop launch, return-to-BASIC path.
- `kernel/assets.asm` — font/icon/cursor/backdrop/wallpaper reload helpers.
- `kernel/config_module.asm` — `GBCFG.MOD` boot-time parse/load path.
- `kernel/modules.asm` — shared paged-module runners (`GBUI`, `GBNET`, config).
- `kernel/app_pool.asm` — bank-page allocation/free for apps and borrowed pages.
- `kernel/input_api.asm` — pointer/keyboard polling and top-bar dispatch.
- `kernel/clock.asm` / `kernel/memdetect.asm` — RTC/timekeeping and RAM probe.

The split is meant to keep the generated kernel image stable while making future
size work safer.

## Execution model

Cooperative and single-foreground-app to start:

- One application has the foreground at a time.
- The desktop runs an event loop; when it launches an app, control transfers to
  the app's own event loop until the user quits.
- A vblank interrupt drives lightweight housekeeping (pointer, cursor blink,
  timers) regardless of who has the foreground.

Preemptive multitasking is explicitly out of scope. GEOBENCH is cooperative and
single-foreground by design.

## The system API

Applications reach system services through a fixed **jump table** at `#8000`.
Each entry is a 3-byte `jp`, so slot addresses stay stable as the kernel grows.
`lib/gbapp.inc` is the authority; `tools/check_abi_table.py` verifies the
exported table against the kernel source. C apps call the table through `libgb`.
Current service groups:

- **Drawing** — text (`gb_text`), filled rects (`gb_fill`), outlines
  (`gb_frame`), icons (`gb_icon`/`gb_blite`), windows (`gb_window`).
- **Input + cursor** — `gb_poll` (pointer position + click/quit/fire),
  `gb_curshow`/`gb_curhide`.
- **Files** — directory iteration, load/save/delete/copy, drive selection, and
  system-file loading through the active storage backend.
- **Apps / WM** — open/close windows, managed chrome, app launch, fullscreen,
  focus/z-order, drag-and-drop, clipboard, top-bar integration.
- **Modules / services** — config parsing, UI/file dialogs, networking, media
  reload, backdrop/wallpaper helpers, RTC/time, RAM total.

Keeping this explicit jump table is what lets apps stay as separate C binaries
without linking against private kernel internals.

## Storage and distribution shape

The shipped runtime target is:

- **Albireo / CH376 card** as the primary storage path.
- **AMSDOS floppy** as the fallback path and as the bootable disk-pair format.

The archived storage backends still exist in source but are not built by the
default workflow:

- **M4** is parked on an unresolved real-hardware timing/load issue.
- **IDE** is kept as a recovery target, not a shipped one.

See [`ARCHIVED.md`](ARCHIVED.md) for the exact support boundary.

The default media layout is intentionally simple:

- card: `QA/CARD/` with `GB.BAS`, `GBALB.BIN`, `GEOBENCH.CFG`, and `GBENCH/`
- floppy: `QA/GEOBENCH.DSK` (Main) plus `QA/COMPANION.DSK` (drive-B extras)

## Settings and media contracts

`GEOBENCH.CFG` is the user-visible configuration contract. The important current
rules are:

- backdrop, wallpaper, and saver names may be **drive-qualified** (`A:NAME`,
  `B:NAME`, `C:NAME`) so the Settings app can point at either floppy or Albireo
  content explicitly;
- backdrop and wallpaper are treated as mutually exclusive desktop background
  sources;
- invalid configured media falls back safely to `SOLID` / `NONE` during boot so
  the machine still reaches the desktop;
- screensavers are just full-screen `.SAV` apps launched by the desktop idle
  timer.

The intent is to keep policy in apps or modules and keep the resident kernel at
the level of asset reload, storage, and window-manager primitives.

## Hardware notes

- **Video:** Mode 1 (320×200, 4 colours) is the planned default desktop surface
  — a compromise between resolution and the ~16K framebuffer cost. The graphics
  library isolates the Mode 1 byte/pixel layout so other modes remain possible.
- **CPC vs CPC+:** addressed behind named constants; the plus's extra features
  (hardware sprites, palette) are a possible enhancement, not a dependency.
- **AMSDOS:** file I/O goes through firmware vectors. Note that USB/FAT-drive
  AMSDOS shifts some CAS IN vectors — see the sibling `n4c-nettools` notes.

## Known architectural limits

- **128K+ only.** The app model depends on banked memory.
- **Cooperative execution only.** No preemptive multitasking.
- **Flat-ish content layout.** Nested subdirectories deeper than one level are
  not a supported storage workflow today; see [`File_Manager_Issue.md`](File_Manager_Issue.md).
- **Legacy AMSDOS launching** is still a roadmap item, not a supported feature.

## Booting and distribution

`bash tools/build_kernel.sh` stages (and ships under `QA/`):

- **`QA/CARD/`** — for the Albireo card: `GB.BAS`, `GBALB.BIN`,
  `GEOBENCH.CFG`, and a `GBENCH/` subfolder holding the kernel-loaded payload
  (apps, modules, fonts, icons, cursor, media).
- **`QA/GEOBENCH.IMG`** — a ready-to-flash **Albireo** FAT16 card image, rebuilt
  by `tools/build_card_img.sh`; local artifact, not committed.
- **`QA/GEOBENCH.DSK`** — the **Main** flat bootable floppy: the OS (kernel/loader/modules/
  fonts/icons/cursor/config), the core apps (Desktop, Notepad, Clock, File Manager, Viewer,
  Settings, Iconed), the default `CIRCLE.SAV` saver, the `LOGO.PIC` wallpaper and the
  backdrops. Built by `kernel/gbkern.asm` + `pack_apps{,2,3}.asm` (#250).
- **`QA/COMPANION.DSK`** — the **Companion** floppy (#250): a non-bootable DATA disk with
  the extras — Paint, Telnet, Xaos, the full screensaver set, and the gallery pictures.
  Built by `kernel/pack_comp{1,2,3}.asm`. It is meant for **drive B** while the Main floppy
  stays in drive A: the kernel's system loader (`fs_load_sys`, `lib/fs.asm`) tries the boot
  drive (A) first and **falls back to the browse drive** (B), so a Companion app launched
  from a drive-B File Manager loads from B while its shared dependencies (`GBUI.MOD`,
  `GBNET.MOD`, `PAINT.IST`) load from A — no duplicates on the Companion. (The Albireo card
  is unaffected — it already ships everything on one volume.)

`RUN"GB` runs `GB.BAS`. On card media it `RUN"`s `GBALB`; on floppy media it
`RUN"`s `GBKERN`. The kernel then loads from `/GBENCH` on card media and from the
flat root on floppies.

The loader is **BASIC, not machine code**, on purpose: under UniDOS (CP/M-based) a
`RUN"`-loaded binary that returns triggers a warm-boot, the firmware CAS goes to tape,
and the DOS's RSXs/BIOS are unreachable from a loaded binary — whereas a BASIC program
runs with the DOS fully active, so its `RUN"GBALB` or `RUN"GBKERN` simply works.

### The GEOBENCH ROM (driver offload + boot banner)

The screen-independent low-level drivers — the FAT read/write core, the AMSDOS floppy
reader, the IDE backend and the CH376/Albireo backend — can run from a **16K loadable
upper ROM** instead of the resident kernel, freeing `#8000` RAM (the headroom that
unblocks window-chrome work like #156). `tools/build_rom.sh` builds one per card:
`rom/GEOBENCH.ROM` (IDE) and `rom/GBALB.ROM` (Albireo).

A driver call pages the ROM in (`OUT (#7F),#85` — upper ROM on, **lower** ROM off so
low-RAM scratch stays visible; `#7F81` would overlay the firmware lower ROM and corrupt
it), `OUT (#DF)` selects the ROM number, and the kernel `CALL`s a fixed dispatch slot.
The ROM is read-only, so each backend's writable state is relocated to fixed low RAM that
both the resident stubs and the ROM agree on (the FAT core at `#1C00`, the CH376 path at
`#1293`, a transfer area at `#1270`). The resident kernel is built with `-DGB_ROM_REQ=1`
to use the stubs; without the ROM the plain kernel runs every driver resident, so the ROM
is optional.

The same image is a standard CPC **background ROM** (type-1 header at `#C000`):
the firmware initialises it at cold boot and it prints a `GEOBENCH <commit>`
banner before BASIC's prompt. The offload dispatch table lives just past the
header.
