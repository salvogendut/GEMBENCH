# GEOBENCH Architecture

The core is built: a banked, resident kernel running separate-binary C apps. This
doc is the deeper design rationale; the README's "How it works" is the quick
summary. Some sections below (legacy launching, the plus, networking) are still
forward-looking.

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
│  kernel/   boot · banking · screen · text ·   │  ← resident; Z80 asm
│            input · cursor · fs · loader · API  │
├─────────────────────────────────────────────┤
│  Amstrad CPC hardware  (Z80, CRTC, gate array, AMSDOS)│
└─────────────────────────────────────────────┘
```

Each layer only calls **down** through documented entry points. Apps never touch
video, storage or input hardware directly — they go through the kernel API
(`lib/gbapp.inc`), reached from C via `libgb`. The desktop is itself an app; it's
the first one booted and the one apps return to.

## Memory model

128K+ only (the banked app model needs the expansion banks). The gate-array
RAM-config port pages a 16K block into the `#4000–#7FFF` window:

- The **kernel is resident** (in always-mapped RAM at `#8000+`), kept small. So
  are the stack, the screen, and the firmware.
- The kernel's **data buffers** (font, icon set, directory scratch) live in a
  bank page (`PAGE_DATA`); a service swaps that page in, touches the buffer, and
  restores the caller's page.
- **Apps are loaded into bank pages** (`PAGE_APP0+`) at `#4000` and run there.
  They nest: desktop -> filemgr -> (notepad/paint/viewer/...), each in its own
  page; the launcher keeps the caller's page on the stack and restores it on quit.

## Execution model

Cooperative and single-foreground-app to start:

- One application has the foreground at a time.
- The desktop runs an event loop; when it launches an app, control transfers to
  the app's own event loop until the user quits.
- A vblank interrupt drives lightweight housekeeping (pointer, cursor blink,
  timers) regardless of who has the foreground.

Preemptive multitasking — the Amiga's signature — is explicitly *not* a v1 goal.

## The system API

Applications reach system services through a fixed **jump table** at `#8000` —
each entry a 3-byte `jp`, so addresses stay stable as the kernel grows.
`lib/gbapp.inc` is the authority; C apps call it through `libgb` (`lib/gb/`).
What's there today:

- **Drawing** — text (`gb_text`), filled rects (`gb_fill`), outlines
  (`gb_frame`), icons (`gb_icon`/`gb_blite`), windows (`gb_window`).
- **Input + cursor** — `gb_poll` (pointer position + click/quit/fire),
  `gb_curshow`/`gb_curhide`.
- **Files** — directory iteration (`gb_dir1`/`gb_dirn`), load a file
  (`gb_fs_load`). Write is still to come.
- **Apps** — launch by name (`gb_run`) or by file type (`gb_launch`).

Keeping this an explicit, stable jump table is what lets apps be separate
binaries — written in C — without linking against private kernel internals.

## Launching legacy AMSDOS software

GEOBENCH sits *on top of* AMSDOS/UniDOS, so the desktop should be able to launch
the CPC's existing catalogue — `.BIN` binaries and `.BAS` programs — from an
icon (see the README's "Running existing AMSDOS software"). The user picks
**fullscreen** or **windowed**; these are very different problems.

### Fullscreen (the tractable case)

The safe, always-works path. Most CPC software assumes it **owns the machine**:
full memory, its own video mode, direct hardware access. So GEOBENCH steps
aside rather than trying to contain it:

1. The desktop **parks its state** — ideally persisting enough to disk/spare
   bank to fully reconstruct itself, since the launched program may clobber all
   of RAM and the video mode.
2. Control transfers to the program via the normal firmware path (`RUN"PROG"`
   for BASIC; RSX / CAS / AMSDOS load-and-execute for `.BIN`).
3. The program runs as if GEOBENCH weren't there.
4. **Return is the hard part of even this case:** most CPC programs exit by
   reset or by returning to BASIC, not by calling back into us. Likely options:
   require a reset-and-reload of the desktop, install a return hook where the
   firmware allows it, or simply accept "exit = reboot to desktop." To be
   decided.

### Windowed (the research problem)

Genuinely running an *uncooperative* legacy program inside a desktop window is
the hard, best-effort case and **will not work for every title**. The only
realistic mechanism on real hardware is to **intercept the program's firmware
output** (TXT/GRA VDU calls) and redirect it into a window region instead of the
real screen — which only works for programs that:

- go through the **firmware** for text/graphics rather than writing the
  framebuffer directly,
- **don't switch video mode** out from under the desktop,
- **don't claim memory** the desktop needs (including the firmware workspace /
  screen RAM the desktop is using),
- **don't take over interrupts** or otherwise assume exclusive control.

That basically limits windowed mode to well-behaved BASIC programs and
firmware-only software. Anything that bangs the hardware (most games, most demos)
cannot be contained and must fall back to fullscreen. The desktop should
**detect or heuristically guess** when windowing is unsafe and fall back to (or
warn and offer) fullscreen.

Native GEOBENCH apps sidestep all of this by cooperating with the windowing
layer from the start — the above is purely about coaxing *legacy* binaries in.

## Hardware notes

- **Video:** Mode 1 (320×200, 4 colours) is the planned default desktop surface
  — a compromise between resolution and the ~16K framebuffer cost. The graphics
  library isolates the Mode 1 byte/pixel layout so other modes remain possible.
- **CPC vs CPC+:** addressed behind named constants; the plus's extra features
  (hardware sprites, palette) are a possible enhancement, not a dependency.
- **AMSDOS:** file I/O goes through firmware vectors. Note that USB/FAT-drive
  AMSDOS shifts some CAS IN vectors — see the sibling `n4c-nettools` notes.

## Booting and distribution

One image works on any machine. `bash tools/build_kernel.sh` stages (and ships under
`QA/`):

- **`QA/CARD/`** — for an IDE or Albireo card: the BASIC loader `GB.BAS`, both per-card
  kernels `GBIDE.BIN` (FAT16/FAT32 over IDE) and `GBALB.BIN` (CH376/Albireo),
  `GEOBENCH.CFG`, and a `GEOBENCH/` subfolder holding everything the kernel loads at
  boot (apps, modules, fonts, icons, cursor). The card root stays clean next to
  SymBOS/CP/M/UniDOS files.
- **`QA/GEOBENCH.IMG`** — a ready-to-flash card image: one partitioned **FAT16** disk
  (MBR partition at sector 32) that boots on **both** backends — the SYMBiFACE IDE reads
  the partition table, the Albireo CH376 auto-detects the FAT. Rebuilt every build
  (`tools/build_card_img.sh`); a local artifact, not committed.
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

`RUN"GB` runs `GB.BAS`, which probes the bus (an IDE register read-back, then a CH376
`CHECK_EXIST`) and `RUN"`s the matching kernel. The kernel then loads from `/GEOBENCH`
(the IDE backend walks the FAT subdirectory; the Albireo backend prefixes its CH376
path), falling back to a flat root on floppies.

The loader is **BASIC, not machine code**, on purpose: under UniDOS (CP/M-based) a
`RUN"`-loaded binary that returns triggers a warm-boot, the firmware CAS goes to tape,
and the DOS's RSXs/BIOS are unreachable from a loaded binary — whereas a BASIC program
runs with the DOS fully active, so its `RUN"GBIDE` simply works.

### The GEOBENCH ROM (driver offload + boot banner, #152)

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

The same image is a standard CPC **background ROM** (type-1 header at `#C000`): the
firmware initialises it at cold boot and it prints a `GEOBENCH <commit>` banner before
BASIC's prompt, like M4 or SymbOS. The offload dispatch table lives just past the header.

## Open questions

- Relocatable app binaries vs fixed load address + banking?
- Icon / resource file format on disk.
- How much of the desktop is "just an app" vs privileged.
- Minimum viable target: commit to 128K, or keep 64K alive?
- Launching legacy software: how does the desktop **survive a fullscreen
  takeover and reload itself** on return (reset-and-reload vs return hook)?
- Windowed legacy mode: is **firmware output interception** worth building, and
  how does the desktop **decide a program is safe to window** vs force
  fullscreen?

These get answered as the kernel and graphics library take shape.
