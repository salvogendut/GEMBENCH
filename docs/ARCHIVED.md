# Archived storage backends

As of **2026-06-22** GEOBENCH ships **one** storage target: the **Albireo (CH376)**
kernel, which also carries the **AMSDOS floppy** fallback (it boots floppy drive A
when no card is present). The **M4 board** and **IDE (SYMBiFACE / Cyboard)** backends
are **archived**: their source stays in the tree, but `tools/build_kernel.sh` no
longer builds or ships them.

## Why

- **M4** — boots and lists, but loading a picture larger than 8 KB (the banked
  `k_pic_open` path) comes up blank on real hardware while working in the emulator.
  The root cause is an M4ROM interrupt/timing divergence the emulator cannot
  reproduce, so fixes can't be validated without a hardware round-trip every time.
  Several attempts (holding `di` across the long load) reboot the machine; the M4 has
  a tight resident ceiling. Parked rather than chased further.
- **IDE** — long since superseded by Albireo for real CPC cards (FAT16 mismatch, see
  `geobench-fat32-ide` memory); only kept as a dormant recovery/test backend.

## Revisit note

M4 is worth revisiting when real hardware testing is available again. As of the
`kernel-architecture-cleanup` split work, the M4 variant still assembles within the
resident stack-reserve limit; its blocker is the real-hardware load/timing behavior
above, not immediate kernel size.

## What's frozen (still in-tree, unbuilt)

| Backend | Source | Build for recovery |
|---------|--------|--------------------|
| M4      | `lib/fs_m4.asm`, `tools/m4detect.asm`, `if STORAGE_M4` block in `lib/fs.asm` | `rasm kernel/gbkern.asm -DSTORAGE_M4=1` |
| IDE     | `lib/fs_ide_fat.asm`, `lib/fs_ide_read.asm`, `lib/fs_fat32_core.asm` (default backend when no `-DSTORAGE_*`) | `STORAGE=ide tools/build_kernel.sh` |

None of this code was deleted — reviving a backend is re-adding its `build_variant`
(and, for M4, the `m4detect.asm`-based detector in `tools/stage_dist.sh`) to the
build, nothing more.

## What ships now

`tools/build_kernel.sh` builds the `GBALB` kernel and stages:

- `QA/CARD/` — loose files: `GB.BAS` (one line, `RUN"GBALB`), `GBALB.BIN`,
  `GEOBENCH.CFG`, and the `GBENCH/` system folder.
- `QA/GEOBENCH.IMG` — a partitioned FAT16 card image for the Albireo CH376.
- `QA/GEOBENCH.DSK` — a bootable floppy image (same kernel, `RUN"GB` → `RUN"GBKERN`).
