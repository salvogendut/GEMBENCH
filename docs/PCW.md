# GEOBENCH on the Amstrad PCW 8256 / 8512 (#331)

The third GEOBENCH platform: the same kernel body, window manager, and C
apps as the CPC and MSX2 targets, running on the Amstrad PCW — a machine
with no ROM, no firmware, and (natively) no colour.

**Runs on real hardware**: verified booting a physical PCW 8256 from a
Gotek (FlashFloppy) serving `QA/PCW/GEOBENCH.DSK`. On real machines the
display is the native 1bpp monochrome (see the colour section below).

```
bash tools/build_kernel_pcw.sh          # -> GEOBENCH.DSK + COMPANION.DSK + MEDIA.DSK
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
bit transform `screen = ((gb & #55)<<1) | ((~gb & #AA)>>1)`. Most assets
stay in GB pen-space / MSX Screen-6-style bytes and are permuted by the PCW
driver on write (`packicons`, `ist_to_msx`, `bdp_to_msx`). Raw-restore assets
are the exception: the splash, pointer, and staged `.PIC` files are
pre-permuted to CGA2 hardware-space at build time (`pic_to_pcw.py` for
pictures), because `restore_block` copies those bytes straight to the screen.

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

CP/M 2.2 on CF2 180K (40 tracks, 1K blocks, 64 dir entries, flat root).
Read AND write: save/truncate, append (`FS_XFLAGS` bit1), delete, and
chunked reads (`FS_XFLAGS` bit0 + 24-bit `FS_LOAD_OFS`) — so any-size
drag-copy and the Viewer's big pictures work. Sizes are 128-byte CP/M
records (`#1A`-padded tails). Drive B is supported for CF2 and CF2DD discs
(`fs_set_drive` remounts; `k_drive_poll` probes with a single read).

## What ships where

- **GEOBENCH.DSK** (bootable): kernel + DESKTOP, FILEMGR, NOTEPAD,
  SETTINGS, VIEWER, CLOCK, TIMESYNC, ICONED, SHELL + the portable savers
  (SQUARES — the default —, ANT, XMATRIX, DECO) + fonts, icon sets, pointer,
  splash, Browser's `GBWEB.MOD`/`BRSAVE.APP` helpers, `LOGO.PIC` (default
  wallpaper), GEOBENCH.CFG. No other picture is included.
- **COMPANION.DSK** (CF2 data): backdrop tiles,
  TELNET.APP (PerryNet/PerryFi plus serial), NETTEST.APP (PerryNet/PerryFi),
  WGET.APP and BROWSER.APP (HTTP over PerryNet), XAOS.APP, WELCOME.TXT.
- **MEDIA.DSK** (720K CF2DD data): every picture from `assets/pictures`, converted
  to the PCW display encoding. Use it in drive B when browsing the gallery.

## PCW Time Sync With PerryFi / PerryNet

On real PCW hardware, automatic desktop time sync needs a PerryFi card running
the PerryNet firmware. Configure WiFi in PerryNet first, then enable sync in the
GEOBENCH boot config:

```text
TIMESYNC=true
TIMEZONE=+2
```

`TIMESYNC=true` makes the desktop launch `TIMESYNC.APP` at startup.
`TIMEZONE=` is a whole-hour offset from UTC; use `TIMEZONE=+2` for CEST,
`TIMEZONE=+1` for CET, or another `+H` / `-H` value for your local time. There
is no daylight-saving rule engine in GEOBENCH yet, so the offset is explicit.

`TIMESYNC.APP` asks PerryNet for its firmware-maintained UTC clock with
`TIME_GET`, applies the configured `TIMEZONE=` offset, sets the GEOBENCH
software clock, then detaches. PerryNet initializes that clock with SNTP after
WiFi comes up; if the firmware clock is not valid yet, GEOBENCH leaves the
desktop running normally and makes a bounded number of later lightweight
`TIME_GET` retries instead of blocking boot.

TELNET's terminal is **80×25 in the window and 90×28 fullscreen**
(Telnet menu toggle; Ctrl-] or ESC exits) — a 4×8 charset
(`apps/telnet/charset4.h`, generated by `tools/gen_telnet_charset4.py`)
drawn straight into the framebuffer: the PCW char-cell layout makes each
text cell 8 *contiguous* bytes (`cellrow*1024 + col*8`), one `lut4`
lookup per glyph line. Fullscreen is the viewer-style `WM_FS` borderless
window — no video-mode switch, so it looks the same on real hardware.
The faster PerryNet profile requests nominal `19200` baud; PerryFi/PerryNet
firmware aliases that to the PCW's exact `17857` baud divisor.

`WGET.APP` and `BROWSER.APP` use the same PerryNet host-pulled TCP path. WGET
downloads a plain `http://` URL to floppy A or B, writing incrementally rather
than holding the response in RAM; the destination name is derived from the final
URL path component and converted to CP/M-compatible 8.3 form. WGET follows up
to four absolute or relative redirects and keeps an interrupted partial file. A
later PCW attempt restarts that file rather than sending Range: CP/M records
only retain a 128-byte-granular size, so an exact resume offset cannot be
reconstructed safely. Browser follows redirects too, parses chunked HTML bodies,
renders text/list/link text into a borrowed 16K page holding up to 255
fixed-width lines. It renders one viewport, pauses the open PerryNet TCP stream,
and resumes from the retained receive byte as the user scrolls down; cached lines
remain available for upward scrolling. The proportional scrollbar shows that
continuation is available, and reaching the line bound is reported as truncated.
Underlined link rows open when clicked, and one previous URL is retained for
Back. Its File menu loads and saves offline `.HTM` files, and File Manager opens
those files in Browser with the text-file icon. The Settings menu persists an
optional plain-HTTP proxy as `PROXY=` in `GEOBENCH.CFG`; selecting Direct clears
it. HTTPS is not supported because the PCW side has no TLS implementation.

## Not (yet) on the PCW

- The direct-`#C000` savers (PYRO, HELIX, STARFLD, …) — they poke the CPC
  framebuffer; each needs a PCW plot path.
- DISKUTIL (needs a PCW FORMAT TRACK backend), PAINT and GB-BASIC (their
  repos need `-DGB_PCW` targets).
- TELNET, WGET and Browser use PerryNet/PerryFi directly for TCP sessions on
  PCW. They open PerryNet sockets in host-pulled receive mode (`TCP_RECV`) so
  network data is only transmitted while the app is actively polling serial; a
  shared direct network-module backend remains a later target.
- CF2DD 720K media (2K blocks, 16-bit allocation entries) — drive B
  currently expects CF2-format discs.

## The real uPD765 (rules the emulator does not enforce)

The first Gotek boots on a physical 8256 failed even though the emulator
was flawless. The root causes were found by diffing our FDC code against
a CP/M 3 boot sector and the MCU bootstrap — both proven on that machine
(#344). If you touch any FDC code, these are load-bearing:

- **MSR settle**: after every command byte written to, or result byte
  read from, the data register, the real chip's main status register
  stays stale for ~12µs. Follow each such access with an `EX (SP),HL`
  ×4 chain before polling MSR again — otherwise the stale RQM
  double-feeds command bytes and every command is corrupt.
- **Seek/recalibrate completion**: wait for the ASIC's live FDC INTRQ
  mirror (port `#F8` read, bit 5), then acknowledge with **one** SENSE
  INTERRUPT. Never hammer SENSE INT while a seek is stepping.
- **Read/write shape**: TC clear (`#F8` cmd 6) before the command;
  READ `#66` (MFM+SK) / WRITE `#45` with **EOT = 9** so the chip streams
  into the inter-sector gap; TC set (cmd 5) right after the payload
  bytes; then wait INTRQ and read the full result set. `EN` alone in
  ST0 is TC-normal — only `ST0 & #88` (invalid/ready-change IC, NR) is
  fatal.
- The transfer loops must beat the **~32µs MFM byte window**: `INI`/`OUTI`
  with the count in B (2 × 256 per sector), two `ADD A,A` + `JP P` for
  the EXM test — the machine's own bootstrap loop shape.
- The **emulator proves nothing about FDC timing or handshakes** — it
  updates MSR instantly and enforces no byte window. Validate FDC changes
  against real hardware, or at minimum against the byte-for-byte shape of
  a boot sector known to work there.

### Boot diagnosis beacons

The boot sector paints its progress on the real screen with zero disk
I/O (a minimal roller table pointing every scanline at one shared row):

| Pattern | Meaning |
|---|---|
| nothing (unchanged from power-on) | boot code never ran: checksum/entry/image serving |
| fine vertical stripes, stuck | FDC init / recalibrate / seek hangs |
| sparse stripes, frozen | sector reads hard-failed; **ST0/ST1/ST2 are painted as three rows of 8 bit-blocks** (bit 7 leftmost, lit = 1) — photograph and decode |
| solid lit / dither texture | kernel loaded and alive |

## Gotchas (hard-won)

- Anything that hardcodes byte `#00` as "pen 0" is wrong here (the
  permuted pen 0 is `#55`) — route fills through `pen_to_byte`. The same
  goes for `#F0`/`#0F` Mode-1 literals (see `KWB_*` in `gbkern.asm`).
- App code with `#ifdef GB_MSX2 … #else` platform arms: the `#else` side
  often calls **CPC firmware vectors** (`#BBxx`/`#BCxx`), which on the
  PCW are bytes inside the kernel — instant garbage execution. Grep for
  `0xBB`/`0xBC`/`0xFD1` before staging any app, and give PCW the
  MSX-safe arm (or its own).
- Nothing may assume the slot-3 window persists across calls; map before
  use. The stack must never live in `#C000`–`#FFFF`.
- RASM once emitted a phase-inconsistent binary (a CALL kept a stale
  pass-1 target); `tools/pcwspike/build.sh` cross-checks CALL targets
  against the symbol table. If PCW code crashes inexplicably after a
  small edit, suspect this first.
- CPS8256 serial baud: the 8253 PIT is clocked at **2 MHz** and the DART
  divides by 16, so **baud = 125000 / count** — 9600 is count 13 (9615),
  per Joyce's `JoyceCPS.cxx` (written against the real device). Not the
  PC-style 1.8432 MHz crystal: count 12 is 10417 baud = framing garbage
  on real hardware, and the 1985 emulator stores the count without
  timing it, so it cannot catch a wrong divisor.
- CPS8256 serial modem-control: GEOBENCH's direct-boot setup uses DART WR5
  `0x68` (TX enable + 8-bit TX, RTS/DTR inactive). Real PerryFi hardware
  answered `AT` at 9600 with this value, while WR5 `0xEA` (RTS/DTR asserted)
  did not.
- Drive B's stepping depends on the MECHANISM, not the media: an
  8512-style 80-track CF2DD drive double-steps CF2 discs, but a Gotek
  (or a 40-track bolt-on B) maps tracks 1:1 — hardcoding either breaks
  the other (real-HW symptom: B mounts but lists empty, because track-0
  reads are identical both ways and only the directory diverges).
  `pcwfdc_detect` measures it at mount: seek physical track 2, READ ID,
  and let the on-media cylinder answer (C=1 → double-step, C=2 → 1:1).
  The spike harness tests both via a 43-track B image (1985's AUTO
  heuristic serves >42-track images 1:1, a stand-in for the Gotek).
