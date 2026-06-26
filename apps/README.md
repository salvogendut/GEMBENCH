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

## Screensavers (`.SAV`)

A screensaver is just an app shipped with a `.SAV` extension. The desktop's
idle timer launches the configured one (`SAVER=<module>` / `SAVERTIME=<minutes>`
in `GEOBENCH.CFG`, set from **Settings → Screensaver**) after the idle timeout, and
System → "Activate screensaver" runs it on demand. Each is a full-screen window
(`WM_FS`) that animates every frame and closes on any input.

| Saver | Disk file | Effect |
|-------|-----------|--------|
| saver    | `CIRCLE.SAV`   | random circles (the first/test saver) |
| deco     | `DECO.SAV`     | Art-Deco / Mondrian rectangle subdivision — ported from the SymbOS `symsav-deco` |
| xmatrix  | `XMATRIX.SAV`  | binary "Matrix" digital rain (white → red → black glow) — ported from `symsav-xmatrix` |
| mountain | `MOUNTAIN.SAV` | isometric 3D filled terrain + white wireframe — ported from `symsav-mountain` (writes the `#C000` screen directly) |
| fractalic | `FRACTALI.SAV` | Sierpinski triangle + Koch snowflake (random each cycle) — ported from `symsav-fractalic`. **Albireo card only** (too big for the floppy) |
| starfield | `STARFLD.SAV`  | 3D star-field flying toward the viewer (blue → red → white, black border) — inspired by `symsav-starfield`, fresh `#C000` impl. **Albireo card only** (the floppy pack is at its 64K ceiling) |
| xroach   | `XROACH.SAV`   | 16×16 cockroaches scuttle on the blue field and scatter from a red rogue roach — ported from `symsav-xroach`, direct `#C000` sprite blit. **Albireo card only** |

The Settings **Module** picker lists every `.SAV` in `/GBENCH`, so a new
screensaver appears there automatically once it is built and staged.

## App contract

An app's `main()` runs in its bank, draws its initial content, and registers a
window (`gb_wm_add` for a legacy window, or `gb_wm_managed` for kernel-drawn
chrome), then returns to the opener. The kernel's master loop then drives it:
it polls input and calls the focused window's frame / repaint / event handlers;
the app reads input with `gb_flags`/`gb_mx`/`gb_my` and calls `gb_wm_close` to
quit. See `lib/gb/gb.h` for the full API.
