# GEOBENCH on the Amstrad PCW 8256 / 8512 (#331)

The third GEOBENCH platform: the same kernel body, window manager, and C
apps as the CPC and MSX2 targets, running on the Amstrad PCW — a machine
with no ROM, no firmware, and (natively) no colour.

```
bash tools/build_kernel_pcw.sh          # -> QA/PCW/GEOBENCH.DSK + COMPANION.DSK
~/Dev/1985/1985 --config debug/1985-pcw.conf --disk-a QA/PCW/GEOBENCH.DSK
```

Headless smoke test:

```
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ~/Dev/1985/1985 \
    --config debug/1985-pcw.conf --disk-a QA/PCW/GEOBENCH.DSK \
    --unthrottled --screenshot-at 2500:/tmp/pcw.ppm --exit-after 2600
```

## How it boots (no CP/M anywhere)

The PCW has no ROM: at power-on the printer-controller MCU loads track 0 /
sector 1 of drive A to `#F000`, checks that the 8-bit sum of the sector is
`#FF`, and jumps to `#F010`. GEOBENCH ships its own boot sector
(`kernel/pcwboot.asm`): a polled uPD765 loader that pulls the kernel image
from the disc's reserved tracks straight to `#8000` and jumps to it.

The disc still carries a standard CP/M 2.2 filesystem (fully readable on a
real CP/M machine) holding the apps and assets; `lib/pcw/fs.asm` reads and
writes it directly over `lib/pcw/fdc.asm`. `tools/mkpcwdsk.py` builds the
whole disc on the host: EXTENDED .DSK container, boot sector with the
checksum fixed, kernel in reserved tracks, files in the filesystem
(`--add FILE[=NAME]`).

`GB_EXIT` warm-reboots through the MCU bootstrap still resident at `#0000`.

## Video: 4 colours via the emulator's CGA2 mode

The real PCW is 1bpp 720×256 through "roller RAM" (a 512-byte table of one
word per scanline; the in-row layout is char-cell interleaved, so
horizontally adjacent bytes are **8 apart**). The 1985 emulator's
`video_mode = cga2` reinterprets the same bitmap as 2bpp — **360×256,
4 colours, 90 byte columns, 4 px/byte** — with exactly the MSX Screen 6
pixel packing. GEOBENCH uses a 90×248 desktop (byte-wide clip cells can't
hold 256) with the last 8 scanlines as a static letterbox strip.

The CGA2 palette is fixed (black/cyan/magenta/white). The driver
(`lib/pcw/screen.asm`) permutes GEOBENCH pens on the way to the screen —
pen 0 blue→cyan, 1 white→white, 2 black→black, 3 red→magenta, which is the
bit transform `screen = ((gb&#55)<<1) | ((~gb&#AA)>>1)` — so **assets stay
in the MSX Screen-6 encoding** and the whole MSX transcoder chain
(`packicons/ist_to_msx/pic_to_msx/bdp_to_msx --platform msx2`) is reused
verbatim. Only save-block-format blobs (the splash) and the pointer
(`png2spr --platform pcw`) are pre-permuted to hardware pens at build time.

**On real hardware the CGA2 mode does not exist**: a real PCW shows the
same bitmap as monochrome with fine stripe textures. The port targets the
emulator's colour mode by design (#331 decision).

## Input

The pointer is the **DK'tronics sound board joystick** (AY register 14 via
ports `#AA`/`#A9`, active-low) merged with the keyboard cursor keys;
SPACE doubles as fire, EXIT quits. `k_getkey` scans the memory-mapped
keyboard matrix itself (rows 0–10 at `#FFF0` with block 3 in the slot-3
window, active-high, Joyce layout with shift tables) — there is no
firmware to ask. The machine runs fully DI; k_poll paces on the frame
flyback (port `#F8` bit 6).

## Memory plan

| CPU slot | Contents |
|---|---|
| 0 `#0000` | phys block 0: low-RAM contracts (#1000+), MCU bootstrap at #0000 |
| 1 `#4000` | app paging window (port `#F1`); pool = phys blocks `#86`–`#8D`; roller table at phys `#4000` (block 1) |
| 2 `#8000` | phys block 2: the kernel (`GB_KERNEL`), stack down from `#C000` |
| 3 `#C000` | shared window (port `#F3`): framebuffer blocks 4–5 while drawing, keyboard block 3 while polling |

Framebuffer: phys blocks 4–5, cellrow `r` at `#10000 + r*1024`. PAGE_DATA =
block 14 (`#8E`). 256K (8256) and 512K (8512) both work; the boot probe
reports the size in the top bar.

## Storage

CP/M 2.2 on CF2 180K (40 tracks, 1K blocks, 64 dir entries, flat root —
CP/M has no directories, so content ships flat like the card platforms).
Read AND write: save/truncate, append (`FS_XFLAGS` bit1), delete, and
chunked reads (`FS_XFLAGS` bit0 + 24-bit `FS_LOAD_OFS`) — so any-size
drag-copy and the Viewer's big pictures work. Sizes are 128-byte CP/M
records (`#1A`-padded tails). Drive B is supported for CF2 discs
(`fs_set_drive` remounts; `k_drive_poll` probes with a single read).

## What ships where

- **GEOBENCH.DSK** (bootable): kernel + DESKTOP, FILEMGR, NOTEPAD,
  SETTINGS, VIEWER, CLOCK, XAOS, ICONED + the portable savers (SQUARES —
  the default —, ANT, DECO, XMATRIX) + fonts, icon sets, pointer, splash,
  GEOBENCH.CFG.
- **COMPANION.DSK** (data): the picture gallery, backdrop tiles,
  CLASSIC.FNT, WELCOME.TXT.

## Not (yet) on the PCW

- The direct-`#C000` savers (PYRO, HELIX, STARFLD, …) — they poke the CPC
  framebuffer; each needs a PCW plot path.
- DISKUTIL (needs a PCW FORMAT TRACK backend), PAINT and GB-BASIC (their
  repos need `-DGB_PCW` targets), TELNET (CPC network hardware).
- CF2DD 720K media (2K blocks, 16-bit allocation entries) — drive B
  currently expects CF2-format discs.

## Gotchas (hard-won)

- The FDC transfers **one sector per READ/WRITE command** in this polled
  non-DMA setup — never use multi-sector commands.
- Anything that hardcodes byte `#00` as "pen 0" is wrong here (the
  permuted pen 0 is `#55`) — route fills through `pen_to_byte`.
- Nothing may assume the slot-3 window persists across calls; map before
  use. The stack must never live in `#C000`–`#FFFF`.
- RASM once emitted a phase-inconsistent binary (a CALL kept a stale
  pass-1 target); `tools/pcwspike/build.sh` cross-checks CALL targets
  against the symbol table. If PCW code crashes inexplicably after a
  small edit, suspect this first.
