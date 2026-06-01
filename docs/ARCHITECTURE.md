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
