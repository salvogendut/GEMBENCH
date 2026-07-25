# tools/

Host-side (PC) tooling for building GEOBENCH and preparing assets. None of this
runs on the CPC — it produces the binaries and data files that do. The kernel is
assembled with **RASM**; the C apps with **SDCC**. Most builds run inside the
project's distrobox (which carries `rasm`, `sdcc`, `mtools`, `dosfstools`, ...).

## Build orchestration

- **`build_kernel.sh`** — the one-shot build. Assembles the shipped **`GBALB`** (Albireo)
  and **`GBM4`** (M4) kernels, packs the apps, and stages the distribution into `QA/`:
  the loose card files (`QA/CPC/CARD/`), the Main and Companion floppies under
  `QA/CPC/Floppies/`, the gallery `EXTRAS.DSK`, and the shared card image
  (`QA/CPC/GEOBENCH.IMG`).
  The IDE backend is archived (frozen, not built — see `docs/ARCHIVED.md`);
  rebuild it for recovery with `STORAGE=ide`. `STORAGE=m4` leaves an M4 dev-harness
  kernel in `build/`. `FAT16=1` and `EXTRA_RASM=...` tune the variant
  (e.g. `EXTRA_RASM="-DGB_ROM_REQ=1"` for the ROM-offload kernel).
- **`build_kernel_pcw.sh`** — builds the standalone PCW boot disk, companion
  disk, and 720K `EXTRAS.DSK`. The extras build stages the PCW payloads from
  sibling GB-PAINT and GB-BASIC checkouts.
- **`build_kernel_msx.sh`** — builds the `GBMSX.COM` video-mode selector,
  `GBMSX6.COM`, `GBMSX7.COM`, the MSX2 app/module payload, and the bootable
  Nextor `QA/GBMSX.IMG`. Set `MSX_UNAPI_TSR` to stage a local
  openMSXnet `UNAPINET.COM` before `GBMSX.COM`; the TSR remains untracked.
- **`run_msx.sh`** — launches the MSX2 image in native or Flatpak openMSX.
  It adds openMSXnet's `unapinet` extension by default when using its custom
  emulator build and automatically selects a bundle in
  `QA/MSXDEPS/openmsxnet/`. `OPENMSXNET_HOME` overrides that location;
  missing host libraries are supplied through `my-distrobox`
  (`MSX_DISTROBOX` overrides the name). `MSX_UNAPI=0` disables the extension.
- **`m4detect.asm`** — a tiny BASIC-callable detector that asks the firmware
  (`KL_FIND_COMMAND`) whether an M4 ROM RSX is installed. The staged `GB.BAS` loads
  it as `M4DETECT.BIN` and uses its result to pick `GBM4` vs `GBALB`.
- **`build_rom.sh`** — builds the 16K upper ROMs that offload the low-level drivers
  and carry the cold-boot banner: `rom/GBALB.ROM` (Albireo, shipped) and `rom/GEOBENCH.ROM`
  (the archived IDE backend). Bakes the git commit into the banner
  (`rom/gitcommit.inc`, generated).
- **`build_m4netmod.sh [out.RAW]`** — builds `GBNETM4.MOD`, the M4ROM TCP command
  backend for the shared `gb_net_*` API.
- **`build_m4savemod.sh`** — builds `M4SAVE.MOD`, the M4ROM save/delete/free-space
  and chunked-read backend loaded on demand by the M4 kernel.
- **`stage_dist.sh <out>`** — stages the shared Albireo/M4 card distribution
  (`GB.BAS`, `M4DETECT.BIN`, `GBALB.BIN`, `GBM4.BIN`, and the `GBENCH/` payload)
  into a directory.
- **`build_capp.sh <app_dir> <out.RAW>`** — builds a single C app against `libgb`,
  for iterating on one app. App/module helper scripts write `*.stamp` metadata
  beside their outputs so a repeated full build can reuse unchanged binaries and
  skip recompiling untouched apps/modules. With `NET=1`, CPC links the paged
  network stub and `APPDEFS=-DGB_MSX2` selects the TCP/IP UNAPI backend.
  `WIDGETS=1` links reusable buttons/fields and `SCROLL=1` links the vertical
  scrollbar unit. `TOGGLE=1`, `STEPPER=1`, `SELECTOR=1`, and `SLIDER=1`
  independently link the corresponding settings controls, so tight apps pay only
  for controls used.
- **`check_abi_table.py`** — verifies the `kernel/gbkern.asm` jump-table comments
  match the exported `lib/gbapp.inc` slot addresses through `kernel/api_table.inc`.
- **`check_lowram_map.py`** — validates the fixed low-RAM ownership map in
  `kernel/lowram.tsv` for accidental range overlaps.
- **`deploy_ide.sh`** — *(archived)* copy the staged distribution onto a real/emulated IDE
  image (for the frozen IDE backend).

## Card / disk images

- **`build_card_img.sh [CARD] [IMG]`** — builds a partitioned **FAT16 card image**
  (`QA/CPC/GEOBENCH.IMG` by default) from the staged `QA/CPC/CARD/` for Albireo and M4
  image mode. Called by `build_kernel.sh`.
- **`mkcpcmedia.py OUT.dsk --add FILE ...`** — builds the extended 80-track,
  single-sided AMSDOS DATA image used for the CPC picture gallery.
- **`mkpcwdsk.py`** — builds bootable or data PCW CF2/CF2DD images, including
  `QA/PCW/EXTRAS.DSK`.
- **`build_ide_img.sh`** — *(archived)* older IDE-only image helper.

## Paged kernel modules

Build the on-demand kernel modules (loaded into a bank and `call`ed): config
(`build_cfgmod.sh`), FAT write (`build_fatmod.sh`), floppy write
(`build_floppymod.sh`), M4 save (`build_m4savemod.sh`), dialogs/UI
(`build_uimod.sh`, which also embeds the root `VERSION` and current Git commit
for System > About GEOBENCH), and networking (`build_netmod.sh`, `build_m4netmod.sh`);
`build_kmod.sh` is the shared helper used by the smaller asm/C module scripts.

## Asset converters

- **`png2cpc.py`** — a 32×32 PNG → a CPC Mode-1 icon asm source (for `.IST` sets).
- **`png2spr.py`** — a PNG → a `.SPR` cursor sprite (2 pre-shifted phases, mask+data
  **interleaved** per byte to match the kernel compositor — see `lib/cursor.asm`).
- **`packicons.py`** — pack icon asm sources into a `.IST` set (in slot order); builds
  `build/DEFAULT.IST` fresh each build. The `.IST` files are stored in the canonical
  CPC Mode-1 payload on disk; MSX/PCW decode them at load time with `icon_convert`
  in the kernel.
- **`ist_append.py`** — append icon asm bitmap(s) to an existing (hand-tuned) `.IST`
  set, bumping the count + shifting offsets; used to add a new slot to the tracked
  `assets/iconsets/*.IST` sets that `packicons.py` doesn't regenerate.
- **`ist_replace_slot.py`** — replace one positional icon in a tracked `.IST` set
  from an icon asm source while preserving the set's slot count and layout.
- **`packfont.py` / `genfont.py`** — pack an 8×8 asm font into a `.FNT`, or generate
  the 6×8 `DEFAULT.FNT` procedurally.
- **`picconv.py`** — convert an image to portable four-colour GBPC v2 (the
  default) or an MSX Screen 7 sixteen-colour `.PIC` (`--colors 16`), using
  either the GUI or CLI. Width and height can be entered independently; leave
  either one blank to preserve the source aspect ratio.
- **`gen_pic_luts.py`** — generate and verify the reversible MSX2/PCW picture
  display lookup tables used by the kernels.
- **`png2backdrop.py` / `patternedit.py`** — create or edit portable canonical
  Mode-1 `.BDP` backdrop tiles. CPC uses them directly, MSX2/PCW decode them when
  loaded, and `bdp_to_msx.py` remains only for legacy artifacts.
- **`check_pic_distribution.py`** — verify canonical `.PIC`/`.BDP` byte identity
  across staged folders and CPC/PCW disks.
- **`iconedit.py`** — a host-side tkinter editor for `.IST` icon sets and `.SPR`
  cursors. The keyboard arrow keys shift the current bitmap one pixel for easy
  alignment; pixels shifted beyond an edge are clipped.
- **`amsdos_header.py`** — prepend a 128-byte AMSDOS header to a RAW binary.

## Conventions

- Output binaries under `build/` are local artifacts. The staged `QA/`
  distribution is committed, including the `.dsk` media, so every shipped change
  should rebuild those images before commit.
- Any text/data file destined for the CPC must use **CR+LF** line endings.
