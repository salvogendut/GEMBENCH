# Nested subdirectories (depth ≥ 2) don't navigate on this platform

**Status:** won't-fix — a **kernel FAT-core / storage re-mount limitation**, below the File
Manager. Reproduced **deterministically in the 1984 emulator on the IDE backend** (which the
emulator runs faithfully), and on Albireo/CH376. **Resolution: ship content flat in
`/GEOBENCH/` (one level), do not promise nested folders.** All experimental code (the FM
breadcrumb-rebuild, the `gb_root` primitive, `alb_cd_path`) was reverted — the tree matches
the flat `main` layout.

## Definitive reproduction (this session, headless IDE)

Auto-driving the **real** File Manager on the IDE backend (`tools/build_kernel.sh` card +
`1984-ide.conf`, floppy-boot the GBIDE kernel + IDE `ide_image`), recording `total` after each
relist into low-RAM bytes read back from a saved `.sna`:

```
root → GEOBENCH → PICTURES   : 5 → 21 → 4   ✅ descending is perfect
PICTURES → ..  (to GEOBENCH) : 0            ❌ ascends to an EMPTY parent
```

A from-scratch **absolute rebuild** in the FM (`gb_root()` then re-descend the breadcrumb with
`gb_chdir`) did **not** fix it. Instrumentation of that rebuild on the ascent: it correctly
walked the one path component "GEOBENCH" (`ncomp=1`) but **never found it** (`ndesc=0`) —
because right after `gb_root()`, re-enumerating **root** returns **zero entries**. So it is
**not** the SDCC compiler, **not** the incremental `gb_back`, and **not** the FM logic: the
kernel's `gb_root`/`fs_mount` + re-read of root yields an empty directory once a depth-2
cluster-chain has been traversed. Same `fs_to_path("/GEOBENCH")` gives 21 from a shallow state
and 0 from depth-2 — identical code, the only variable is prior kernel state.

## Symptom

Descend the File Manager **two levels** into the tree, then go back up (`..`), and the parent
lists **empty**; every subsequent "up" stays empty, all the way to the drive root. One level
deep and back works perfectly:

```
root → GEOBENCH → ..            ✅  lists root correctly
root → GEOBENCH → PICTURES → .. ❌  /GEOBENCH lists empty (then root empty too)
```

User's words: *"descending one level works, descending 2 does not"* and *"apparently lots of
DOSes on this platform do not support subdirectories."*

## Root cause: the storage layer can't re-enumerate a shallower directory

The decisive measurement (Albireo, with kernel-side + FM-side instrumentation): after going
deep and coming back up, even a **from-scratch re-list of the parent from root returns zero
entries**. Specifically:

- The File Manager was reworked to rebuild its directory **absolutely** every list — reset to
  the drive root (`gb_root`), then re-descend the breadcrumb with the (working) `gb_chdir` —
  so directory state is a pure function of the path, never the incremental `gb_back`.
- Instrumented, `gb_root` **correctly cleared** the path (`alb_path[0] == 0`), yet the very
  next `gb_dir1` enumeration of **root** found **0 entries** — so `seek_named("GEOBENCH")`
  couldn't even find `GEOBENCH` in root, right after having been in `/GEOBENCH/PICTURES`.
- On the CH376 this is its internal *current-folder* state: after enumerating a subdirectory,
  a `FILE_CLOSE` frees the enumeration handle but leaves the chip's current folder deep, so a
  later absolute `SET_FILE_NAME` of a **shallower** path resolves under it and lists empty.
  Forcing a re-root first (`SET_FILE_NAME "/"` + `FILE_OPEN` before each open) **did not** fix
  it either.
- The **IDE** FAT backend (cluster `fs_dir_clus` push/pop — a completely different code path,
  no CH376) reproduces the identical failure, so it is not one chip's quirk: it's the platform.

In isolation the kernel primitives are fine — a gated spike (`-DALBSUBTEST=1` in
`kernel/gbkern.asm`) that drives `k_chdir`/`k_back` with **full** enumerations to completion
at each level lists every depth correctly. The real File Manager differs in that it **stops
enumerations mid-stream** (`dir_seek` positions at an index without reading to the end), and
that, combined with the DOS/firmware directory model, is what these storage layers don't
survive when re-opening a parent. Three independent fixes were tried and **none worked**:

- a `build_list()` "prime" pass in `go_up`;
- `alb_close_enum` (`FILE_CLOSE`) at the top of `fsalb_dir_first` (commit `ae14eef`);
- a full **absolute rebuild** in the FM (`gb_root` + re-descend) **plus** an explicit CH376
  re-root (`alb_cd_root`) before every enumeration.

The break is below the layer we can fix cheaply, and matches the platform reality that these
CPC storage DOSes don't robustly support nested directories. Not worth fighting further.

## Decision / what shipped

- **Pictures ship flat in `/GEOBENCH/`** (`tools/stage_dist.sh`), alongside the apps — depth 1,
  which navigates correctly. No `/GEOBENCH/PICTURES/` subfolder.
- **Everything** from the fix attempts was reverted to `main`: the FM breadcrumb-rebuild
  (`fs_to_path`), the `gb_root` kernel primitive (`GB_ROOT`/`k_root`/libgb `gb_root()`), and the
  Albireo `alb_cd_path` walk (which *rebooted* a real Albireo on boot — never ship it).
- Treat "no nested subdirectories (depth ≥ 2)" as a **known kernel/platform limitation**, not a
  bug to chase. If revisited: the fix is in the **kernel FAT core** (`fs_mount`/`fs_dir_rewind`/
  `fside_dir_first`), not the File Manager — instrument *inside* the kernel (the app can't peek
  `#1C00` FS-state RAM reliably; the firmware lower ROM shadows `#0000–#3FFF` when an app bank is
  mapped). A gated `-DIDESUBTEST` IDE spike was prototyped but needs the boot's ATA-init context
  (it ran too early to read the card).

## How to reproduce (for the record)

### Interactively
Albireo:
```bash
~/Dev/1984/1984 --config=/tmp/gbalb_qa.conf --paste='|drive,"A","SD:"\nrun"gb\n'
```
Then File Manager → into a one-level subdir → into a second subdir → `..`: the parent is empty.
(You must put a depth-2 subdir on the card first, e.g. `mmd -i QA/GEOBENCH.IMG@@16384
::/GEOBENCH/PICTURES`, since the shipped layout is flat.)

### Headless (deterministic)
Temporarily auto-open the FM (`gb_set_drive(0); gb_wm_open("FILEMGR APP");` in
`apps/desktop/main.c`'s first-frame block) and run a frame-spaced
`open_entry(0); open_entry(0); go_up();` in `fm_frame`, writing `total` after the up to a low-RAM
byte; boot with `--save-sna-at=N:f.sna --exit-after=N+10` and read the byte (offset `256+addr`).
A working build lists the real parent count; the bug writes **0**. A visual `--screenshot-at`
of the FM window after the up shows the empty listing (title `Disk C/GEOBENCH`, only the `..`
arrow) just as clearly.

### The IDE 1984 config
The IDE backend needs the Cyboard board with HDCPM + UNIDOS + UNITOOLS + **FATFS-P1/P2** (the
FATFS ROMs expose the `IDE:` UniDOS drive that boots `RUN"GB`), `symbiface_ide=true`, and
`ide_image=` pointing at the same FAT16 card image (`[board:cyboard]` slots 1/7/8/9/10; use
absolute paths). It reproduces the same depth-2 failure as Albireo.

See the `geobench-albireo` memory for the full trail.
