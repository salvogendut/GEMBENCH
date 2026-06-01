# Development

How GEOBENCH is built and run during development. None of this runs on the CPC;
it's the host-side workflow.

## Toolchain

- **Assembler:** [RASM](http://www.roudoudou.com/rasm/) (`rasm` on PATH —
  v3.2.1+). RASM can emit raw binaries, AMSDOS-headed binaries, and `.dsk`
  images directly, so no separate disk tool is required.
- **Emulators:** see below.

## Emulators

We develop against two emulators with distinct roles:

| Emulator | Role | Why |
|----------|------|-----|
| **1984** (`../1984`) | **Primary dev target** | The user's own cycle-stepped CPC emulator. Standard firmware/AMSDOS software runs well — which is all GEOBENCH is. `--screenshot-at=N:PATH` dumps a `.ppm` and exits, giving clean headless visual verification, and `--autostart=NAME` autoruns a file after boot. Dogfooding it exercises the emulator too. |
| **cap32** (`../caprice32`) | **Cross-check oracle** | Mature, widely-validated [Caprice32](https://github.com/ColinPitrat/caprice32). When a behaviour is ambiguous, run the same artifact on cap32: if the two disagree, the bug is localised. |

### Why 1984 is primary, not cap32

cap32 is arguably more *accurate* — but only for the things GEOBENCH never does
(cycle-exact CRTC tricks, undocumented hardware, demo/game edge cases). GEOBENCH
is plain firmware + AMSDOS + Mode 1 code, so that edge doesn't matter here. 1984
wins on workflow: it's ours (dogfooding), and `--screenshot-at` makes automated
visual checks trivial. cap32 stays as a second opinion.

### Mouse / pointer

The default pointer is an **AMX-style mouse read via the joystick port** — no
expansion hardware required, so it works on a bare CPC and on *both* emulators
(both emulate the joystick). During development the host's mouse or a gamepad
drives the emulated joystick directions. A SYMBiFACE II / Cyboard PS/2 mouse is
a later add behind the input layer for machines with the board.

## Running a build

cap32 and 1984 both accept a `.dsk` slot file. Two quick paths:

```bash
# Inject a raw binary at its org address (fast iteration, no disk needed):
../caprice32/cap32 -i bin/PROG.BIN -o 0x4000

# Or boot a disk image and autorun a file:
../caprice32/cap32 --autocmd 'RUN"PROG' build/geobench.dsk
```

1984 has its own invocation (see `../1984/INSTALL.md` / `1984.conf.example`);
the build artifacts (`.bin` / `.dsk`) are the same.

## File line endings

Any text/data file the CPC reads must use **CR+LF** (`0x0D 0x0A`), not Unix LF.
Convert before packing onto a disk image (`unix2dos file` or `sed -i 's/$/\r/'`).
