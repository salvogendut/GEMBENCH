# Unified Notepad integration — not a delivery build

This binds the editor from `../notepad` to portable managed windows, typed
clipboard, the owned file chooser and bounded document I/O. The native source
and normal distribution targets are unchanged.

**The complete primary-only link does not fit the ABI memory limit.** The
standard builder rejects it before emitting an APP. Do not stage the overlapping
IHX/raw linker output or relax the layout check. Owned data/secondary-code
services must be brought forward before this integration can run safely.

Host policy tests (mocked public services, not emulator acceptance):

```sh
python3 -m unittest discover -s tests -p test_unotepad.py -v
```

Full size-audit command, using the project SDCC toolchain in an isolated worktree:

```sh
UNIVERSAL_FS=1 UNIVERSAL_SCRAP=1 UNIVERSAL_DOCIO=1 \
UNIVERSAL_FILEPICK=1 UNIVERSAL_MENU=1 UNIVERSAL_WINDOW_KIND=1 \
APP_ICON=apps/notepad/icon.asm DATA_LOC=0x6000 \
APP_CFLAGS="--max-allocs-per-node 100000" \
bash tools/build_uapp.sh apps/unotepad build/universal/NOTEPAD.APP
```

`DATA_LOC` here is a diagnostic placement, not a usable memory map. No alternative
placement fits the combined allocation. The manifest's one-page request describes
this rejected primary-only candidate, not the eventual paged application.

Remaining work includes the paged integration, portable shell/document handoff
and configuration reload, CPC pathname parity and actual cross-target editor,
storage-failure, repaint, input and cleanup qualification. See
[the audit](../../docs/UNIFIED-NOTEPAD.md) for evidence and exact boundaries.
