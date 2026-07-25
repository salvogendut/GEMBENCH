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
  `QA/CPC/GEOBENCH.IMG`. The project distrobox carries all of these. `tools/build_rom.sh`
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
../caprice32/cap32 --autocmd 'RUN"GB' QA/CPC/Floppies/GEOBENCH.DSK
```

1984 has its own invocation. For GEOBENCH the common paths are:

```bash
bash tools/build_kernel.sh
../1984/1984 --config=/dev/null --6128 --memory=512 --disk-a=QA/CPC/Floppies/GEOBENCH.DSK --disk-b=QA/CPC/Floppies/COMPANION.DSK --autostart=GB
../1984/1984 --config=/dev/null --6128 --memory=512 --disk-a=QA/CPC/Floppies/GEOBENCH.DSK --autostart=GB --screenshot-at=2200:/tmp/boot.ppm --exit-after=2200
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
- always rebuild the packaged media (`QA/CPC/Floppies/GEOBENCH.DSK`,
  `QA/CPC/Floppies/COMPANION.DSK`, `QA/CPC/Floppies/EXTRAS.DSK`,
  `QA/CPC/CARD/`, `QA/CPC/GEOBENCH.IMG`);
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

## Reusable application UI

New applications should normally register a managed `gb_mwin_t` window, use
`gb_doc_t` when they need standard File/Edit/View behaviour, and opt into the
common non-modal controls instead of implementing their appearance independently:

```c
gb_field(x, y, w, 13, visible_text,
         editing ? GB_WIDGET_FOCUSED : 0);
gb_button(x, button_y, 20, 15, "Apply", 0);
gb_button(x, button_y, 20, 15, "Apply", GB_WIDGET_PRESSED);
gb_vscroll(sx, sy, 3, sh, top, total, visible, GB_WIDGET_ARROWS);
gb_select(x, option_y, 26, 10, current_option, 0);
gb_stepper(x, value_y, 16, 10, value_text, 0);
```

Enable the required compilation units per app:

```bash
BUTTON=1 SELECTOR=1 STEPPER=1 \
    tools/build_capp.sh apps/myapp build/MYAPP.RAW
```

`BUTTON=1` provides `gb_button` and `gb_widget_hit` without linking the text-field
renderer. `WIDGETS=1` provides those plus `gb_field`; `SCROLL=1`
provides byte-range `gb_vscroll` and `gb_vscroll_hit`. `SCROLL16=1` adds
large-range vertical and horizontal scrollbars plus pointer-to-value mapping,
as used by Viewer for pictures taller than 255 rows. `TOGGLE=1`, `STEPPER=1`,
`SELECTOR=1`, and `SLIDER=1` each link only that control and its matching
hit/value helper. Widget state stays in the app bank. This avoids resident-kernel
growth and avoids using `GBUI.MOD`, whose modal dispatcher loads the module from
disk for each operation. Widgets use the four logical UI pens, so `INKS=` changes
their colours consistently on CPC, MSX2 and PCW. Buttons may be drawn with
`GB_WIDGET_PRESSED` or `GB_WIDGET_DISABLED`; `gb_button_hit` automatically
rejects a disabled control. Layout metrics, selected values, ranges, popup
actions and inline text editing remain application-owned.

Browser is an intentional exception: its PCW build is constrained by the
record-rounded app loader ceiling. Linking the generic field/button unit for its
toolbar exceeded that ceiling by 439 bytes, so it retains compact local drawing
until equivalent room is reclaimed.

Settings also retains compact local `Configure`/`Save`/`Cancel` actions. Even the
button-only unit moved its CPC loaded image 276 bytes past the fixed data split,
while its data already ends only 91 bytes below the kernel.

### Reusable forms and modal dialogs

For a new form, link the composition layer into that application:

```bash
WIDGETS=1 FORM=1 tools/build_capp.sh apps/myapp build/MYAPP.RAW

# Add a labelled selector row:
WIDGETS=1 SELECTOR=1 FORM=1 FORM_SELECT=1 \
    tools/build_capp.sh apps/myapp build/MYAPP.RAW
```

`gb_form_field_row()` and `gb_form_select_row()` reserve a caller-selected label
width and draw the control in the remainder. `gb_form_actions()` lays out a
standard button row, while `gb_form_actions_hit()` returns its enabled action.
`gb_form_modal_run()` owns the input loop, title-bar close, optional click-away
cancel, cursor bracketing, modal latch, and final parent repaint. The application
owns field buffers, focus, selection, validation, and save/cancel semantics
through draw, click, and key callbacks in `gb_form_modal_t`.

The form units are app-linked and opt-in. They add nothing to the resident
kernel or `GBUI.MOD`, and existing apps remain byte-identical until migrated
explicitly. Build `make formref`, then run `FORMREF.APP` from `DIAG/` on CPC,
`GBENCH/` on MSX2, or from the PCW Companion disk, before applying the API to a
constrained app. Settings and Browser deliberately remain on their current
implementations. Clock is the first production form-modal user; it builds with
`WIDGETS=1 STEPPER=1 FORM=1 TIMESET=1`. `TIMESET=1` links `gb_set_time()` into
that app only, preserving CPC resident-kernel headroom.

## Icon and font sets (GEOBENCH.CFG)

`GEOBENCH.CFG` selects named resources. `ICONS=<name>` loads `<name>.IST`,
`FONT=<name>` loads `<name>.FNT`, `CURSOR=<name>` loads `<name>.SPR`,
`BACKDROP=<drive:name|SOLID>`, `WALLPAPER=<drive:name|NONE>`, and
`SAVER=<drive:name|NONE>` identify optional desktop media. Missing font/icon/
cursor settings fall back to `DEFAULT`; invalid background media falls back to
`SOLID` / `NONE` during boot so the machine still starts.

Per-screensaver options also live in this file. The first contract is
`STARFLD_SPEED=1..8` and `STARFLD_STARS=16..96` (defaults `4` and `64`). Saver
apps should use `lib/gb/gbcfg.h` for bounded numeric values so old, missing, or
malformed settings fall back safely without kernel involvement.

Build a set, then package it (add an `incbin` + a `save "<NAME>.<EXT>",...,DSK`
line in the pack assembly or stage it into the card distribution as appropriate):

- **Font** (`.FNT`): from an 8×8 `.asm` font source — `tools/packfont.py
  build/NAME.FNT lib/font.asm` (ships `CLASSIC.FNT`, the 8×8 ROM font). The 6×8
  `DEFAULT.FNT` is generated procedurally by `tools/genfont.py`.
- **Icons** (`.IST`): each icon is a 32×32 PNG → `tools/png2cpc.py assets/x.png
  lib/icon_x.asm icon_x 32x32`, then `tools/packicons.py build/NAME.IST
  lib/icon_*.asm ...` in **slot order** (must match `ext_to_icon` in `gbkern.asm`:
  floppy ide clock trash geobench basic binary picture text folder).
  `packicons.py` always emits canonical CPC Mode-1 payloads. MSX and PCW keep the
  `.IST` files unchanged on disk and decode them to native icon bytes when loaded.

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
- **Pictures** (`.PIC`): convert a PNG to the portable 4-colour GBPC v2 format
  with `tools/picconv.py` — a tkinter GUI (Open / dither / width / height /
  preview / Save)
  or a CLI (`tools/picconv.py in.png out.PIC -d floyd -w 160`). The canonical
  Mode-1 payload is byte-identical on CPC, MSX2, and PCW; target kernels translate
  it while drawing. For an MSX Screen 7 image, choose 16 colours in the GUI or
  pass `--colors 16`; leave either size field blank to preserve aspect
  ratio, or set both to fit the Screen 7 limit of 512x255. This mode-7 extension is not editable in Paint and
  is not displayed by CPC, PCW, or the Screen 6 backend. `.PIC` opens in Viewer
  and portable mode-1 files edit in PAINT. See
  [PIC_FORMAT.md](PIC_FORMAT.md).

## File line endings

Any text/data file the CPC reads must use **CR+LF** (`0x0D 0x0A`), not Unix LF.
Convert before packing onto a disk image (`unix2dos file` or `sed -i 's/$/\r/'`).
