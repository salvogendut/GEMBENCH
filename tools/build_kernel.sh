#!/usr/bin/env bash
# Build the GEOBENCH banked-kernel skeleton + the HELLO app (Phase 1 proof).
#
# Apps are separate binaries; the app is built FIRST because the kernel incbins
# build/HELLO.RAW. Output: build/gbkern.dsk (GBKERN.BIN, with HELLO embedded).
#   tools/build_kernel.sh
#   1984 --memory=128 --disk-a=build/gbkern.dsk --autostart=GBKERN
set -euo pipefail

cd "$(dirname "$0")/.."          # repo root
RASM="${RASM:-rasm}"

# Every card gets its own kernel + QA subdir (below). STORAGE only picks which
# variant is left in build/ for the dev harness (--disk-a / deploy_ide.sh):
# "ide" (default) or "albireo". The backends are mutually exclusive per build, so
# the IDE FAT32 core stays off an Albireo kernel (#104).
STORAGE_FLAG=""
if [ "${STORAGE:-ide}" = "albireo" ]; then
    STORAGE_FLAG="-DSTORAGE_ALBIREO=1"
fi

mkdir -p build
rm -f build/gbkern.dsk                        # save-to-DSK appends; start clean

python3 tools/genfont.py build/DEFAULT.FNT   # 6x8 font -> PAGE_DATA
python3 tools/packfont.py build/CLASSIC.FNT lib/font.asm  # 8x8 ROM font (FONT=CLASSIC)
python3 tools/packicons.py build/DEFAULT.IST \
    lib/icon_floppy.asm lib/icon_ide.asm lib/icon_clock.asm lib/icon_trash.asm \
    lib/icon_geobench.asm lib/icon_basic.asm lib/icon_binary.asm \
    lib/icon_picture.asm lib/icon_text.asm lib/icon_folder.asm \
    lib/icon_app.asm lib/icon_notepad.asm lib/icon_iconeditor.asm \
    lib/icon_font.asm lib/icon_iconset.asm \
    lib/icon_desktop.asm lib/icon_filemanager.asm \
    lib/icon_paint.asm lib/icon_fractal.asm lib/icon_sd.asm \
    lib/icon_viewer.asm \
    # slots: 9=folder 10=.APP 11=NOTEPAD 12=ICONED 13=.FNT 14=.IST 15=DESKTOP 16=FILEMGR
    # 17=PAINT 18=FRACTAL 19=SD (Albireo Disk C, #104) 20=VIEWER
python3 tools/packicons.py build/PAINT.IST \
    assets/paint/pencil.asm assets/paint/square.asm assets/paint/circle.asm \
    assets/paint/fill.asm assets/paint/undo.asm   # PAINT toolchest set (24x24), ICONED-editable (#114)
tools/build_capp.sh apps/desktop build/DESKTOP.RAW # DESKTOP (C/SDCC) -> build/DESKTOP.RAW
tools/build_capp.sh apps/filemgr build/FILEMGR.RAW # FILEMGR (C/SDCC) -> build/FILEMGR.RAW
tools/build_capp.sh apps/viewer build/VIEWER.RAW   # VIEWER (C/SDCC) -> build/VIEWER.RAW
DATA_LOC=0x6800 DIALOGS=1 PROMPT=1 tools/build_capp.sh apps/notepad build/NOTEPAD.RAW # NOTEPAD:
                                   # code-heavy, so a higher data-loc gives it ~1.9K code room
                                   # (#97); shared File popup + name prompt (gbdlg/gbprompt, #114)
DATA_LOC=0x5C00 DIALOGS=1 tools/build_capp.sh apps/iconed build/ICONED.RAW # ICONED: lower
                                   # data-loc so its 7KB icon-set buffer (BUFSZ) fits below
                                   # #8000 (#110); DIALOGS=1 for the shared Load/Save popup (#114)
tools/build_capp.sh apps/clock  build/CLOCK.RAW    # CLOCK  (C/SDCC) -> build/CLOCK.RAW
DIALOGS=1 PROMPT=1 tools/build_capp.sh apps/paint build/PAINT.RAW # PAINT: shared list popup
                                   # + name prompt (gbdlg.c + gbprompt.c) for its File menu (#114)
tools/build_cfgmod.sh build/GBCFG.RAW              # config-parser C kernel module -> build/GBCFG.RAW
tools/build_fatmod.sh                              # FAT16/IDE write module -> build/GBFAT.RAW
# QA/<CARD>/: one distribution per storage card (#104). The apps/modules/assets
# above are shared; only the kernel differs, so we assemble each variant and stage
# it into its own subdir with BOTH formats: the loose files to copy onto that
# card's FAT drive, and a bootable floppy image (GEOBENCH.DSK) for a CPC that
# boots from disc. Add a card here (e.g. M4 "-DSTORAGE_M4=1") when its backend lands.
build_variant() {                                # $1 = subdir name, $2 = rasm -D flag
    rm -f build/gbkern.dsk                       # save-to-DSK appends; start clean
    "$RASM" kernel/gbkern.asm -eo $2             # incbins apps + font + icons -> .dsk + RAW
    tools/stage_dist.sh "QA/$1"                  # loose files for the card's FAT drive
    cp build/gbkern.dsk "QA/$1/GEOBENCH.DSK"     # bootable floppy image
    echo "  QA/$1: $(ls "QA/$1" | wc -l) files (incl. GEOBENCH.DSK floppy image)"
}
rm -rf QA
echo "Staging per-storage distributions -> QA/"
build_variant IDE     ""
build_variant ALBIREO "-DSTORAGE_ALBIREO=1"

# Leave build/ as the STORAGE-selected variant (default IDE) so the --disk-a test
# harness and deploy_ide.sh see a predictable build/gbkern.dsk + build/GBKERN.RAW.
rm -f build/gbkern.dsk
"$RASM" kernel/gbkern.asm -eo $STORAGE_FLAG >/dev/null
echo "Built QA/IDE + QA/ALBIREO; build/ = ${STORAGE:-ide} variant for testing"
