# Roadmap (rough)

## Done

1. ✅ **Boot + desktop** — Mode 1 backdrop, top bar, software pointer.
2. ✅ **Windowing + icons** — windows with title bars/gadgets, draggable icons.
3. ✅ **File manager** — browse a drive (list/icon views, sorted by type + name),
   select, scroll, open by type.
4. ✅ **Banked app model + app API** — separate-binary apps over a kernel API.
5. ✅ **Apps in C** — the whole app layer moved from assembly to C over `libgb`.
6. ✅ **Storage write layer** — Albireo, M4 and floppy read/write paths support
   save/delete/copy; the archived IDE/FAT backend remains buildable for recovery.
7. ✅ **Apps** — Notepad, ICONED, Paint, Clock, Viewer, Xaos, Diskutil, and a
   **Settings** control panel (font / icon set / cursor / drive-qualified
   backdrop-wallpaper-saver settings + a live desktop-colours editor). The CPC
   distro also ships Telnet and Nettest.
8. ✅ **Unified menu system (`gb_doc`)** — one File / Edit / View menu framework for
   every app (New/Load/Save/Save As, a shared cross-app clipboard, **Fullscreen**, a
   navigable Open/Save dialog in a paged module); the desktop's System menu and the
   clock's Options menu render through it too.
9. ✅ **Driver offload to ROM (#152)** — the screen-independent low-level drivers (FAT
   read/write, AMSDOS floppy, IDE, CH376/Albireo) run from a 16K upper ROM
   (`GEOBENCH.ROM`/`GBALB.ROM`), freeing resident RAM; the ROM is also a CPC background ROM
   that boots a `GEOBENCH <commit>` banner.
10. ✅ **M4 board SD/TCP support (#174, #259)** — a file-level backend (`GBM4.BIN`)
   ships beside `GBALB.BIN` on the shared card image. `GB.BAS` detects M4ROM
   (`KL_FIND_COMMAND` for an M4 RSX) and selects the right kernel. M4 supports
   directory, load, save/create, delete, free-space queries, and TCP through
   `M4SAVE.MOD` / `GBNETM4.MOD`. Its storage and
   network calls preserve the active CPC video mode, so Telnet's Mode 2 fullscreen
   terminal survives paged module loads.
11. ✅ **Kernel source split + build cache** — the resident kernel contracts now
   live in dedicated source files with checked ABI/low-RAM maps, and the full
   build reuses unchanged app/module outputs instead of recompiling everything.
12. ✅ **MSX2 port (#287)** — the kernel and app set cross-build to a second
   platform: `GBMSX.COM` under MSX-DOS 2 / Nextor, V9938 Screen 6, hardware
   sprite pointer, MSX mouse, all 16 screensavers, and an openMSX test harness
   (`tools/build_kernel_msx.sh` + `tools/run_msx.sh`).
13. ✅ **Portable picture payloads (#381)** — CPC, MSX2, and PCW distributions
   carry the same canonical GBPC v2 Mode-1 `.PIC` bytes. MSX2 and PCW translate
   pixels at the display boundary; Paint and XAOS also save the portable format.

## Next

- **Shared non-picture assets across platforms** — icon sets and backdrops still
  have platform-specific Mode-1 / Screen-6 payloads. Pictures are already shared
  through the portable GBPC v2 format.
- **Paint** follow-ups — resizable canvas and scrolling for pictures bigger than the
  screen (Fullscreen already centers the canvas + tools).
- **Drawers/folders** and richer desktop arrangement.
- **Per-screensaver configuration** — the savers currently use baked-in defaults
  (there is no per-module setup panel yet); Settings only picks the module + idle
  timeout.
