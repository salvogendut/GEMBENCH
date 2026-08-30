# tools/

Host-side (PC) tooling for building GEOBENCH and preparing assets. None of this
runs on the CPC — it produces the binaries and data files that do. The kernel is
assembled with **RASM**; the C apps with **SDCC**. Most builds run inside the
project's distrobox (which carries `rasm`, `sdcc`, `mtools`, `dosfstools`, ...).

## Build orchestration

- **`build_kernel.sh`** — the one-shot build. Assembles the shipped **`GBALB`** (Albireo)
  and **`GBM4`** (M4) kernels, packs the apps, and stages the distribution into `QA/`:
  the loose card files (`QA/CPC/CARD/`), the Main and Companion floppies under
  `QA/CPC/Floppies/`, the gallery and Disk Utility `EXTRAS.DSK`, and the shared card image
  (`QA/CPC/GEOBENCH.IMG`).
  The IDE backend is archived (frozen, not built — see `docs/ARCHIVED.md`);
  rebuild it for recovery with `STORAGE=ide`. `STORAGE=m4` leaves an M4 dev-harness
  kernel in `build/`. `FAT16=1` and `EXTRA_RASM=...` tune the variant
  (e.g. `EXTRA_RASM="-DGB_ROM_REQ=1"` for the ROM-offload kernel).
- **`build_kernel_pcw.sh`** — builds the standalone PCW boot disk, companion
  disk, and 720K `EXTRAS.DSK`. The extras build stages the PCW payloads from
  sibling GB-PAINT and GB-BASIC checkouts.
- **`build_kernel_msx.sh`** — builds the `GBMSX.COM` video-mode selector,
  `GBMSX6.COM`, `GBMSX7.COM`, the MSX2 app/module payload, and the bootable
  Nextor `QA/MSX/GBMSX.IMG`, plus the two 720K images under `QA/MSX/Floppies/`.
  Its Paint application and tool artwork are maintained in-tree under
  `apps/paint/` and `assets/paint/`.
  The dependency fetcher supplies a local openMSXnet
  `UNAPINET.COM`, which is staged before `GBMSX.COM`; `MSX_UNAPI_TSR` overrides
  it, and an explicitly empty value omits it. The standalone staged TSR and
  dependency bundle remain untracked; the released system floppy embeds the
  MIT-licensed TSR and notice, while the rest of `QA/MSX/CARD/` is committed.
- **`build_msx_floppy.sh`** — builds `GEOBENCH.DSK` with the full system and
  `EXTRAS.DSK` with the picture gallery. The disks use standard 720K FAT12
  geometry and, as shipped with `NEXTOR.SYS`, require a Nextor kernel ROM
  supplied by the MSX. The system disk starts `UNAPINET.COM` before GEOBENCH so
  its network apps can use the matching openMSXnet emulator extension.
- **`run_msx.sh`** — launches the MSX2 image in native or Flatpak openMSX.
  It adds openMSXnet's `unapinet` extension by default when using its custom
  emulator build and automatically selects a bundle in
  `QA/MSXDEPS/openmsxnet/`. `OPENMSXNET_HOME` overrides that location;
  missing host libraries are supplied through `my-distrobox`
  (`MSX_DISTROBOX` overrides the name). `MSX_UNAPI=0` disables the extension.
  Passing a `.DSK` mounts it in drive A; `MSX_DISKB` optionally mounts a second
  floppy on machine definitions that expose drive B.
- **`m4detect.asm`** — a tiny BASIC-callable detector that asks the firmware
  (`KL_FIND_COMMAND`) whether an M4 ROM RSX is installed. The staged `GB.BAS` loads
  it as `M4DETECT.BIN` and uses its result to pick `GBM4` vs `GBALB`.
- **`build_rom.sh`** — builds optional legacy 16K upper-ROM experiments that
  offload low-level drivers and carry the cold-boot banner:
  `rom/GBALB.ROM` (Albireo) and `rom/GEOBENCH.ROM` (the archived IDE backend).
  Neither is staged in normal release media. The script bakes the git commit into the banner
  (`rom/gitcommit.inc`, generated).
- **`build_m4netmod.sh [out.RAW]`** — builds `GBNETM4.MOD`, the M4ROM TCP command
  backend for the shared `gb_net_*` API.
- **`build_m4savemod.sh`** — builds `M4SAVE.MOD`, the M4ROM save/delete/free-space
  and chunked-read backend loaded on demand by the M4 kernel.
- **`stage_dist.sh <out>`** — stages the shared Albireo/M4 card distribution
  (`GB.BAS`, `M4DETECT.BIN`, `GBALB.BIN`, `GBM4.BIN`, and the `GBENCH/` payload)
  into a directory.
- **`build_capp.sh <app_dir> <out.RAW>`** — builds a single C app against `libgb`,
  for iterating on one app. App/module helper scripts write `*.stamp` metadata
  beside their outputs so a repeated full build can reuse unchanged binaries and
  skip recompiling untouched apps/modules. With `NET=1`, CPC links the paged
  network stub and `APPDEFS=-DGB_MSX2` selects the TCP/IP UNAPI backend.
  `WIDGETS=1` links reusable buttons/fields, `SIZEPROMPT=1` links the compact
  shared width-by-height dialog stub, and `SCROLL=1` links the vertical
  scrollbar unit. `TOGGLE=1`, `STEPPER=1`, `SELECTOR=1`, and `SLIDER=1`
  independently link the corresponding settings controls, so tight apps pay only
  for controls used. `FORM=1` adds form rows and modal lifecycle and requires
  `WIDGETS=1`; `FORM_SELECT=1` adds selector rows and requires both `FORM=1` and
  `SELECTOR=1`. `FORM_MODAL_ONLY=1` omits row/action helpers for an app that uses
  only the modal lifecycle. `GBR_FORMS=1` adds resource field rendering, live
  text bindings, and focus traversal; `GBR_EMBEDDED=1` selects the compact
  accessor path for a build-verified embedded resource. `GBWIN_DRAG_ONLY=1`
  keeps window dragging but omits the resize
  grip and resize-drag helpers for apps that do not use them.
  `WINDOW_KIND=1` links the MSX2-only explicit v1 registration wrapper; it
  requires `APPDEFS=-DGB_MSX2` and is omitted from legacy-only applications.
  `GB_EVENTS=1` links the bounded `gbevent` subscription adapter; callers own
  its state and it adds no resident kernel or low-RAM allocation.
  `GB_REGIONS=1` links the four-rectangle visible-region iterator; callers own
  its 40-byte state and capacity overflow restores the legacy damage clip. The
  release build currently enables it only for the MSX2 Desktop.
  `GB_SCRAP=1` links the bounded MSX2 typed-scrap API over the unchanged
  510-byte resident clipboard. `GB_SCRAP_TEXT_ONLY=1` selects the 100-byte
  set/type adapter for clients that keep using raw length/get after checking
  text or legacy-untyped input; it requires `GB_SCRAP=1`.
  `GB_SHELL_TARGET=1` links MSX2 service registration; `GB_SHELL_CLIENT=1`
  links discovery, synchronous delivery, and the combined request helper. Both
  profiles require `APPDEFS=-DGB_MSX2` and add no application-side queue.
  `GB_DEFER=1` links the 36-byte MSX2 deferred-message binding, exposes
  `gbdefer.h`, and defines `GB_DEFER_MESSAGES`; the resident kernel owns the
  fixed eight-record FIFO.
  `SOUND=1` links the target-specific PSG/beeper primitives into that app only;
  it does not add a resident kernel service.
  `REPAINTTOP=1` links the three-byte `gb_repaint_top()` binding for an opaque
  top window's initial publication; exposure repairs must keep using
  `gb_restore_parent()`.
  `APP_ICON=path/icon.asm` embeds a canonical 32x32 icon in the
  optional `GBAP` executable preamble without changing the kernel launch ABI;
  `APP_ICON16=path/icon16.asm` adds an explicit native Screen-7 variant. For
  app-owned `icon.asm` sources, an adjacent `icon16.asm` is detected
  automatically by MSX builds only.
- **`test_formref_openmsx.sh`** — builds a disposable Nextor image and drives the
  resource-backed MSX2 FormRef through pointer launch, keyboard focus,
  checkbox/radio mutation, default Save, and trace assertions under openMSX.
  `MSX_HEADLESS=1` skips screenshots while retaining the complete logic trace.
- **`test_window_kinds_openmsx.sh`** — drives the real MSX2 File Manager through
  pointer selection from the generated View popup, `I`/`L`/`F` shortcut and
  checked/radio transitions, then kernel-owned maximise/restore, move, and
  resize gestures. It verifies the menu state and append-only geometry messages
  and captures the final Screen 7 window. Headless mode retains all assertions.
- **`test_multi_event_openmsx.sh`** — launches the built MSX2 Clock from a
  disposable Nextor image and asserts combined timer, keyboard, pointer, and
  window delivery through real matrix input. `MSX_HEADLESS=1` keeps the trace
  assertions without a display.
- **`test_typed_scrap_openmsx.sh`** — launches two byte-identical Notepads from
  a disposable network-free Nextor image, copies typed text through the real
  Edit menu, proves bitmap mismatch is atomic, and then accepts the text paste.
  It does not require the optional openMSXnet `unapinet` extension.
- **`test_shell_service_openmsx.sh`** — opens two disposable text documents
  through the real File Manager path and proves the second request raises and
  reuses the original Notepad. It asserts registration/discovery/send counts,
  document and 8.3-name replacement, stable window count, cleared dispatch
  guard, caller-bank recovery, and target-entry stack delta without requiring
  the optional openMSXnet extension.
- **`test_m1_architecture_openmsx.sh`** — exercises the versioned MSX2
  architecture APIs, including mapper ownership, application records, a
  transient second window, the deferred FIFO/cancellation/delivery contract,
  filesystem contexts, stale generation rejection, and complete cleanup. `make
  gembench-m4-openmsx` runs this diagnostic and the two-mode loader smoke.
- **`test_m3_boot_modes_openmsx.sh`** — boots disposable, network-free Screen 6
  and Screen 7 images and requires a live Desktop, sysinfo v4, the retained
  mapper pool, and an empty deferred queue. It guards the fixed 16,128-byte
  child-COM loader window; `make gembench-m3-boot-openmsx` runs it alone.
- **`build_fsctxmod.sh` / `run_gbfsctx_tests.sh`** — build the paged MSX2
  filesystem-context provider and verify its four-context, 512-byte,
  append-only public contract. The live architecture test additionally proves
  independent File Manager enumeration, offset isolation, and owner teardown.
- **`test_m2_paint_openmsx.sh`** — opens an actual `.PIC` in the in-tree Paint,
  observes its Toolchest, Preview, and Canvas under one application/code page,
  drags and continues using all three windows, verifies application geometry and
  vacated-screen cleanup after each compositor pass, closes the picture windows
  independently, and proves final window, owner, and mapper-page counts return
  to baseline.
- **`gen_desk_accessories.py`** — validates the fixed-capacity build-time Desk
  catalog and generates stable IDs, labels, and padded APP names in
  `gbdesk_catalog.h`; `--check` detects stale generated metadata.
- **`test_desk_accessories_openmsx.sh`** — selects Clock and Calculator through
  the generated Desk popup, proves deferred exact activation never duplicates
  either window, closes Clock through its real gadget, observes one mapper page
  return, and relaunches it. The disposable image does not require openMSXnet.
- **`gbrc.py` / `gbrverify.py`** — compile deterministic GBR v1 resources and
  strictly verify binary resources. `gbrc.py --c-header` can also emit a C blob,
  section/count constants, and source-only object IDs for embedded resources;
  `--menu-header` emits bounded code-only `GBRM` menu metadata without changing
  the canonical `.GBR` bytes.
- **`build_savercfg.sh <app_dir> <out.RAW>`** — builds
  `apps/<saver>/config.c` as an 8 KB-bounded paged configuration companion at
  `#6000`. Package the result with the same stem as its saver (`XMATRIX.MOD`
  beside `XMATRIX.SAV`); Settings launches it without linking its controls.
  `make formref` builds the small three-platform reference app and its Daruma
  embedded-icon example.
  `make sndtest` builds the three app-linked sound diagnostics.
- **`rebuild_app.sh <name>`** — performs a focused cross-platform rebuild and
  distribution refresh for a registered application. Use
  `make app APP=mahjong` after changing Mahjongg code or its embedded icon; it
  skips kernels, unrelated applications, pictures, and external GB-BASIC/GB-PAINT
  builds while refreshing the companion disks and existing FAT images.
- **`package_cpc_companion.sh` / `package_pcw_companion.sh`** — repack only the
  corresponding companion disk from existing application payloads. Full and
  focused builds share these helpers so their file lists cannot drift.
- **`embed_app_icon.py`** — validates canonical four-/sixteen-colour sources and
  injects/checks the versioned executable preamble used by icon-bearing `.APP`
  files. See `docs/APP_ICON_FORMAT.md`.
- **`build_appickmod.sh`** — builds `GBAPICK.MOD`, ICONED's paged Open dialog
  that filters out `.APP` files without an embedded icon header.
- **`iconedit.py`** — edits `.IST`, `.SPR`, embedded `.APP` icons, and canonical
  four-/sixteen-colour RASM icon sources. Open an `APP_ICON=`/`APP_ICON16=`
  source and save it directly to make an icon change survive rebuilds;
  executable bytes are preserved when editing an `.APP` binary. Its compact
  toolchest provides pen/erase, straight lines, outline and filled shapes,
  flood fill, spray paint, undo, and rectangular selection-aware copy/paste.
- **`check_abi_table.py`** — verifies the `kernel/gbkern.asm` jump-table comments
  match the exported `lib/gbapp.inc` slot addresses through `kernel/api_table.inc`.
- **`check_gembench_abi.py`** — checks the frozen GEMBENCH-1 JSON manifest
  against GBR constants, C/assembly window values, the Z80 descriptor layouts,
  and the explicit legacy/v1 registration selectors.
- **`check_lowram_map.py`** — validates the fixed low-RAM ownership map in
  `kernel/lowram.tsv` for accidental range overlaps.
- **`build_scheduler.sh {cpc|msx|pcw}`** — assembles the release, app-carried
  preemptive scheduler into a bounded 512-byte raw payload. `build_capp.sh`
  embeds it in the root desktop when `TASK_ROOT=1`; the resulting runtime is
  installed in fixed RAM and requires no GEOBENCH or M4 ROM. See
  `docs/PREEMPTIVE_MULTITASKING.md`. Explicit `*-cooperative` Make targets omit
  it for regression testing.
- **`check_app_layout.py` / `test_app_layout.py`** — enforce the normal app
  image limits and the `#7F00-#7FFF` task stack-snapshot reserve.
- **`deploy_ide.sh`** — *(archived)* copy the staged distribution onto a real/emulated IDE
  image (for the frozen IDE backend).

## Card / disk images

- **`build_card_img.sh [CARD] [IMG]`** — builds a partitioned **FAT16 card image**
  (`QA/CPC/GEOBENCH.IMG` by default) from the staged `QA/CPC/CARD/` for Albireo and M4
  image mode. Called by `build_kernel.sh`.
- **`mkcpcmedia.py OUT.dsk --add FILE ...`** — builds the extended 80-track,
  single-sided AMSDOS DATA image used for the CPC picture gallery.
- **`mkpcwdsk.py`** — builds bootable or data PCW CF2/CF2DD images, including
  `QA/PCW/Floppies/EXTRAS.DSK`.
- **`build_ide_img.sh`** — *(archived)* older IDE-only image helper.

## Paged kernel modules

Build the on-demand kernel modules (loaded into a bank and `call`ed): config
(`build_cfgmod.sh`), FAT write (`build_fatmod.sh`), floppy write
(`build_floppymod.sh`), M4 save (`build_m4savemod.sh`), dialogs/UI
(`build_uimod.sh`, which also embeds the root `VERSION` and current Git commit
for System > About GEOBENCH), and networking (`build_netmod.sh`, `build_m4netmod.sh`);
`build_kmod.sh` is the shared helper used by the smaller asm/C module scripts.

## Asset converters

- **`png2cpc.py`** — a 32×32 PNG → a CPC Mode-1 icon asm source (for `.IST` sets).
- **`png2spr.py`** — a PNG → a `.SPR` cursor sprite (2 pre-shifted phases, mask+data
  **interleaved** per byte to match the kernel compositor — see `lib/cursor.asm`).
- **`packicons.py`** — pack icon asm sources into a `.IST` set (in slot order); builds
  `build/DEFAULT.IST` fresh each build. The `.IST` files are stored in the canonical
  CPC Mode-1 payload on disk; MSX/PCW decode them at load time with `icon_convert`
  in the kernel.
- **`ist_append.py`** — append icon asm bitmap(s) to an existing (hand-tuned) `.IST`
  set, bumping the count + shifting offsets; used to add a new slot to the tracked
  `assets/iconsets/*.IST` sets that `packicons.py` doesn't regenerate.
- **`ist_replace_slot.py`** — replace one positional icon in a tracked `.IST` set
  from an icon asm source while preserving the set's slot count and layout.
- **`titlebaredit.py`** — edit a canonical four-pen `.TBR` repeated 16x14 title
  background and an independently saved `.GDT` close/maximize pair. Preview the
  combined result on sample windows. Its toolchest supplies pencil, line,
  outlined/filled shapes, bucket fill, spray paint, undo, and one-pixel shift
  arrows for the active canvas. `make titlebar-editor` opens the shipped
  `ORIGINAL.TBR` and `ORIGINAL.GDT` defaults; legacy 106-byte themes can be split.
- **`build_titlebarmod.sh`** — validate/stage all `.TBR` and `.GDT` assets and
  assemble the paged renderer with a composed embedded safe fallback.
- **`packfont.py` / `genfont.py`** — pack an 8×8 asm font into a `.FNT`, or generate
  the 6×8 `DEFAULT.FNT` procedurally.
- **`picconv.py`** — convert an image to portable four-colour GBPC v2 (the
  default) or an MSX Screen 7 sixteen-colour `.PIC` (`--colors 16`), using
  either the GUI or CLI. Width and height can be entered independently; leave
  either one blank to preserve the source aspect ratio.
- **`gen_pic_luts.py`** — generate and verify the reversible MSX2/PCW picture
  display lookup tables used by the kernels.
- **`png2backdrop.py` / `patternedit.py`** — create or edit portable canonical
  Mode-1 `.BDP` backdrop tiles. CPC uses them directly, MSX2/PCW decode them when
  loaded, and `bdp_to_msx.py` remains only for legacy artifacts.
- **`check_pic_distribution.py`** — verify canonical `.PIC`/`.BDP` byte identity
  across staged folders and CPC/PCW disks.
- **`iconedit.py`** — a host-side tkinter editor for canonical icon `.asm`
  sources, `.IST` icon sets, `.SPR` cursors, and embedded `.APP` icons. The
  keyboard arrow keys shift the current bitmap one pixel for easy alignment;
  pixels shifted beyond an edge are clipped. Drag with Select to copy or paste
  a sub-region; with no selection, Copy/Paste continues to operate on the whole
  icon for cross-window icon-set workflows.
- **`amsdos_header.py`** — prepend a 128-byte AMSDOS header to a RAW binary.

## Conventions

- Output binaries under `build/` are local artifacts. The staged `QA/`
  distribution is committed, including the `.dsk` media, so every shipped change
  should rebuild those images before commit.
- Any text/data file destined for the CPC must use **CR+LF** line endings.
