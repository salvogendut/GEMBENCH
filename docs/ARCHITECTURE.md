# GEOBENCH Architecture (sketch)

This is an early, deliberately-loose architecture sketch. It will firm up as the
first pieces get built. Treat it as a shared mental model, not a spec.

## Layer cake

GEOBENCH is organised as layers, lowest (closest to hardware) at the bottom:

```
┌─────────────────────────────────────────────┐
│  apps/      bundled applications             │  ← load on demand from disk
├─────────────────────────────────────────────┤
│  desktop/   Workbench-style shell            │  ← icons, windows, drawers, menus
├─────────────────────────────────────────────┤
│  lib/       graphics · window · input · font │  ← reusable, hardware-abstracting
├─────────────────────────────────────────────┤
│  kernel/    boot · memory · loader · API gate│  ← resident
├─────────────────────────────────────────────┤
│  Amstrad CPC hardware  (Z80, CRTC, gate array, AMSDOS)│
└─────────────────────────────────────────────┘
```

Each layer only calls **down** through documented entry points. The desktop and
apps never touch video or input hardware directly — they go through `lib/`.

## Memory model

- The **kernel is resident** and kept as small as possible.
- `lib/` routines are resident too (they're needed by everything).
- The **desktop** is resident-ish (it's the shell you return to).
- **Apps are transient**: loaded into a kernel-allocated block, run, then freed.
- On a 128K machine, the extra banks hold buffers, off-screen bitmaps, and
  possibly a second app/data bank. The 64K target is a stretch goal with a much
  tighter budget.

## Execution model

Cooperative and single-foreground-app to start:

- One application has the foreground at a time.
- The desktop runs an event loop; when it launches an app, control transfers to
  the app's own event loop until the user quits.
- A vblank interrupt drives lightweight housekeeping (pointer, cursor blink,
  timers) regardless of who has the foreground.

Preemptive multitasking — the Amiga's signature — is explicitly *not* a v1 goal.

## The system API

Applications reach system services through a single **call gate** the kernel
hands them at launch. Categories of call (to be specified):

- **Graphics** — draw into a window's region.
- **Windowing** — request / resize / close a window; handle redraw.
- **Input** — read pointer and keyboard events.
- **Files** — open / read / write / catalogue on disk (via AMSDOS).
- **Memory** — allocate / free blocks.

Keeping this an explicit, versioned gate is what lets third parties write apps
without linking against private kernel internals.

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

These get answered as the kernel and graphics library take shape.
