#!/usr/bin/env bash
# Build one two-bank editor for both receivers; staging belongs to each target.
set -euo pipefail
cd "$(dirname "$0")/.."
SECONDARY_DATA_LOC=0x5E00 bash tools/build_usecondary.sh apps/unotepad/secondary build/universal/NOTEPAD.BIN
UNIVERSAL_COMPUTE=1 UNIVERSAL_IX=1 APP_SECONDARY=build/universal/NOTEPAD.BIN \
UNIVERSAL_FS=1 UNIVERSAL_FS_IDENTITY=1 UNIVERSAL_DOCIO=1 UNIVERSAL_FILEPICK=1 UNIVERSAL_SCRAP=1 \
UNIVERSAL_MENU=1 UNIVERSAL_MENU_BORROWED=1 UNIVERSAL_MINIMAL=1 \
UNIVERSAL_WINDOW_KIND=1 APP_ICON=apps/notepad/icon.asm \
DATA_LOC="${DATA_LOC:-0x7870}" bash tools/build_uapp.sh apps/unotepad build/universal/NOTEPAD.APP
cp build/universal-obj/unotepad/app.noi build/universal/NOTEPAD.noi
