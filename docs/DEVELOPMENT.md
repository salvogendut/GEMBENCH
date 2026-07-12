# Development

How GEOBENCH is built and run during development. None of this runs on the CPC;
it's the host-side workflow.

## Toolchain

- **Assembler:** [RASM](http://www.roudoudou.com/rasm/) (`rasm` on PATH —
  v3.2.1+). RASM can emit raw binaries, AMSDOS-headed binaries, and `.dsk`
  images directly, so no separate disk tool is required for the floppy.
- **C compiler:** [SDCC](http://sdcc.sourceforge.net/) (`sdcc`, `sdasz80`,
  `makebin`) for the apps.
- **Card image:** `tools/build_card_img.sh` needs `sfdisk` (util-linux),
  `mkfs.fat` (dosfstools) and `mcopy` (mtools) to build the partitioned FAT16
  `QA/GEOBENCH.IMG`. The project distrobox carries all of these. `tools/build_rom.sh`
  (the driver-offload ROM) needs only `rasm`.
- **Emulators:** see below.

The intended host environment is the project distrobox:

```bash
distrobox enter my-distrobox
```

That container is where `gh`, the CPC toolchain, and the image-build
dependencies are expected to exist.

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
../caprice32/cap32 --autocmd 'RUN"GB' QA/GEOBENCH.DSK
```

1984 has its own invocation. For GEOBENCH the common paths are:

```bash
bash tools/build_kernel.sh
../1984/1984 --config=/dev/null --6128 --memory=512 --disk-a=QA/GEOBENCH.DSK --disk-b=QA/COMPANION.DSK --autostart=GB
../1984/1984 --config=/dev/null --6128 --memory=512 --disk-a=QA/GEOBENCH.DSK --autostart=GB --screenshot-at=2200:/tmp/boot.ppm --exit-after=2200
```

The boot splash prints the build commit below the progress bar only when
`DEBUG=TRUE` is set in `GEOBENCH.CFG`; normal media show `GEOBENCH` there. Use the
debug splash to cross-check media against the source tree under test.

### Incremental build behavior

`tools/build_kernel.sh` still stages the full distribution, but the expensive C
app and module builds are cached. The helper scripts write `*.stamp` metadata
next to their outputs and skip recompilation when the output, toolchain, build
flags, and transitive source dependencies are unchanged. Re-running the full
build should therefore:

- rebuild only the touched apps/modules;
- always rebuild the packaged media (`QA/GEOBENCH.DSK`, `QA/COMPANION.DSK`,
  `QA/MEDIA.DSK`, `QA/CARD/`, `QA/GEOBENCH.IMG`);
- refresh the boot-splash build id from the current git commit.

## Static Contract Checks

The app ABI jump table is tracked in `kernel/api_table.inc` and exported to
apps through `lib/gbapp.inc`. Low RAM below `#4000` is shared by the resident
kernel, C apps, and paged modules; its fixed ownership map is tracked in
`kernel/lowram.tsv`. Before moving ABI slots or adding absolute cells, run:

```bash
python3 tools/check_abi_table.py
python3 tools/check_lowram_map.py
```

The default profile is the shipped no-ROM Albireo build and should stay clean.
`--list-profiles` shows optional profiles. The archived IDE and optional ROM
profiles currently expose real pressure around `#1250..#12D7`; keep those
failures visible until the ranges are actually moved or retired.

## Icon and font sets (GEOBENCH.CFG)

`GEOBENCH.CFG` selects named resources. `ICONS=<name>` loads `<name>.IST`,
`FONT=<name>` loads `<name>.FNT`, `CURSOR=<name>` loads `<name>.SPR`,
`BACKDROP=<drive:name|SOLID>`, `WALLPAPER=<drive:name|NONE>`, and
`SAVER=<drive:name|NONE>` identify optional desktop media. Missing font/icon/
cursor settings fall back to `DEFAULT`; invalid background media falls back to
`SOLID` / `NONE` during boot so the machine still starts.

Build a set, then package it (add an `incbin` + a `save "<NAME>.<EXT>",...,DSK`
line in the pack assembly or stage it into the card distribution as appropriate):

- **Font** (`.FNT`): from an 8×8 `.asm` font source — `tools/packfont.py
  build/NAME.FNT lib/font.asm` (ships `CLASSIC.FNT`, the 8×8 ROM font). The 6×8
  `DEFAULT.FNT` is generated procedurally by `tools/genfont.py`.
- **Icons** (`.IST`): each icon is a 32×32 PNG → `tools/png2cpc.py assets/x.png
  lib/icon_x.asm icon_x 32x32`, then `tools/packicons.py build/NAME.IST
  lib/icon_*.asm ...` in **slot order** (must match `ext_to_icon` in `gbkern.asm`:
  floppy ide clock trash geobench basic binary picture text folder).

  Two ways to get edited icons onto the next card:

  1. **Change the DEFAULT set** (the icons shown out of the box): edit the source
     `assets/<name>.png` in any image editor (keep the 4-colour desktop palette),
     then run **`tools/regen_icons.sh`** — it re-runs `png2cpc` for every committed
     `lib/icon_*.asm` from its recorded source PNG + size. Paint-specific tool
     icons now live in the separate GB-PAINT repository.
     Rebuild (`tools/build_kernel.sh`) and `packicons` repacks `build/DEFAULT.IST`.
     Note: the build does **not** auto-convert `assets/` — `build/DEFAULT.IST` is a
     gitignored artifact regenerated from the committed `lib/icon_*.asm`, so a PNG
     edit only takes effect after `regen_icons.sh` updates those `.asm` files.
  2. **Ship a custom selectable set**: edit a set visually with
     `tools/iconedit.py assets/iconsets/MYSET.IST` (tracked, unlike `build/`), and
     `stage_dist.sh` copies every `assets/iconsets/*.IST` onto
     the card automatically. Select it with `ICONS=MYSET` in `GEOBENCH.CFG`. See
     `assets/iconsets/README.md`.
- **Pictures** (`.PIC`): convert a PNG to a 4-colour Mode-1 picture with
  `tools/picconv.py` — a tkinter GUI (Open / dither / width / preview / Save) or a
  CLI (`tools/picconv.py in.png out.PIC -d floyd -w 160`). `.PIC` opens in the
  Viewer and edits in PAINT; no packaging needed (it's user content, not a build
  asset).

## File line endings

Any text/data file the CPC reads must use **CR+LF** (`0x0D 0x0A`), not Unix LF.
Convert before packing onto a disk image (`unix2dos file` or `sed -i 's/$/\r/'`).
