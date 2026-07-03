#!/usr/bin/env bash
# tools/build_kernel_msx.sh - build the MSX2 target (#287): the GBMSX.COM
# kernel + the M1 app/asset set, staged into QA/MSX and packed into the
# bootable Nextor image QA/GBMSX.IMG.
#
# Kept separate from tools/build_kernel.sh (that script is CPC-DSK-entangled
# and wipes its own QA outputs); the shared pieces (apps via build_capp.sh,
# GBCFG via build_cfgmod.sh, the Python asset tools) are reused, with
# -DGB_MSX2 / --platform msx2 selecting the MSX encodings.
#
#   bash tools/build_kernel_msx.sh
#   MSX_SHOTS="20 30 45" tools/run_msx.sh      # then verify in openMSX
set -euo pipefail
cd "$(dirname "$0")/.."

RASM="${RASM:-rasm}"
command -v "$RASM" >/dev/null || { echo "ERROR: rasm not on PATH" >&2; exit 1; }
command -v sdcc >/dev/null || { echo "ERROR: sdcc not on PATH" >&2; exit 1; }

mkdir -p build/msx QA/MSX/GBENCH

# --- the C apps, compiled with the MSX geometry ------------------------------
APPDEFS="-DGB_MSX2" DATA_LOC=0x6D00 DOC=1 tools/build_capp.sh apps/desktop build/msx/DESKTOP.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x7600 DOC=1 tools/build_capp.sh apps/filemgr build/msx/FILEMGR.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x6BF0 DOC=1 tools/build_capp.sh apps/notepad build/msx/NOTEPAD.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x6F00 DIALOGS=1 tools/build_capp.sh apps/settings build/msx/SETTINGS.RAW
APPDEFS="-DGB_MSX2" DOC=1 tools/build_capp.sh apps/xaos build/msx/XAOS.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x62C0 DOC=1 tools/build_capp.sh apps/iconed build/msx/ICONED.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x5F20 DOCRO=1 tools/build_capp.sh apps/viewer build/msx/VIEWER.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x6300 DOC=1 tools/build_capp.sh apps/paint build/msx/PAINT.RAW
APPDEFS="-DGB_MSX2" DOC=1 tools/build_capp.sh apps/clock build/msx/CLOCK.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/saver build/msx/SQUARES.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/ant  build/msx/ANT.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/deco build/msx/DECO.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/xmatrix build/msx/XMATRIX.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/mountain build/msx/MOUNTAIN.RAW

# --- the shared config-parser module (platform-neutral C over low RAM) -----
tools/build_cfgmod.sh                            # -> build/GBCFG.RAW
tools/build_uimod.sh                             # -> build/GBUI.RAW (dialogs/menus)

# --- assets ------------------------------------------------------------------
python3 tools/genfont.py build/msx/DEFAULT.FNT           # 1bpp glyphs: shared format
python3 tools/packicons.py --platform msx2 build/msx/DEFAULT.IST \
    lib/icon_floppy.asm lib/icon_ide.asm lib/icon_clock.asm lib/icon_trash.asm \
    lib/icon_geobench.asm lib/icon_basic.asm lib/icon_binary.asm \
    lib/icon_picture.asm lib/icon_text.asm lib/icon_folder.asm \
    lib/icon_app.asm lib/icon_notepad.asm lib/icon_iconeditor.asm \
    lib/icon_font.asm \
    lib/icon_desktop.asm lib/icon_filemanager.asm \
    lib/icon_paint.asm lib/icon_fractal.asm lib/icon_sd.asm \
    lib/icon_viewer.asm \
    lib/icon_telnet.asm lib/icon_network.asm lib/icon_shell.asm \
    lib/icon_up.asm lib/icon_screensaver.asm
python3 tools/packicons.py --platform msx2 build/msx/PAINT.IST \
    assets/paint/pencil.asm assets/paint/square.asm assets/paint/circle.asm \
    assets/paint/fill.asm assets/paint/undo.asm
python3 tools/png2spr.py --platform msx2 assets/pointer.png build/msx/DEFAULT.SPR cursor

# --- the kernel + the .COM stub ---------------------------------------------
# RASM exits 0 even on assembly errors, so stale outputs would silently ship:
# remove them first and require fresh files after each pass.
rm -f build/msx/GBKERNM.RAW build/msx/GBMSX.COM
( cd build/msx && "$RASM" ../../kernel/gbkern.asm -DPLATFORM_MSX=1 -s -o gbkernm ${EXTRA_RASM:-} )
[ -s build/msx/GBKERNM.RAW ] || { echo "ERROR: GBKERNM.RAW not produced (rasm errors above)" >&2; exit 1; }
( cd build/msx && "$RASM" ../../kernel/msx_stub.asm )
[ -s build/msx/GBMSX.COM ] || { echo "ERROR: GBMSX.COM not produced (rasm errors above)" >&2; exit 1; }

# --- stage QA/MSX --------------------------------------------------------------
cp build/msx/GBMSX.COM QA/MSX/
printf 'GBMSX\r\n' > QA/MSX/AUTOEXEC.BAT
printf 'FONT=DEFAULT\r\nICONS=DEFAULT\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\nBACKDROP=SOLID\r\nWALLPAPER=NONE\r\nSAVER=SQUARES\r\nSAVERTIME=2\r\n' > QA/MSX/GEOBENCH.CFG
cp build/msx/DESKTOP.RAW  QA/MSX/GBENCH/DESKTOP.APP
cp build/msx/FILEMGR.RAW  QA/MSX/GBENCH/FILEMGR.APP
cp build/msx/NOTEPAD.RAW  QA/MSX/GBENCH/NOTEPAD.APP
cp build/msx/SETTINGS.RAW QA/MSX/GBENCH/SETTINGS.APP
cp build/msx/XAOS.RAW     QA/MSX/GBENCH/XAOS.APP
cp build/msx/ICONED.RAW   QA/MSX/GBENCH/ICONED.APP
cp build/msx/VIEWER.RAW   QA/MSX/GBENCH/VIEWER.APP
cp build/msx/PAINT.RAW    QA/MSX/GBENCH/PAINT.APP
cp build/msx/PAINT.IST    QA/MSX/GBENCH/PAINT.IST
cp build/msx/CLOCK.RAW    QA/MSX/GBENCH/CLOCK.APP
cp build/msx/SQUARES.RAW  QA/MSX/GBENCH/SQUARES.SAV
cp build/msx/ANT.RAW      QA/MSX/GBENCH/ANT.SAV
cp build/msx/DECO.RAW     QA/MSX/GBENCH/DECO.SAV
cp build/msx/XMATRIX.RAW  QA/MSX/GBENCH/XMATRIX.SAV
cp build/msx/MOUNTAIN.RAW QA/MSX/GBENCH/MOUNTAIN.SAV
cp assets/WELCOME.TXT     QA/MSX/WELCOME.TXT
python3 tools/pic_to_msx.py assets/pictures/PENGUIN.PIC QA/MSX/PENGUIN.PIC
cp build/GBCFG.RAW      QA/MSX/GBENCH/GBCFG.MOD
cp build/GBUI.RAW       QA/MSX/GBENCH/GBUI.MOD
cp build/msx/DEFAULT.FNT QA/MSX/GBENCH/
cp build/msx/DEFAULT.IST QA/MSX/GBENCH/
cp build/msx/DEFAULT.SPR QA/MSX/GBENCH/

# --- bootable Nextor image ------------------------------------------------------
bash tools/build_msx_img.sh QA/MSX QA/GBMSX.IMG

echo "MSX2 target built: QA/MSX (staged) + QA/GBMSX.IMG (bootable Nextor image)"
