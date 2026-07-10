# Building, deploying and running

The **Amstrad CPC** build is below; the **MSX2** build is in
[Building for MSX2](#building-for-msx2). Both share the RASM kernel + SDCC apps
and happen inside the project distrobox (RASM, SDCC, `mtools`/`dosfstools` on
`PATH`).

## Amstrad CPC

The kernel is assembled with **RASM**; the apps are compiled with **SDCC**
(`sdcc`, `sdasz80`, `makebin` on `PATH`). In practice development happens inside
the project distrobox, where those tools plus `mtools`/`dosfstools` already
exist. One script builds the whole distribution; app and module helper scripts
cache unchanged outputs, so a repeat full build does **not** rebuild every app
unnecessarily. `iDSK` is only needed to inject the convenience `GB.BAS` loader
into the floppy images; without it the floppy still boots via `RUN"GBKERN`:

```bash
bash tools/build_kernel.sh
```

The repository also has a thin top-level Makefile: `make cpc`, `make msx`,
`make all`, and `make check` wrap the same scripts and static checks.

This stages these outputs (the staged media under `QA/` are committed, so you
can test or deploy without rebuilding first):

- **`QA/CARD/`** — the loose card distribution. Copy its contents onto an Albireo
  card or use it as the source for an M4 card/image. The card root holds the
  loader `GB.BAS`, `M4DETECT.BIN`, both kernels (`GBALB.BIN`, `GBM4.BIN`), and
  `GEOBENCH.CFG` — everything else the kernel loads at boot lives in a `GBENCH/`
  subfolder.
- **`QA/GEOBENCH.IMG`** — a ready-to-flash shared **Albireo/M4 card image**: a
  partitioned FAT16 disk the CH376 auto-detects and 1984's M4 image mode can mount.
  Built by `tools/build_card_img.sh`; a 32 MB local artifact, rebuilt every build
  and not committed.
- **`QA/GEOBENCH.DSK`** — the bootable **Main** floppy image.
- **`QA/COMPANION.DSK`** — the **Companion** floppy with the larger apps
  (including Telnet, WGET, Browser and Shell), extra savers, and sample pictures
  for drive B.

Boot with **`RUN"GB`**: the card loader `GB.BAS` loads `M4DETECT.BIN`, probes for
M4ROM's RSX table, and then `RUN"`s `GBM4` on M4 hardware or `GBALB` otherwise. On
the floppy, `GB.BAS` still `RUN"`s `GBKERN`. The selected kernel then drives the
card backend or falls back to the AMSDOS floppy path. On a floppy you can also
`RUN"GBKERN` directly.

```bash
1984 --memory=128 --disk-a=QA/GEOBENCH.DSK --autostart=GB     # floppy in an emulator
```

`tools/build_capp.sh <app_dir> <out.RAW>` builds a single C app against `libgb`
if you just want to iterate on one.

## Optional: the GEOBENCH ROM

`tools/build_rom.sh` builds a 16K upper ROM — `rom/GBALB.ROM` (Albireo) is the shipped
one (`rom/GEOBENCH.ROM` is the archived IDE variant) — that does two things:

- **Offloads the low-level drivers.** The screen-independent storage drivers (FAT
  read/write, the AMSDOS floppy reader, the IDE backend and the CH376/Albireo backend) run
  from the ROM instead of the resident kernel, freeing `#8000` RAM. The resident kernel keeps
  thin stubs that page the ROM in and call it; build that variant with
  `EXTRA_RASM="-DGB_ROM_REQ=1"`. Without the ROM the plain kernel runs every driver resident,
  so the ROM is **optional**.
- **Announces GEOBENCH at boot.** It is a standard CPC **background ROM**, so the firmware
  prints a `GEOBENCH <commit>` banner at cold boot (like M4 or SymbOS) before BASIC's prompt.

Flash the matching ROM into a free upper-ROM slot.

## Building for MSX2

The same kernel and app sources cross-build for the MSX2 (`-DPLATFORM_MSX` for the
kernel, `-DGB_MSX2` for the apps). See [The MSX2 target](MSX2.md) for the runtime
design; this is the build.

```bash
bash tools/fetch_msx_deps.sh       # one-time: Nextor system files + NMS 8250 ROMs
bash tools/build_kernel_msx.sh     # the whole MSX2 distribution
tools/run_msx.sh                   # boot it in openMSX (interactive)
MSX_SHOTS="25 40" tools/run_msx.sh # headless: screenshots into build/msx/
```

`build_kernel_msx.sh` produces:

- **`QA/MSX/`** — the loose MSX distribution (committed): `GBMSX.COM`, an
  `AUTOEXEC.BAT` that runs it, `GEOBENCH.CFG`, the `GBENCH/` system folder
  (fonts/icons/cursor/modules/apps/savers) and the sample pictures.
- **`QA/GBMSX.IMG`** — a bootable 32 MB **FAT16 hard-disk image** (a local
  artifact, git-ignored like the CPC card image). `tools/build_msx_img.sh` fills
  it from `QA/MSX` plus the Nextor system files, so Nextor's Sunrise IDE driver
  boots it straight to the desktop.

**Assets are packaged automatically.** Anything dropped into `assets/iconsets`,
`assets/backdrops` or `assets/pictures` is transcoded from CPC Mode 1 to V9938
Screen 6 and staged for both root (viewable) and `GBENCH/` (selectable via
`ICONS=`/`BACKDROP=`/`WALLPAPER=`) — the tools take a `--platform msx2` flag
(`packicons`, `png2spr`, `picconv`, `png2backdrop`, `png2cpc`) or are dedicated
transcoders (`pic_to_msx`, `ist_to_msx`, `bdp_to_msx`). The mouse pointer is a
V9938 hardware sprite: a hand-edited **`assets/pointer.SPR`** (edit it with
`tools/iconedit.py --platform msx2 assets/pointer.SPR`) is preferred over
generating it from `assets/pointer.png`.

### Deploying

Copy the contents of **`QA/MSX/`** onto storage your MSX-DOS 2 / Nextor setup
mounts (an SD card, IDE disk, …) and run **`GBMSX.COM`** (the `AUTOEXEC.BAT` runs
it for you) — or write the whole `QA/GBMSX.IMG` to the device. It needs **MSX-DOS
2** (mapper support); a bare MSX2 with only Disk BASIC / MSX-DOS 1 won't run it.

### Boot floppy (experimental)

`tools/build_msx_floppy.sh` assembles a single bootable **720 KB MSX-DOS 2 floppy**
(`QA/GBMSX.DSK`) — MSX floppies are big enough that the whole ~612 KB distro fits
on one disk. It carries third-party MSX-DOS 2 files (`MSXDOS2.SYS`, `COMMAND2.COM`),
so treat it as an optional generated test artifact; it may appear untracked after
running the builder. **Status:** it boots MSX-DOS 2 and GEOBENCH starts, but the
display currently stays blanked under a floppy DOS2 setup (the disk ROM holds the
screen off during floppy access) — under investigation; the IDE/SD image
(`QA/GBMSX.IMG`) is the working path for now.
