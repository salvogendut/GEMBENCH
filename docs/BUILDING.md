# Building, deploying and running

This covers the **Amstrad CPC** build. For the MSX2 build, see
[The MSX2 target](MSX2.md).

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
- **`QA/COMPANION.DSK`** — the **Companion** floppy with the larger apps, extra
  savers, and sample pictures for drive B.

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
