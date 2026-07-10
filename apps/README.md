# apps/

Bundled GEOBENCH applications — programs that run on top of the kernel + desktop.
Each app is a separate **SDCC `-mz80` C binary** built by `tools/build_capp.sh`
to run in a 16 KB banked window (`#4000–#7FFF`), reaching the resident kernel only
through the shared `lib/gb` API (`gb_fill`, `gb_wm_*`, the `gb_doc` document
framework, the `gb_popup`/`gb_prompt` dialogs, …). Apps are loaded from disk on
demand (GEOS-style), not resident; the kernel runs the cooperative window-manager
loop and calls each focused window's handlers (issue #45).

## The apps (one C source each, under `apps/<name>/main.c`)

| App | Disk file | What it is |
|-----|-----------|------------|
| desktop  | `DESKTOP.APP`  | the root window — drive/Clock/Trash icons, drag-and-drop, the top bar + System menu, the screensaver idle trigger |
| filemgr  | `FILEMGR.APP`  | per-drive file browser (list/icon views, type→app routing, `..`, Trash) |
| viewer   | `VIEWER.APP`   | text / `.PIC` viewer (banked load for big pictures) |
| notepad  | `NOTEPAD.APP`  | text editor (word-wrap, File/Edit/View, saves `.BAS` CR+LF) |
| iconed   | `ICONED.APP`   | `.IST` icon-set / `.SPR` cursor editor |
| paint    | `PAINT.APP`    | Mode-1 bitmap paint (toolchest, saves `.PIC`) |
| xaos     | `XAOS.APP`     | fractal generator, exports `.PIC` |
| clock    | `CLOCK.APP`    | analog clock widget |
| settings | `SETTINGS.APP` | control panel — font / icons / cursor / backdrop / wallpaper / desktop colours / screensaver, persisted to `GEOBENCH.CFG` |
| telnet   | `TELNET.APP`   | ANSI/Telnet terminal (4x8 charset): CPC TCP via Net4CPC/M4 plus serial, 78x22 windowed + Mode-2 80x25 fullscreen; PCW PerryNet/PerryFi plus serial, 80x25 windowed + 90x28 fullscreen |
| nettest  | `NETTEST.APP`  | network diagnostic — DNS `example.com`, TCP connect, HTTP GET, and PASS/FAIL status; CPC uses the active GBNET backend, PCW uses PerryNet over PerryFi |
| wget     | `WGET.APP`     | GUI HTTP downloader: enter a plain `http://` URL, select an available drive, and stream the response to an automatically derived 8.3 filename; CPC uses GBNET, PCW uses PerryNet |
| shell    | `SHELL.APP`    | fullscreen command shell with `ls`, `cd`, `pwd`, `cat`, `cp`, `rm`, `clear`, `help`, and `exit`; supports A/B/C paths and streamed arbitrary-size file copies |
| timesync | `TIMESYNC.APP` | PCW desktop helper — reads PerryNet's firmware clock with `TIME_GET` when `TIMESYNC=true`, then applies `TIMEZONE=+/-H` |

## Screensavers (`.SAV`)

A screensaver is just an app shipped with a `.SAV` extension. The desktop's
idle timer launches the configured one (`SAVER=<module>` / `SAVERTIME=<minutes>`
in `GEOBENCH.CFG`, set from **Settings → Screensaver**) after the idle timeout, and
System → "Activate screensaver" runs it on demand. Each is a full-screen window
(`WM_FS`) that animates every frame and closes on any input.

The Main CPC boot floppy carries `SQUARES.SAV`; `QA/COMPANION.DSK`, the
Albireo/M4 card distribution, and the MSX2 distribution carry all 16 savers.

| Saver | Disk file | Effect |
|-------|-----------|--------|
| saver    | `SQUARES.SAV`  | random squares (the default saver) |
| deco     | `DECO.SAV`     | Art-Deco / Mondrian rectangle subdivision — ported from the SymbOS `symsav-deco` |
| xmatrix  | `XMATRIX.SAV`  | binary "Matrix" digital rain (white → red → black glow) — ported from `symsav-xmatrix` |
| mountain | `MOUNTAIN.SAV` | isometric 3D filled terrain + white wireframe — ported from `symsav-mountain` (writes the `#C000` screen directly) |
| fractalic | `FRACTALI.SAV` | Sierpinski triangle + Koch snowflake (random each cycle) — ported from `symsav-fractalic` |
| starfield | `STARFLD.SAV`  | 3D star-field flying toward the viewer (blue → red → white, black border) — inspired by `symsav-starfield`, fresh `#C000` impl |
| xroach   | `XROACH.SAV`   | 16×16 cockroaches scuttle on the blue field and scatter from a red rogue roach — ported from `symsav-xroach`, direct `#C000` sprite blit |
| pyro     | `PYRO.SAV`     | fixed-point fireworks — rockets rise and burst into shrapnel showers — ported from xscreensaver |
| forest   | `FOREST.SAV`   | recursive fractal trees with red blossoms — ported from xscreensaver |
| helix    | `HELIX.SAV`    | woven harmonograph curves (sin-table) — ported from xscreensaver |
| catclock | `CATCLK.SAV`   | Kit-Cat Klock — embedded body bitmap (from `assets/catclockbody.png` via `tools/png2catclock.py`) with sliding pupils + real hour/minute hands from `gb_time()` |
| munch    | `MUNCH.SAV`    | "munching squares" XOR moiré sweeping a power-of-two square — ported from xscreensaver |
| rorschach | `RORSCH.SAV`  | 4-fold-symmetric random-walk ink-blots — ported from xscreensaver |
| truchet  | `TRUCHET.SAV`  | random diagonal-tile maze, re-tiled every few seconds — ported from xscreensaver |
| ant      | `ANT.SAV`      | Langton's ant on an 80×50 grid (4-state rule, all four pens) — inspired by xscreensaver |
| lightning | `LIGHTN.SAV`  | midpoint-displacement forked lightning bolts that flash and re-strike — ported from xscreensaver |

The Settings **Module** picker lists every `.SAV` in the system media folder for
the selected drive, so a new screensaver appears there automatically once it is
built and staged. Saver names in `GEOBENCH.CFG` may be drive-qualified
(`A:XMATRIX`, `C:CATCLK`) for mixed floppy/card setups.

## App contract

An app's `main()` runs in its bank, draws its initial content, and registers a
window (`gb_wm_add` for a legacy window, or `gb_wm_managed` for kernel-drawn
chrome), then returns to the opener. The kernel's master loop then drives it:
it polls input and calls the focused window's frame / repaint / event handlers;
the app reads input with `gb_flags`/`gb_mx`/`gb_my` and calls `gb_wm_close` to
quit. Settings and saver apps should keep persistent config/media policy in the
app layer and treat the kernel as a provider of storage, WM, and reload
primitives. See `lib/gb/gb.h` for the full API.
