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

# Fixed-height default action rows on an existing surface panel:
ACTIONS=1 tools/build_capp.sh apps/myapp build/MYAPP.RAW
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

`ACTIONS=1` is the smaller option for a constrained dialog that only needs
default-state command rows. `gb_actions()` frames and labels one or more
caller-sized actions at the fixed `GB_ACTION_H` metric; the caller must first
paint the containing panel with the surface pen. `gb_actions_hit()` uses
wrap-safe 8-bit coordinate deltas and returns the selected index or
`GB_ACTION_NONE`. This unit does not provide pressed or disabled states; use
`BUTTON=1` and `gb_button()` when those states are needed.

Browser is an intentional exception: its PCW build is constrained by the
record-rounded app loader ceiling. Linking the generic field/button unit for its
toolbar exceeded that ceiling by 439 bytes, so it retains compact local drawing
until equivalent room is reclaimed.

Settings uses `ACTIONS=1` for the screensaver Configure and Save/Cancel rows.
Its stack-heavy live colour editor deliberately retains the proven local
Save/Cancel path: calling or drawing the shared row in that loop regressed
target-side stepper input. A bounded allocation pass keeps this mixed
implementation within the CPC code/data split without changing the colour
handler. Settings data still ends only 91 bytes below the kernel, so further
migration requires target testing and an explicit map check.

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
constrained app. Its modal deliberately combines a field, selector, stepper and
the compact `ACTIONS=1` Save/Cancel row so target dispatch can be checked before
another Settings migration. Settings and Browser deliberately remain on their
compact implementations. Clock is the first production form-modal user; it
builds with `WIDGETS=1 STEPPER=1 FORM=1 TIMESET=1`. `TIMESET=1` links
`gb_set_time()` into that app only, preserving CPC resident-kernel headroom.

### App-linked audio

Audio is an optional application library, not a kernel service. Link it only
into an app that needs sound:

```bash
SOUND=1 tools/build_capp.sh apps/myapp build/MYAPP.RAW
```

The portable API in `lib/gb/gb.h` is deliberately small:

- `gb_sound_tone(note, volume)` starts a C3..B6 chromatic note.
- `gb_sound_noise(period, volume)` starts PSG noise.
- `gb_sound_stop()` silences the app-owned channel.
- `gb_sound_caps()` reports pitch, noise, and volume capabilities.

Use `GB_SOUND_NOTE(GB_PITCH_*, octave)` to construct a note and keep volume in
`0..GB_SOUND_VOLUME_MAX`. CPC and MSX2 use PSG channel A. PCW safely probes the
DK'tronics AY at ports `A9`/`AA`/`AB`, preserves channels B/C and the joystick
input bit, and uses channel A when found. A stock PCW maps both tone and noise
to the fixed 3.75 kHz beeper. Duration and sequencing remain in the app's
`GB_MSG_FRAME` handler; always call `gb_sound_stop()` before closing.

This design adds no resident state, kernel code, or ABI slot. Apps that do not
build with `SOUND=1` remain byte-identical. `make sndtest` builds the
three-platform `SNDTEST.APP` reference without rebuilding the distributions.

## Icon and font sets (GEOBENCH.CFG)

`GEOBENCH.CFG` selects named resources. `ICONS=<name>` loads `<name>.IST`,
`FONT=<name>` loads `<name>.FNT`, `CURSOR=<name>` loads `<name>.SPR`,
`TITLEBAR=<name>` loads a standalone `<name>.TBR` window-title theme,
`BACKDROP=<drive:name|SOLID>`, `WALLPAPER=<drive:name|NONE>`, and
`SAVER=<drive:name|NONE>` identify optional desktop media. Missing font/icon/
cursor settings fall back to `DEFAULT`; invalid background media falls back to
`SOLID` / `NONE` during boot so the machine still starts.

Title themes are canonical four-pen assets shared unchanged by every target.
Their 16x14 background repeats horizontally; 8x10 close and 12x10 maximize
tiles are stamped over it. Settings applies a new theme live and independently
of `ICONS=`. A missing theme falls back to embedded `ORIGINAL` assets. Legacy
56-byte files replace only the repeated background and retain fallback gadgets.

Per-screensaver options also live in this file. The first contract is
`STARFLD_SPEED=1..8` and `STARFLD_STARS=16..96` (defaults `4` and `64`). Saver
apps should use `lib/gb/gbcfg.h` for bounded numeric values so old, missing, or
malformed settings fall back safely without kernel involvement.

Configurable savers keep their Settings UI in `apps/<name>/config.c`. Build it
with `tools/build_savercfg.sh` and stage the result as a same-stem `.MOD` beside
the `.SAV`. Settings invokes that module through the existing paged `GB_UI`
service and accepts a bounded list of `KEY=`/value pairs defined by
`lib/gb/gbsavercfg.h`; it does not link saver-specific controls or know their
keys. A saver without a companion remains valid and reports that it has no
settings when **Configure** is selected.

XMATRIX adds `XMATRIX_GLYPHS=0|1` (binary/Kana), `XMATRIX_SPEED=1..3`, and a
target-specific `XMATRIX_COLOR=`. CPC stores a firmware hardware ink in
`0..26` (default `18`, bright green); MSX Screen 7 stores a stable extended
palette index in `4..15` (default `4`). PCW and MSX Screen 6 keep the fixed
green treatment and do not offer the color row. Every mode clears to black,
snapshots its launch-time palette, and restores that snapshot on exit.

MOUNTAIN adds `MOUNTAIN_SPEED=1..3` (default `2`),
`MOUNTAIN_PEAKS=4..30` (default `15`), and
`MOUNTAIN_HOLD=30..240` (default `120`, stepped by 30). MSX Screen 7 maps
terrain height through eight fixed palette bands; MSX Screen 6, CPC, and PCW
retain bounded target-appropriate shading. The saver restores the two temporary
Screen 7 wire/background palette entries when it exits. CPC and MSX force a
black display border while Mountain runs and restore the configured border on
exit; on MSX Screen 6 the border shares palette entry 0 with the sky.

Build a set, then package it (add an `incbin` + a `save "<NAME>.<EXT>",...,DSK`
line in the pack assembly or stage it into the card distribution as appropriate):

- **Font** (`.FNT`): from an 8×8 `.asm` font source — `tools/packfont.py
  build/NAME.FNT lib/font.asm` (ships `CLASSIC.FNT`, the 8×8 ROM font). The 6×8
  `DEFAULT.FNT` is generated procedurally by `tools/genfont.py`.
- **Icons** (`.IST`): each icon is a 32×32 PNG → `tools/png2cpc.py assets/x.png
  lib/icon_x.asm icon_x 32x32`, then `tools/packicons.py build/NAME.IST
  lib/icon_*.asm ...` in **slot order** (must match `ext_to_icon` in `gbkern.asm`:
     floppy clock trash geobench basic binary picture text folder app font
     desktop filemanager sd up screensaver cf ide fractal settings calculator).
  `packicons.py` always emits canonical CPC Mode-1 payloads. MSX and PCW keep the
  `.IST` files unchanged on disk and decode them to native icon bytes when loaded.

  Two ways to get edited icons onto the next card:

  1. **Change the DEFAULT set** (the icons shown out of the box): edit the source
     `assets/<name>.png` in any image editor (keep the 4-colour desktop palette),
     then run **`tools/regen_icons.sh`**. It re-runs `png2cpc` for committed
     resident `lib/icon_*.asm` and app-owned `apps/*/icon.asm` sources from their
     recorded PNG and size. Paint-specific tool icons live in GB-PAINT.
     Rebuild (`tools/build_kernel.sh`) and `packicons` repacks `build/DEFAULT.IST`.
     Note: the build does **not** auto-convert `assets/` — `build/DEFAULT.IST` is a
     gitignored artifact regenerated from the committed `lib/icon_*.asm`, so a PNG
     edit only takes effect after `regen_icons.sh` updates those `.asm` files.
  2. **Ship a custom selectable set**: edit a set visually with
     `tools/iconedit.py assets/iconsets/MYSET.IST` (tracked, unlike `build/`), and
     `stage_dist.sh` copies every `assets/iconsets/*.IST` onto
     the card automatically. Select it with `ICONS=MYSET` in `GEOBENCH.CFG`. See
     `assets/iconsets/README.md`.

### Icons embedded in applications

A C application can opt into the versioned `GBAP` executable preamble by
passing `APP_ICON=path/to/icon.asm` to `tools/build_capp.sh`. This retains the v1
layout: a canonical 32x32 Mode-1 bitmap and application entry at `#4110`.
`APP_ICON16=path/to/icon16.asm` adds an explicitly declared native Screen-7
resource, selects the v2 directory layout, and relocates the entry to `#4320`.
Headerless applications keep the legacy `#4000` entry and generic or
system-name-mapped `.IST` icon. See [APP_ICON_FORMAT.md](APP_ICON_FORMAT.md).

The app-owned source convention is `apps/<name>/icon.asm`. On an MSX build,
`build_capp.sh` also detects an optional adjacent `icon16.asm` and emits GBAP v2
automatically. CPC and PCW retain the smaller portable-only header.

File Manager probes the first 1,024 bytes of a visible generic `.APP`. CPC, PCW,
and MSX Screen 6 select the portable fallback; MSX Screen 7 selects the
sixteen-colour resource when present. An absent or invalid header falls back to
the generic application icon. The native blit operation is compiled only into
the Screen-7 kernel. `FORMREF.APP` is the dual-icon reference:

```sh
tools/png2cpc.py assets/daruma.png apps/formref/icon.asm appicon 32x32
APP_ICON=apps/formref/icon.asm APP_ICON16=apps/formref/icon16.asm \
  DATA_LOC=0x6200 \
  tools/build_capp.sh apps/formref build/FORMREF.RAW
```

Both `tools/iconedit.py` and `ICONED.APP` preserve executable bytes and
unselected resources when saving. The host editor opens either `APP_ICON=` ASM
source directly, offers separate New 4-color/New 16-color source commands, and
uses Previous/Next for the two resources in a v2 APP. `ICONED.APP` uses the
7,168-byte low-RAM transfer buffer for its whole document; MSX Screen 7 exposes
both resources and the other modes expose the portable fallback. Larger
applications still display their embedded icon and can be edited with the host
tool. Its paged
`GBAPICK.MOD` Open dialog uses the resident chunk readers on MSX and PCW. The
CPC build instead probes with a bounded ordinary load into the shared
module-data buffer, avoiding a recursive chunk-module load over the running
picker. `.APP` entries without a valid preamble remain hidden on all targets.

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
