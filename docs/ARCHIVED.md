# Archived storage backends

As of issue **#259**, GEOBENCH again ships **two** card kernels on the same FAT
image:

- **Albireo (CH376)** as `GBALB.BIN`.
- **M4 board** as `GBM4.BIN`, selected by the BASIC loader when M4ROM is present.

Both carry the **AMSDOS floppy** fallback. The **IDE (SYMBiFACE / Cyboard)** backend
is the only storage backend still archived: its source stays in the tree, but
`tools/build_kernel.sh` no longer builds or ships it.

## Why

- **IDE** — long since superseded by Albireo for real CPC cards (FAT16 mismatch, see
  `geobench-fat32-ide` memory); only kept as a dormant recovery/test backend.

## M4 support boundary

The M4 backend is active again for boot, directory listing, load, save/create, and
TCP networking. The same `QA/GEOBENCH.IMG` can be used by Albireo and by 1984's
M4 image mode.

Two M4 caveats remain:

- delete is not wired yet: M4ROM exposes `C_ERASEFILE`, but 1984's image-backed
  M4 file API supports write/create but not FAT entry erase;
- the historical real-hardware report of blank >8 KB pictures needs to be
  revalidated on current M4ROM and current GEOBENCH.

## What's frozen (still in-tree, unbuilt)

| Backend | Source | Build for recovery |
|---------|--------|--------------------|
| IDE     | `lib/fs_ide_fat.asm`, `lib/fs_ide_read.asm`, `lib/fs_fat32_core.asm` (default backend when no `-DSTORAGE_*`) | `STORAGE=ide tools/build_kernel.sh` |

None of the IDE code was deleted — reviving it is re-adding its `build_variant`
to the build and revalidating the FAT/image behavior.

## What ships now

`tools/build_kernel.sh` builds the `GBALB` and `GBM4` kernels and stages:

- `QA/CARD/` — loose files: `GB.BAS`, `M4DETECT.BIN`, `GBALB.BIN`, `GBM4.BIN`,
  `GEOBENCH.CFG`, and the `GBENCH/` system folder, including `GBNET.MOD`,
  `GBNETM4.MOD`, and `M4SAVE.MOD`.
- `QA/GEOBENCH.IMG` — a partitioned FAT16 card image for Albireo and M4 image mode.
- `QA/GEOBENCH.DSK` — a bootable floppy image (same kernel, `RUN"GB` → `RUN"GBKERN`).
