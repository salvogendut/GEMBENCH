# About GEOBENCH

A graphical desktop environment for the **Amstrad CPC** and the **MSX2** — a
hybrid clone that borrows the best ideas from **Commodore GEOS** (C64/C128) and
the **Amiga Workbench**, reimagined for 8-bit Z80 hardware.

## What is this?

The Amstrad CPC shipped with Locomotive BASIC and AMSDOS: a perfectly capable
8-bit machine that never got a first-class graphical operating environment the
way the C64 did with GEOS or the Amiga did with Workbench/Intuition.

GEOBENCH aims to fill that gap. The goal is a mouse-and-icon desktop that feels
familiar to anyone who used a 16-bit Amiga, but runs within the constraints of
a 128K CPC.

### Why "GEOBENCH"?

**GEO**S + Work**BENCH**. Two of the most influential desktop metaphors of the
8/16-bit era, fused into one name.

### What about SymbOS?

To be clear up front: a genuine first-class, multitasking, windowed operating
system **already exists** for the Amstrad CPC — [**SymbOS**](https://www.symbos.de).
It is a remarkable engineering achievement, with preemptive multitasking, a full
window manager, and its own application ecosystem.

GEOBENCH is **not** an attempt to copy, compete with, or reimplement SymbOS.
SymbOS is its own complete OS and is far more ambitious (and complex) than what
this project sets out to do. Instead, GEOBENCH is a much humbler thing: a
**graphical desktop layer that sits on top of an existing disk operating system**
— standard **AMSDOS**, or a more capable DOS such as **UniDOS**. It keeps the
familiar DOS underneath and adds a GEOS/Workbench-style face on top, rather than
replacing the whole system. Smaller scope, smaller footprint, different goal.

## Visual target

The long-term look we're aiming for — an Amiga Workbench-style desktop as it
might have existed on the CPC: labelled drawer/app icons, windows with title
bars and gadgets, a trashcan, an arrow pointer.

![Visual target](../goal.png)

> Image: a screenshot from The 8-Bit Guy's video on the **C128 "Alternate
> Universe"** — used here purely as a visual reference for the look we're after.

We're a long way from this, but it's the north star.

## How it works

GEOBENCH borrows SymbOS's banked-app shape, scaled down:

- **Banked memory model.** On a 128K+ machine the gate-array RAM-config port
  pages a 16K block into the `#4000–#7FFF` window. The kernel, the stack, the
  screen and the firmware stay in always-resident RAM; apps and the kernel's data
  buffers (font, icons) live in bank pages and are swapped in as needed.
- **Resident kernel (`kernel/`, Z80 asm).** Boots the machine (Mode 1, palette,
  RAM probe, clock, top bar), owns storage + screen + input + cursor, and
  exposes a **fixed jump-table API** at `#8000`. The kernel source has been
  split by subsystem (`boot.asm`, `assets.asm`, `modules.asm`, `app_pool.asm`,
  `input_api.asm`, `clock.asm`, `memdetect.asm`, `api_table.inc`,
  `lowram.inc`) so resident responsibilities and low-RAM contracts are easier to
  reason about without changing the generated image.
- **Apps in C (`apps/`, SDCC).** Each app is a single `main.c` compiled to run at
  `#4000` in a bank page. It reaches the kernel only through **`libgb`**
  (`lib/gb/` — `gb.h` + asm trampolines that map the C calling convention onto the
  jump table). The desktop launches the file manager, which opens each file in its
  app (Notepad, ICONED, Paint, Viewer, ...); an app returns to its caller by `return`.
- **Storage backends.** A dispatcher (`lib/fs.asm`) selects the card backend at
  build time. The shipped card builds both the CH376 **Albireo** kernel (`GBALB`)
  and the **M4 board** kernel (`GBM4`) into one shared FAT image. Both kernels also
  carry the AMSDOS-over-**floppy** fallback. The FAT16/FAT32 **IDE** backend is
  archived — source kept in-tree, not built or shipped by default (see
  [`ARCHIVED.md`](ARCHIVED.md)). The screen-independent driver path can
  still be **offloaded to a loadable upper ROM** (`GBALB.ROM`) to free resident
  `#8000` RAM — see [Building](BUILDING.md#optional-the-geobench-rom).

## Target hardware

- **Amstrad CPC** (464 / 664 / 6128, and CPC+) with **128K+ RAM** (the banked app
  model needs the expansion banks; 512K is typical and fine). Larger expansions
  are **detected and reported** up to 1MB — the boot probe walks both the 8
  DK'tronics banks (port `&7F`) and the **Yarek / CPC4MB** upper-bank ports
  (`&7E…`), so the top bar shows the true total (e.g. **1088K** on a CPC464 with a
  1MB Yarek). The app-page pool draws from the detected banks; the space beyond
  what the windows use is free headroom (issue #138).
- Mode 1 (320×200, 4 colours) for the desktop.
- **Joystick / keyboard-driven software pointer.** An **AMX mouse works too** — it
  plugs into the joystick port and reports as a joystick (movement + buttons), so
  the same pointer path drives it (either fire button clicks). A **SYMBiFACE II /
  Cyboard PS/2 mouse** can be added for machines that have one.
- Albireo (CH376), M4 board, or AMSDOS floppy storage. The IDE backend is archived
  — frozen in-tree, not shipped; see [`ARCHIVED.md`](ARCHIVED.md). Telnet
  uses Net4CPC/W5100S when running the Albireo kernel and M4ROM's TCP commands
  when running the M4 kernel.
- **MSX2** (V9938, 128K VRAM) running **MSX-DOS 2 / Nextor** — see
  [The MSX2 target](MSX2.md). Stock 128K RAM boots the desktop;
  a memory-mapper expansion (512K typical) is recommended for multiple app
  windows.

## Design inspirations

We deliberately cherry-pick from both ancestors rather than cloning either one.

### From Commodore GEOS

- **It runs on tiny hardware.** GEOS proved a real WIMP desktop is possible on a
  1 MHz 8-bit CPU with 64K of RAM. That is the existence proof GEOBENCH stands on.
- **Proportional bitmap fonts** and a consistent system look.
- **A disk-based application model** — load apps from disk on demand, keep the
  resident kernel small.
- **Bundled productivity apps** in the spirit of geoWrite / geoPaint — Notepad and
  Paint are the first of these.

### From Amiga Workbench

- **The desktop metaphor proper:** draggable icons, windows, drawers (folders),
  and a trashcan.
- **Screens and windows** as the core UI primitives.
- **A clean, layered look** that treats the desktop as a workspace, not a menu.
- **Tools and drawers** the user can arrange spatially.

## Goals

- A resident **kernel** small enough to leave usable RAM for applications.
- A **desktop shell**: icons, windows, drawers, drag-and-drop, menus.
- A **graphics + windowing layer** abstracting the CPC's video hardware.
- A **mouse/input layer** with a software pointer.
- A small set of **bundled applications** to prove the platform is real.
- A documented **application API** (the `libgb` jump table) so third parties can
  write GEOBENCH apps — in C.

## Running existing AMSDOS software

GEOBENCH does **not** run ordinary AMSDOS `.BIN` binaries or BASIC `.BAS`
programs. Those expect to own the whole machine under BASIC/AMSDOS, so the
desktop does not attempt to launch or contain them: double-clicking a `.BIN` or
`.BAS` in the File Manager shows an info note telling you to run it from BASIC
instead (`RUN"PROG"`). GEOBENCH only runs its own apps — the C `.APP` programs and
`.SAV` screensavers — which cooperate with the kernel window manager.

This was an early aspiration ("layer on top of DOS, launch the existing
catalogue"), but coaxing software that assumes total machine ownership into a
cooperative desktop proved out of scope, so it is a non-goal rather than a
roadmap item.

## Non-goals (for now)

- Multitasking / preemptive scheduling (cooperative, single-app-at-a-time is the
  realistic start on a Z80).
- Hard compatibility with actual GEOS or Workbench binaries. GEOBENCH is
  *inspired by* them, not a binary-compatible reimplementation.
- 100% feature parity with either ancestor.

## Tech notes

- **CPU:** Zilog Z80 (~4 MHz), banked 128K+ memory map.
- **Kernel:** Z80 assembly, assembled with **RASM**.
- **Apps:** **C**, compiled with **SDCC**, linked against the shared `libgb`
  (`lib/gb/`) and a small crt0 to run as a banked binary at `#4000`.
- **Constraints:** every byte and cycle counts; apps share a 16K bank window.

## Project layout

```
geobench/
├── README.md
├── kernel/            # resident OS kernel (entry file + split subsystem asm/includes)
├── lib/               # kernel libraries: screen, text/font, input, cursor,
│   │                  #   fs (AMSDOS + FAT16), banking, icon/cursor bitmaps
│   ├── gbapp.inc      #   the app ABI (jump-table addresses, memory model)
│   └── gb/            #   libgb: shared C bindings (gb.h, gblib.s, crt0.s), the
│                      #     gb_doc menu/document framework (gbdoc.c), window
│                      #     drag/resize (gbwin.c) + dialog stubs (the dialog renderer
│                      #     is a paged kernel module, kernel/kc/gbui_mod.c)
├── apps/              # the C apps (each a single main.c)
│   ├── desktop/       #   the boot shell: backdrop, icons, drag, launch, System menu
│   ├── filemgr/       #   scrolling file manager (multi-drive, drag-and-drop, Trash)
│   ├── notepad/       #   text editor (File/Edit/View menus, copy/paste, .BAS CR+LF)
│   ├── iconed/        #   icon/cursor editor for .IST sets and .SPR cursors
│   ├── paint/         #   Mode-1 paint app (toolchest, palette, .PIC files)
│   ├── xaos/          #   fixed-point Mandelbrot generator (.PIC export)
│   ├── viewer/        #   text + .PIC image viewer
│   ├── clock/         #   analog clock window
│   └── settings/      #   control panel: config/media picker + desktop colours
├── rom/               # per-backend upper ROMs (GBALB.ROM shipped; IDE ROM archived)
│                      #   for driver offload + the boot banner
├── assets/            # icon/cursor/paint source PNGs + sample files (WELCOME.TXT)
├── docs/              # architecture, development, archive notes, review docs
└── tools/            # host-side build/asset tooling (build_kernel.sh, build_rom.sh, ...)
```
