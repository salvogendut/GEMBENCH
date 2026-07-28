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
   backdrop-wallpaper-saver settings + a live desktop-colours editor). CPC and
   PCW ship the complete network app set; MSX2 currently ships Browser and
   Telnet through TCP/IP UNAPI.
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
   platform under MSX-DOS 2 / Nextor, with selectable V9938 Screen 6/7
   backends, a hardware sprite pointer, MSX mouse, all 16 screensavers, and an
   openMSX test harness (`tools/build_kernel_msx.sh` + `tools/run_msx.sh`).
13. ✅ **Portable picture payloads (#381)** — CPC, MSX2, and PCW distributions
   carry the same canonical GBPC v2 Mode-1 `.PIC` bytes. MSX2 and PCW translate
   pixels at the display boundary; Paint and XAOS also save the portable format.
14. ✅ **Portable icon-set payloads** — CPC, MSX2, and PCW distributions carry
   canonical Mode-1 `.IST` bytes. Non-CPC kernels transcode the selected set when
   loading it, and ICONED preserves the portable format on every target.
15. ✅ **Portable backdrop payloads (#388)** — all targets carry the same 64-byte
   canonical Mode-1 `.BDP` tiles. MSX2 and PCW convert the selected tile at load
   time while CPC draws the already-native bytes from its desktop app, preserving
   the resident kernel's stack guard.
16. ✅ **Per-screensaver configuration (#390)** — Settings has a generic
   same-stem `.MOD` launcher instead of embedded saver dialogs. STARFLD's module
   persists speed and star count; XMATRIX's module adds binary/Kana glyphs,
   speed, and a CPC/MSX Screen 7 color choice with palette restoration on exit.
   MOUNTAIN's module adds speed, peak-count, and hold-time controls; its MSX
   Screen 7 renderer uses an eight-band elevation palette.
17. ✅ **MSX2 TCP/IP UNAPI networking (#397)** — Browser and Telnet use the shared
   `gb_net_*` API through a discovered mapped-RAM or page-3 UNAPI implementation.
   The initial emulator target is openMSXnet; no network code is added to the
   resident kernel.

## Next

- **Paint** follow-ups — resizable canvas and scrolling for pictures bigger than the
  screen (Fullscreen already centers the canvas + tools).
- **Drawers/folders** and richer desktop arrangement.
- **More screensaver controls** — add same-stem configuration companions as
  individual savers gain useful parameters; Settings needs no corresponding
  source or resident-kernel change.
