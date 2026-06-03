# GEOBENCH

A graphical desktop environment for the **Amstrad CPC** — a hybrid clone that
borrows the best ideas from **Commodore GEOS** (C64/C128) and the **Amiga
Workbench**, reimagined for 8-bit Z80 hardware.

> **Status:** a working **banked multi-app micro-OS** for 128K+ CPCs. A resident
> Z80 **kernel** owns the machine and exposes a fixed jump-table API; the
> **apps are written in C** (SDCC) and run co-resident in expansion-bank pages,
> reaching the kernel through a small `libgb`. The desktop, a scrolling file
> manager, and a text viewer all work: double-click a drive to browse it,
> double-click a file to open it in its app. Build with `tools/build_kernel.sh`.

## Visual target

The long-term look we're aiming for — an Amiga Workbench-style desktop as it
might have existed on the CPC: labelled drawer/app icons, windows with title
bars and gadgets, a trashcan, an arrow pointer.

![Visual target](goal.png)

> Image: a screenshot from The 8-Bit Guy's video on the **C128 "Alternate
> Universe"** — used here purely as a visual reference for the look we're after.

We're a long way from this, but it's the north star.

### Where it is now

The current GEOBENCH desktop running on the Amstrad CPC (1984 emulator): a Mode 1
backdrop, a top bar showing total RAM and a clock, and draggable multicolour
bitmap icons (Disk, Clock, Trash) driven by a keyboard/joystick pointer.

![Current status](initial.png)

What works today:

- **Desktop** — backdrop, top bar (RAM probe + clock), draggable labelled icons.
- **File manager** — double-click the Disk icon to open a window listing the
  drive; a type icon + name per file, a **scrolling** list, click to select,
  double-click to open. Reaches every file regardless of how many.
- **Text viewer** — double-click a `.TXT` (routed by a type→app table) to open it
  in a window with word-wrapped text.
- **Banked app model** — the desktop, file manager and viewer are separate
  binaries, paged into expansion-bank slots and run co-resident with the kernel.
- **Hybrid implementation** — the kernel is Z80 assembly; **every app is C**.

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

## How it works

GEOBENCH borrows SymbOS's banked-app shape, scaled down:

- **Banked memory model.** On a 128K+ machine the gate-array RAM-config port
  pages a 16K block into the `#4000–#7FFF` window. The kernel, the stack, the
  screen and the firmware stay in always-resident RAM; apps and the kernel's data
  buffers (font, icons) live in bank pages and are swapped in as needed.
- **Resident kernel (`kernel/`, Z80 asm).** Boots the machine (Mode 1, palette,
  RAM probe, clock, top bar), owns the storage + screen + input + cursor, and
  exposes a **fixed jump-table API** at `#8000` (`lib/gbapp.inc` documents every
  entry). It loads app binaries off disk into bank pages and runs them there.
- **Apps in C (`apps/`, SDCC).** Each app is a single `main.c` compiled to run at
  `#4000` in a bank page. It reaches the kernel only through **`libgb`**
  (`lib/gb/` — `gb.h` + asm trampolines that map the C calling convention onto the
  jump table). The desktop launches the file manager and the viewer; an app
  returns to its caller by `return`.
- **Storage backends.** A small dispatcher (`lib/fs.asm`) picks AMSDOS-over-floppy
  or FAT16-over-IDE at boot, so the same desktop runs on a plain floppy CPC or a
  SYMBiFACE/Cyboard IDE-equipped one.

## Building and running

The kernel is assembled with **RASM**; the apps are compiled with **SDCC**
(`sdcc`, `sdasz80`, `makebin` on `PATH`). One script builds everything into a
disk image:

```bash
tools/build_kernel.sh           # apps (SDCC) + kernel (RASM) -> build/gbkern.dsk
```

Run it in an emulator (or on hardware):

```bash
1984 --memory=128 --disk-a=build/gbkern.dsk --autostart=GBKERN
```

`tools/build_capp.sh <app_dir> <out.RAW>` builds a single C app against `libgb`
if you just want to iterate on one.

## Design inspirations

We deliberately cherry-pick from both ancestors rather than cloning either one.

### From Commodore GEOS

- **It runs on tiny hardware.** GEOS proved a real WIMP desktop is possible on a
  1 MHz 8-bit CPU with 64K of RAM. That is the existence proof GEOBENCH stands on.
- **Proportional bitmap fonts** and a consistent system look.
- **A disk-based application model** — load apps from disk on demand, keep the
  resident kernel small.
- **Bundled productivity apps** in the spirit of geoWrite / geoPaint.

### From Amiga Workbench

- **The desktop metaphor proper:** draggable icons, windows, drawers (folders),
  and a trashcan.
- **Screens and windows** as the core UI primitives.
- **A clean, layered look** that treats the desktop as a workspace, not a menu.
- **Tools and drawers** the user can arrange spatially.

## Target hardware

- **Amstrad CPC** (464 / 664 / 6128, and CPC+) with **128K+ RAM** (the banked app
  model needs the expansion banks; 512K is typical and fine).
- Mode 1 (320×200, 4 colours) for the desktop.
- **Keyboard/joystick-driven software pointer** today; the input layer stays
  abstract so an AMX-style joystick mouse or a **SYMBiFACE II / Cyboard PS/2
  mouse** can be added for machines that have one.
- Floppy or IDE (FAT16) storage. Networking via Net4CPC (W5100S) is a possible
  future extension — see the related `n4c-nettools` project.

## Goals

- A resident **kernel** small enough to leave usable RAM for applications.
- A **desktop shell**: icons, windows, drawers, drag-and-drop, menus.
- A **graphics + windowing layer** abstracting the CPC's video hardware.
- A **mouse/input layer** with a software pointer.
- A small set of **bundled applications** to prove the platform is real.
- A documented **application API** (the `libgb` jump table) so third parties can
  write GEOBENCH apps — in C.
- **Launching existing software.** Because GEOBENCH sits on top of AMSDOS/UniDOS
  rather than replacing it, the desktop should be able to run the CPC's existing
  catalogue — pick a `.BIN` binary or a BASIC `.BAS` program and launch it, the
  same way you would `RUN"PROG"` from BASIC today.

## Running existing AMSDOS software

A core part of the "layer on top of DOS, don't replace it" philosophy (planned):

- **AMSDOS binaries (`.BIN`)** — hand the file off to the firmware loader and
  transfer control, just as typing `RUN"GAME.BIN"` would.
- **BASIC programs (`.BAS`)** — launched via the BASIC ROM, equivalent to
  `RUN"PROG"`.

When launching, the user chooses how the program runs:

- **Fullscreen** — the program takes over the whole machine. The safe,
  always-works mode: most CPC software assumes it **owns the machine**, so
  GEOBENCH steps aside, hands over, and the user returns to the desktop on exit.
- **Windowed** — where feasible, run a well-behaved program's output inside a
  desktop window. The harder, best-effort mode; the desktop falls back to
  fullscreen when a program can't be safely contained.

GEOBENCH-native apps (the C apps above) always cooperate and run inside the
desktop — the windowed/fullscreen choice is specifically about coaxing *legacy*
`.BIN`/`.BAS` software into the environment.

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
├── kernel/            # resident OS kernel (gbkern.asm) + the jump-table API
├── lib/               # kernel libraries: screen, text/font, input, cursor,
│   │                  #   fs (AMSDOS + FAT16), banking, icon/cursor bitmaps
│   ├── gbapp.inc      #   the app ABI (jump-table addresses, memory model)
│   └── gb/            #   libgb: the shared C bindings (gb.h, gblib.s, crt0.s)
├── apps/              # the C apps (each a single main.c)
│   ├── desktop/       #   the boot shell: backdrop, icons, drag, launch
│   ├── filemgr/       #   scrolling file manager
│   ├── viewer/        #   text-file viewer
│   └── chello/        #   "hello from C" demo (the original C-app spike)
├── assets/            # icon/cursor source PNGs + sample files (WELCOME.TXT)
├── docs/              # architecture, development, references
└── tools/            # host-side build/asset tooling (build_kernel.sh, ...)
```

## Roadmap (rough)

Done:

1. ✅ **Boot + desktop** — Mode 1 backdrop, top bar, software pointer.
2. ✅ **Windowing + icons** — windows with title bars/gadgets, draggable icons.
3. ✅ **File manager** — browse a drive, select, scroll, open by type.
4. ✅ **Banked app model + app API** — separate-binary apps over a kernel API.
5. ✅ **Apps in C** — the whole app layer moved from assembly to C over `libgb`.

Next:

- **More apps** — an editable notepad (needs a storage *write* layer), an icon
  editor, settings.
- **Menu bar** — File/Edit menus in the top bar, dispatched to the focused app.
- **Launching legacy `.BIN`/`.BAS`** software (see above).
- **Drawers/folders** and richer desktop arrangement.

## License

TBD.
