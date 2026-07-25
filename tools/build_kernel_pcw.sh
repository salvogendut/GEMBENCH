#!/usr/bin/env bash
# tools/build_kernel_pcw.sh - build the Amstrad PCW target (#331): the
# GBKERNP.RAW kernel on its own boot sector, the core app/asset set, staged
# into QA/PCW and packed into GEOBENCH.DSK (bootable CF2), COMPANION.DSK,
# and EXTRAS.DSK (CF2DD picture gallery plus standalone applications).
#
# The PCW boots standalone (no CP/M): kernel/pcwboot.asm loads the kernel
# from the disc's reserved tracks; system files live in the disc's CP/M 2.2
# filesystem (read by lib/pcw/fs.asm, written at build time by mkpcwdsk.py).
#
# GBPC v2 pictures, icon sets, and backdrop tiles stay canonical; the kernel
# translates them at runtime. Save-block-format blobs such as the splash still
# need the final CGA2 hardware-pen permutation at build time.
#
#   bash tools/build_kernel_pcw.sh
#   SDL_VIDEODRIVER=dummy ~/Dev/1985/1985 --config debug/1985-pcw.conf \
#       --disk-a QA/PCW/GEOBENCH.DSK --screenshot-at 600:/tmp/pcw.ppm
set -euo pipefail
cd "$(dirname "$0")/.."

RASM="${RASM:-rasm}"
GB_PAINT_DIR="${GB_PAINT_DIR:-../GB-PAINT}"
GB_BASIC_DIR="${GB_BASIC_DIR:-../GB-BASIC}"
command -v "$RASM" >/dev/null || { echo "ERROR: rasm not on PATH" >&2; exit 1; }
command -v sdcc >/dev/null || { echo "ERROR: sdcc not on PATH" >&2; exit 1; }
[ -f "$GB_PAINT_DIR/Makefile" ] || {
    echo "ERROR: GB-PAINT checkout not found at $GB_PAINT_DIR" >&2
    echo "Set GB_PAINT_DIR=/path/to/GB-PAINT or clone it next to geobench." >&2
    exit 1
}
[ -f "$GB_BASIC_DIR/Makefile" ] || {
    echo "ERROR: GB-BASIC checkout not found at $GB_BASIC_DIR" >&2
    echo "Set GB_BASIC_DIR=/path/to/GB-BASIC or clone it next to geobench." >&2
    exit 1
}

mkdir -p build/pcw QA/PCW

# --- the C apps, compiled with the PCW geometry (same DATA_LOCs as CPC/MSX) --
python3 tools/png2mahjong.py assets/katakana.png assets/hiragana.png apps/mahjong/kana.h
APPDEFS="-DGB_PCW" DATA_LOC=0x6D80 DOC=1 tools/build_capp.sh apps/desktop build/pcw/DESKTOP.RAW
APPDEFS="-DGB_PCW" APP_CFLAGS="--max-allocs-per-node 5000" DATA_LOC=0x778A DOC=1 SCROLL=1 tools/build_capp.sh apps/filemgr build/pcw/FILEMGR.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x6BF0 DOC=1 tools/build_capp.sh apps/notepad build/pcw/NOTEPAD.RAW
APPDEFS="-DGB_PCW" APP_CFLAGS=--opt-code-size DATA_LOC=0x7C40 DIALOGS=1 STEPPER=1 SELECTOR=1 tools/build_capp.sh apps/settings build/pcw/SETTINGS.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x68C0 DOCRO=1 tools/build_capp.sh apps/viewer build/pcw/VIEWER.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x6500 DOC=1 WIDGETS=1 STEPPER=1 tools/build_capp.sh apps/clock build/pcw/CLOCK.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x6400 DOC=1 WIDGETS=1 tools/build_capp.sh apps/xaos build/pcw/XAOS.RAW
APPDEFS="-DGB_PCW" APP_CFLAGS="--max-allocs-per-node 100000" DATA_LOC=0x6300 DOC=1 WIDGETS=1 tools/build_capp.sh apps/iconed build/pcw/ICONED.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x7380 DOC=1 tools/build_capp.sh apps/telnet build/pcw/TELNET.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x7400 tools/build_capp.sh apps/nettest build/pcw/NETTEST.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x7940 DIALOGS=1 WIDGETS=1 tools/build_capp.sh apps/wget build/pcw/WGET.RAW
GBWIN=0 GBLIB_SRC=lib/gb/gblib_browser.s APP_CFLAGS="--max-allocs-per-node 100000" LOAD_LIMIT=0x7F80 APPDEFS="-DGB_PCW" DATA_LOC=0x7FA4 tools/build_capp.sh apps/browser build/pcw/BROWSER.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x6200 tools/build_capp.sh apps/brsave build/pcw/BRSAVE.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x7400 tools/build_capp.sh apps/timesync build/pcw/TIMESYNC.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x6D00 SCROLL=1 tools/build_capp.sh apps/shell build/pcw/SHELL.RAW
APPDEFS="-DGB_PCW" DATA_LOC=0x7000 DIALOGS=1 tools/build_capp.sh apps/mahjong build/pcw/MAHJONG.RAW
# savers: the PORTABLE (pure gb_* API) subset - the direct-#C000 ones need a
# PCW plot path first (follow-up)
APPDEFS="-DGB_PCW" tools/build_capp.sh apps/saver build/pcw/SQUARES.RAW
APPDEFS="-DGB_PCW" tools/build_capp.sh apps/ant  build/pcw/ANT.RAW
APPDEFS="-DGB_PCW" tools/build_capp.sh apps/deco build/pcw/DECO.RAW
APPDEFS="-DGB_PCW" tools/build_capp.sh apps/xmatrix build/pcw/XMATRIX.RAW

# --- shared paged C modules (platform-neutral, low-RAM marshalled) -----------
tools/build_cfgmod.sh                            # -> build/GBCFG.RAW
tools/build_uimod.sh                             # -> build/GBUI.RAW
tools/build_webmod.sh                            # -> build/GBWEB.RAW
tools/build_imgmod.sh                            # -> build/GBIMG.RAW

# --- portable icons/pictures; target-native fonts, pointer and splash ---------
python3 tools/genfont.py build/pcw/DEFAULT.FNT
python3 tools/packfont.py build/pcw/CLASSIC.FNT lib/font.asm   # 8x8 (FONT=CLASSIC)
python3 tools/packicons.py build/pcw/DEFAULT.IST \
    lib/icon_floppy.asm lib/icon_flowchart.asm lib/icon_clock.asm lib/icon_trash.asm \
    lib/icon_geobench.asm lib/icon_basic.asm lib/icon_binary.asm \
    lib/icon_picture.asm lib/icon_text.asm lib/icon_folder.asm \
    lib/icon_app.asm lib/icon_notepad.asm lib/icon_iconeditor.asm \
    lib/icon_font.asm \
    lib/icon_desktop.asm lib/icon_filemanager.asm \
    lib/icon_paint.asm lib/icon_browser.asm lib/icon_sd.asm \
    lib/icon_viewer.asm \
    lib/icon_telnet.asm lib/icon_mahjong.asm lib/icon_shell.asm \
    lib/icon_up.asm lib/icon_screensaver.asm
cp assets/iconsets/REFINED.IST build/pcw/REFINED.IST

# the pointer: interleaved software-cursor .SPR in CGA2 hardware space
"$RASM" kernel/modules/picedit_low.asm -DPLATFORM_PCW=1 >/dev/null
python3 tools/png2spr.py --platform pcw assets/pointer.png build/pcw/DEFAULT.SPR cursor 12x16
cat build/pcw/PICEDITL.RAW >> build/pcw/DEFAULT.SPR

# bootsplash: Screen-6 transcode, then the CGA2 hardware-pen permute
# (boot_splash blits it with restore_block, which writes raw bytes)
BUILD_COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
python3 tools/make_bootsplash.py assets/SPLASH.png build/pcw/SPLASH_BUILD.png "$BUILD_COMMIT" GEOBENCH
python3 tools/png2cpc.py --platform msx2 build/pcw/SPLASH_BUILD.png build/pcw/SPLASH.BIN splash 96x184
python3 - build/pcw/SPLASH.BIN build/pcw/SPLASH.MOD <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
open(sys.argv[2], 'wb').write(bytes(((b & 0x55) << 1) | (((b ^ 0xFF) & 0xAA) >> 1) for b in d))
PY
cp assets/pictures/LOGO.PIC build/pcw/LOGO.PIC

# --- the kernel + the boot sector ---------------------------------------------
rm -f build/pcw/GBKERNP.RAW build/pcwboot.bin
( cd build/pcw && "$RASM" ../../kernel/gbkern.asm -DPLATFORM_PCW=1 -s -o gbkernp ${EXTRA_RASM:-} )
[ -s build/pcw/GBKERNP.RAW ] || { echo "ERROR: GBKERNP.RAW not produced (rasm errors above)" >&2; exit 1; }
"$RASM" kernel/pcwboot.asm
[ -s build/pcwboot.bin ] || { echo "ERROR: pcwboot.bin not produced" >&2; exit 1; }

# --- the bootable disc -----------------------------------------------------------
printf 'FONT=DEFAULT\r\nICONS=REFINED\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\nBACKDROP=SOLID\r\nWALLPAPER=LOGO\r\nSAVER=SQUARES\r\nSAVERTIME=2\r\nSTARFLD_SPEED=4\r\nSTARFLD_STARS=64\r\nTIMESYNC=true\r\nTIMEZONE=+2\r\nPROXY=\r\n' > build/pcw/GEOBENCH.CFG
cp build/pcw/GEOBENCH.CFG build/pcw/DEFAULT.CFG
python3 tools/mkpcwdsk.py QA/PCW/GEOBENCH.DSK \
    --boot build/pcwboot.bin --sys build/pcw/GBKERNP.RAW --load 0x8000 \
    --add build/pcw/GEOBENCH.CFG=GEOBENCH.CFG \
    --add build/pcw/DEFAULT.CFG=DEFAULT.CFG \
    --add build/GBCFG.RAW=GBCFG.MOD \
    --add build/GBUI.RAW=GBUI.MOD \
    --add build/GBWEB.RAW=GBWEB.MOD \
    --add build/GBIMG.RAW=GBIMG.MOD \
    --add build/pcw/SPLASH.MOD=SPLASH.MOD \
    --add build/pcw/DEFAULT.FNT=DEFAULT.FNT \
    --add build/pcw/DEFAULT.IST=DEFAULT.IST \
    --add build/pcw/REFINED.IST=REFINED.IST \
    --add build/pcw/DEFAULT.SPR=DEFAULT.SPR \
    --add build/pcw/DESKTOP.RAW=DESKTOP.APP \
    --add build/pcw/FILEMGR.RAW=FILEMGR.APP \
    --add build/pcw/NOTEPAD.RAW=NOTEPAD.APP \
    --add build/pcw/SETTINGS.RAW=SETTINGS.APP \
    --add build/pcw/VIEWER.RAW=VIEWER.APP \
    --add build/pcw/CLOCK.RAW=CLOCK.APP \
    --add build/pcw/TIMESYNC.RAW=TIMESYNC.APP \
    --add build/pcw/ICONED.RAW=ICONED.APP \
    --add build/pcw/SHELL.RAW=SHELL.APP \
    --add build/pcw/BRSAVE.RAW=BRSAVE.APP \
    --add build/pcw/SQUARES.RAW=SQUARES.SAV \
    --add build/pcw/LOGO.PIC=LOGO.PIC \
    --add build/pcw/CLASSIC.FNT=CLASSIC.FNT

# --- COMPANION.DSK: TELNET, backdrops and spare assets (plain CF2 data disc)
COMP_ADDS=()
for bdp in assets/backdrops/*.BDP; do
    name=$(basename "$bdp" .BDP | tr a-z A-Z)
    cp "$bdp" "build/pcw/$name.BDP"
    COMP_ADDS+=(--add "build/pcw/$name.BDP=$name.BDP")
done
python3 tools/mkpcwdsk.py QA/PCW/COMPANION.DSK \
    "${COMP_ADDS[@]}" \
    --add build/pcw/TELNET.RAW=TELNET.APP \
    --add build/pcw/NETTEST.RAW=NETTEST.APP \
    --add build/pcw/WGET.RAW=WGET.APP \
    --add build/pcw/BROWSER.RAW=BROWSER.APP \
    --add build/pcw/XAOS.RAW=XAOS.APP \
    --add build/pcw/MAHJONG.RAW=MAHJONG.APP \
    --add assets/WELCOME.TXT=WELCOME.TXT

# --- EXTRAS.DSK: portable gallery + standalone apps on a 720K CF2DD disc
echo "Building GB-PAINT PCW payload from $GB_PAINT_DIR"
make -C "$GB_PAINT_DIR" GEOBENCH="$PWD" app-pcw assets-pcw
echo "Building GB-BASIC PCW payload from $GB_BASIC_DIR"
make -C "$GB_BASIC_DIR" GEOBENCH="$PWD" raws-pcw

for f in \
    "$GB_PAINT_DIR/build/pcw/PAINT.APP" \
    "$GB_PAINT_DIR/build/PAINT.IST" \
    "$GB_BASIC_DIR/build/pcw/BASIC.RAW" \
    "$GB_BASIC_DIR/build/pcw/BASRUN.RAW" \
    "$GB_BASIC_DIR/build/pcw/BASRUN2.BIN"; do
    [ -s "$f" ] || { echo "ERROR: missing PCW extras payload $f" >&2; exit 1; }
done

rm -rf build/pcw/basic-examples
mkdir -p build/pcw/basic-examples
for bas in "$GB_BASIC_DIR"/examples/*.BAS; do
    sed 's/$/\r/' "$bas" > "build/pcw/basic-examples/$(basename "$bas")"
done

EXTRAS_ADDS=(
    --add "$GB_PAINT_DIR/build/pcw/PAINT.APP=PAINT.APP"
    --add "$GB_PAINT_DIR/build/PAINT.IST=PAINT.IST"
    --add "$GB_BASIC_DIR/build/pcw/BASIC.RAW=BASIC.APP"
    --add "$GB_BASIC_DIR/build/pcw/BASRUN.RAW=BASRUN.APP"
    --add "$GB_BASIC_DIR/build/pcw/BASRUN2.BIN=BASRUN2.BIN"
    --add "build/pcw/ANT.RAW=ANT.SAV"
    --add "build/pcw/DECO.RAW=DECO.SAV"
    --add "build/pcw/XMATRIX.RAW=XMATRIX.SAV"
)
while IFS= read -r pic; do
    name=$(basename "$pic" .PIC | tr a-z A-Z)
    EXTRAS_ADDS+=(--add "$pic=$name.PIC")
done < <(python3 tools/picture_catalog.py portable)
for bas in build/pcw/basic-examples/*.BAS; do
    EXTRAS_ADDS+=(--add "$bas=$(basename "$bas")")
done
rm -f QA/PCW/MEDIA.DSK
python3 tools/mkpcwdsk.py QA/PCW/EXTRAS.DSK --type cf2dd "${EXTRAS_ADDS[@]}"

echo "PCW target built: QA/PCW/GEOBENCH.DSK + COMPANION.DSK + EXTRAS.DSK"
