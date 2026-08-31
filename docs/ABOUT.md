# About GEOBENCH

A graphical desktop environment for the **Amstrad CPC**, **MSX2**, and
**Amstrad PCW** — a
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

## Original visual reference

The project began from this Amiga Workbench-style reference: labelled
drawer/app icons, windows with title bars and gadgets, a trashcan, and an arrow
pointer on an 8-bit display. The current screenshots in the top-level README
show the implemented desktop; this image records the starting visual direction,
not an unfinished UI specification.

![Visual target](../goal.png)

> Image: a screenshot from The 8-Bit Guy's video on the **C128 "Alternate
> Universe"** — used here purely as a visual reference for the look we're after.

## How it works

GEOBENCH borrows SymbOS's banked-app shape, scaled down and shared across three
Z80 platforms:

- **Banked memory model.** A target-specific mapper pages a 16K application
  block into `#4000-#7FFF`. The kernel and fixed low-RAM contracts remain
  mapped; applications, modules, assets, and borrowed document/picture pages
  use the expansion-bank pool.
- **Resident kernel (`kernel/`, Z80 asm).** Boots the target video backend,
  probes RAM, initializes the clock/top bar, owns storage + screen + input + cursor, and
  exposes a **fixed jump-table API** at `#8000`. The kernel source has been
  split by subsystem (`boot.asm`, `assets.asm`, `modules.asm`, `app_pool.asm`,
  `input_api.asm`, `clock.asm`, `memdetect.asm`, `api_table.inc`,
  `lowram.inc`) so resident responsibilities and low-RAM contracts are easier to
  reason about without changing the generated image.
- **Apps in C (`apps/`, SDCC).** Each app is compiled to run at `#4000` in a
  bank page. It reaches the kernel only through **`libgb`**
  (`lib/gb/` — `gb.h` + asm trampolines that map the C calling convention onto the
  jump table). Managed windows remain co-resident and are driven by the desktop's
  root task; I/O-heavy work is split into bounded jobs, while explicitly opted-in
  pure computation can run in preemptible workers.
- **Storage backends.** On CPC, a dispatcher (`lib/fs.asm`) selects the card
  backend at build time. The shipped card builds both the CH376 **Albireo** kernel (`GBALB`)
  and the **M4 board** kernel (`GBM4`) into one shared FAT image. Both kernels also
  carry the AMSDOS-over-**floppy** fallback. The FAT16/FAT32 **IDE** backend is
  archived — source kept in-tree, not built or shipped by default (see
  [`ARCHIVED.md`](ARCHIVED.md)). The screen-independent driver path can
  still be built as a legacy **loadable upper-ROM** experiment (`GBALB.ROM`) to
  study resident `#8000` headroom, but release media use the no-ROM kernels —
  see [Building](BUILDING.md#optional-the-geobench-rom). MSX2 uses MSX-DOS
  2/Nextor BDOS services; PCW uses its native CF2/CF2DD floppy backend.

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
  — frozen in-tree, not shipped; see [`ARCHIVED.md`](ARCHIVED.md). Telnet,
  NETTEST, WGET and Browser use Net4CPC/W5100S when running the Albireo kernel
  and M4ROM's TCP commands when running the M4 kernel.
- **MSX2** (V9938, 128K VRAM) running **MSX-DOS 2 / Nextor** — see
  [The MSX2 target](MSX2.md). Stock 128K RAM boots the desktop;
  a memory-mapper expansion (512K typical) is recommended for multiple app
  windows. Browser and Telnet use a mapped-RAM or page-3 TCP/IP UNAPI
  implementation; openMSXnet is the initial supported emulator transport.
- **Amstrad PCW** (PCW 8256/8512 class) with banked RAM and CF2 or CF2DD
  media. The monochrome 720x256 backend preserves the shared application and
  asset formats; serial networking uses PerryFi/PerryNet. See
  [The PCW target](PCW.md).

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

## Running existing DOS software

GEOBENCH does **not** run ordinary machine-code `.BIN` programs inside a
managed window. Those programs expect to own the machine under BASIC or DOS,
so the File Manager reports that they must be run after leaving GEOBENCH.

`.BAS` files are different: the bundled **GB-BASIC** package opens them in
`BASIC.APP`. GEOBENCH's native executable formats remain `.APP` applications
and `.SAV` screensavers.

This was an early aspiration ("layer on top of DOS, launch the existing
catalogue"), but coaxing software that assumes total machine ownership into a
managed desktop proved out of scope, so it is a non-goal rather than a
roadmap item.

## Non-goals

- Preempting the resident kernel, firmware, paged modules, storage drivers, or
  drawing operations. Release builds preempt explicitly opted-in pure app
  workers; shared machine services stay atomic under the desktop root task.
- Hard compatibility with actual GEOS or Workbench binaries. GEOBENCH is
  *inspired by* them, not a binary-compatible reimplementation.
- 100% feature parity with either ancestor.

## Tech notes

- **CPU:** Zilog Z80 (~3.5-4 MHz), banked 128K+ memory map.
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
├── apps/              # native C apps and screensavers
│   ├── desktop/       #   the boot shell: backdrop, icons, drag, launch, System menu
│   ├── filemgr/       #   scrolling file manager (multi-drive, drag-and-drop, Trash)
│   ├── notepad/       #   text editor (File/Edit/View menus, copy/paste, .BAS CR+LF)
│   ├── iconed/        #   icon/cursor editor for .IST sets and .SPR cursors
│   ├── paint/         #   GEMBENCH-owned MSX2 Paint variant
│   ├── xaos/          #   fixed-point Mandelbrot generator (.PIC export)
│   ├── viewer/        #   banked/demand-streamed .PIC image viewer
│   ├── clock/         #   analog clock window
│   └── settings/      #   control panel: config/media picker + desktop colours
├── components/
│   └── gb-basic/      # bundled BASIC editor, runtime, engine and examples
├── rom/               # optional CPC ROM/offload sources
├── assets/            # icon/cursor/picture sources + sample files (WELCOME.TXT)
├── docs/              # architecture, development, archive notes, review docs
└── tools/            # host-side build/asset tooling (build_kernel.sh, build_rom.sh, ...)
```

The MSX2 `PAINT.APP` source is owned in-tree so its application/window lifecycle
can evolve with GEMBENCH; CPC and PCW still take Paint from the sibling
`GB-PAINT` repository. GB-BASIC is owned in-tree under `components/gb-basic/`
and staged by the distribution build. Normal and preemptive release media do
not require a GEOBENCH ROM.
