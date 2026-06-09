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
