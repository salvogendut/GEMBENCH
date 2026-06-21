# tools/

Host-side (PC) tooling for building GEOBENCH and preparing assets. None of this
runs on the CPC — it produces the binaries and data files that do. The kernel is
assembled with **RASM**; the C apps with **SDCC**. Most builds run inside the
project's distrobox (which carries `rasm`, `sdcc`, `mtools`, `dosfstools`, ...).

## Build orchestration

- **`build_kernel.sh`** — the one-shot build. Assembles **both** shipped kernels
  (`GBALB` Albireo + `GBM4` M4 board), packs the apps, and stages one unified
  distribution into `QA/`: the loose card files (`QA/CARD/`), the floppy
  (`QA/GEOBENCH.DSK`), and the card image (`QA/GEOBENCH.IMG`). `STORAGE=ide` builds the
  retired IDE backend instead (still in the tree for recovery/tests; history frozen on
  branch `legacy-ide`). `FAT16=1` and `EXTRA_RASM=...` tune the variant (e.g.
  `EXTRA_RASM="-DGB_ROM_REQ=1"` for the ROM-offload kernel).
- **`m4detect.asm`** — the tiny BASIC-callable detector embedded in the unified `GB.BAS`:
  asks the firmware (`KL_FIND_COMMAND`) whether the M4 ROM's RSX is installed, so the
  loader can `RUN"GBM4` on an M4 board or `RUN"GBALB` otherwise. Assembled by `stage_dist.sh`.
- **`build_rom.sh`** — builds the 16K upper ROMs that offload the low-level drivers
  and carry the cold-boot banner: `rom/GBALB.ROM` (Albireo) and `rom/GEOBENCH.ROM`
  (the dormant IDE backend). Bakes the git commit into the banner
  (`rom/gitcommit.inc`, generated).
- **`stage_dist.sh <out>`** — stages the unified card distribution (the detecting GB.BAS
  loader + `GBM4.BIN` + `GBALB.BIN` + the `GEOBENCH/` payload) into a directory.
- **`build_capp.sh <app_dir> <out.RAW>`** — builds a single C app against `libgb`,
  for iterating on one app.
- **`deploy_ide.sh`** — copy the staged distribution onto a real/emulated IDE image
  (for the dormant IDE backend).

## Card / disk images

- **`build_card_img.sh [CARD] [IMG]`** — builds a partitioned **FAT16 card image**
  (`QA/GEOBENCH.IMG` by default) from the staged `QA/CARD/`. One image boots on both the
  M4 board (mounts the FAT) and the Albireo CH376 (auto-detects it); a plain IDE build
  (`STORAGE=ide`) reads it too. Called by `build_kernel.sh`.
- **`build_ide_img.sh`** — older IDE-only image helper.

## Paged kernel modules

Build the on-demand kernel modules (loaded into a bank and `call`ed): config
(`build_cfgmod.sh`), FAT write (`build_fatmod.sh`), floppy write
(`build_floppymod.sh`), dialogs/UI (`build_uimod.sh`); `build_kmod.sh` is the shared
helper they call.

## Asset converters

- **`png2cpc.py`** — a 32×32 PNG → a CPC Mode-1 icon asm source (for `.IST` sets).
- **`png2spr.py`** — a PNG → a `.SPR` cursor sprite.
- **`packicons.py`** — pack icon asm sources into a `.IST` set (in slot order).
- **`packfont.py` / `genfont.py`** — pack an 8×8 asm font into a `.FNT`, or generate
  the 6×8 `DEFAULT.FNT` procedurally.
- **`picconv.py`** — convert a PNG to a 4-colour Mode-1 `.PIC` (GUI or CLI).
- **`iconedit.py`** — a host-side tkinter editor for `.IST` icon sets.
- **`amsdos_header.py`** — prepend a 128-byte AMSDOS header to a RAW binary.

## Conventions

- Output binaries (`*.BIN`, `*.RAW`, `*.dsk`, `QA/GEOBENCH.IMG`) are build artifacts
  and gitignored — except the small staged `QA/` distribution, which is committed
  ready-to-deploy. Regenerate everything with `build_kernel.sh`.
- Any text/data file destined for the CPC must use **CR+LF** line endings.
