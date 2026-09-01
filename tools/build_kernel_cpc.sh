#!/usr/bin/env bash
# Reintroduce the CPC target against the compile-once ABI (issue #54-A).
# The transitional Desktop/File Manager are native bootstrap shells; every app
# selected for ABI proof is copied from build/universal without recompilation.
set -euo pipefail
cd "$(dirname "$0")/.."

RASM="${RASM:-rasm}"
PREEMPTIVE="${PREEMPTIVE:-1}"
CPC_BUILD=build/cpc
CPC_QA=QA/CPC
CPC_CARD="$CPC_QA/CARD"
CPC_SYS="$CPC_CARD/GBENCH"
CPC_FLOPPIES="$CPC_QA/Floppies"

mkdir -p "$CPC_BUILD" "$CPC_SYS" "$CPC_FLOPPIES"

if [ "$PREEMPTIVE" != "1" ]; then
    echo "ERROR: the restored CPC target requires the shared preemptive ABI runtime" >&2
    exit 2
fi
RASM="$RASM" bash tools/build_scheduler.sh cpc
EXTRA_RASM="${EXTRA_RASM:-} -DPLATFORM_CPC=1 -DPREEMPTIVE=1 -DPREEMPTIVE_CONTEXT=1"
export EXTRA_RASM
CPC_ROOT_APPDEFS="${GLOBAL_APPDEFS:-} -DGB_PREEMPTIVE"

CPC_PREEMPTIVE=1 RASM="$RASM" bash tools/build_titlebarmod.sh
tools/build_uimod.sh                              # shared MSX/CPC menus and dialogs
python3 tools/make_bootsplash.py assets/SPLASH.png "$CPC_BUILD/SPLASH_BUILD.png" \
    "$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)" GEOBENCH
python3 tools/png2cpc.py "$CPC_BUILD/SPLASH_BUILD.png" "$CPC_BUILD/SPLASH.BIN" splash 96x184
python3 tools/genfont.py "$CPC_BUILD/DEFAULT.FNT"
python3 tools/packicons.py "$CPC_BUILD/DEFAULT.IST" \
    lib/icon_floppy.asm lib/icon_clock.asm lib/icon_trash.asm \
    lib/icon_geobench.asm lib/icon_basic.asm lib/icon_binary.asm \
    lib/icon_picture.asm lib/icon_text.asm lib/icon_folder.asm \
    lib/icon_app.asm lib/icon_font.asm lib/icon_desktop.asm \
    lib/icon_filemanager.asm lib/icon_sd.asm lib/icon_up.asm \
    lib/icon_screensaver.asm lib/icon_cf.asm lib/icon_ide.asm \
    lib/icon_fractal.asm lib/icon_settings.asm lib/icon_calculator.asm
cp assets/iconsets/REFINED.IST "$CPC_BUILD/REFINED.IST"

printf 'FONT=DEFAULT\r\nICONS=REFINED\r\nCURSOR=DEFAULT\r\nTITLEBAR=ORIGINAL\r\nGADGETS=ORIGINAL\r\nVIEW=DEFAULT\r\nBACKDROP=SOLID\r\nWALLPAPER=LOGO\r\nSAVER=SQUARES\r\nSAVERTIME=2\r\n' \
    > "$CPC_BUILD/GEOBENCH.CFG"

TASK_STACK_RESERVE=256 \
    GB_DEFER=1 GB_TIMER_COLLECTOR=1 \
    GLOBAL_APPDEFS="$CPC_ROOT_APPDEFS" \
    APPDEFS="-DGB_CPC -DGB_DESK_ACCESSORIES" APP_CFLAGS="-I include/gembench" \
    DATA_LOC=0x7800 DOC=1 TITLEBAR=1 \
    tools/build_capp.sh apps/desktop "$CPC_BUILD/DESKTOP.RAW"
APPDEFS="-DGB_CPC" APP_CFLAGS="--max-allocs-per-node 5000" \
    DATA_LOC=0x7960 DOC=1 SCROLL=1 REPAINTTOP=1 \
    APP_PROBE=1 tools/build_capp.sh apps/filemgr "$CPC_BUILD/FILEMGR.RAW"
APPDEFS="-DGB_CPC" tools/build_cfgmod.sh "$CPC_BUILD/GBCFG.RAW"

make geobench-v2-abiprobe geobench-v2-tier1
RASM="$RASM" bash tools/build_m4savemod.sh

"$RASM" tools/m4detect.asm -eo

(
    cd "$CPC_BUILD"
    "$RASM" ../../kernel/cpc_gbap4.asm -DPREEMPTIVE=1
)
"$RASM" kernel/modules/cpcdrag.asm -eo -DPREEMPTIVE=1

(
    cd kernel
    "$RASM" gbkern.asm -eo -DPLATFORM_CPC=1 -DSTORAGE_ALBIREO=1 \
        -DCPC_COMPACT=1 -DTITLEBAR_TILE=1 -DPREEMPTIVE=1 -DPREEMPTIVE_CONTEXT=1
)
cp "$CPC_BUILD/GBKERN.RAW" "$CPC_BUILD/GBALB.RAW"

(
    cd kernel
    "$RASM" gbkern.asm -eo -DPLATFORM_CPC=1 -DSTORAGE_M4=1 \
        -DCPC_COMPACT=1 -DTITLEBAR_TILE=1 -DPREEMPTIVE=1 -DPREEMPTIVE_CONTEXT=1
)
cp "$CPC_BUILD/GBKERN.RAW" "$CPC_BUILD/GBM4.RAW"

# The floppy has no card firmware and therefore retains the Albireo kernel,
# whose storage layer falls back to AMSDOS when no CH376 device is present.
cp "$CPC_BUILD/GBALB.RAW" "$CPC_BUILD/GBKERN.RAW"

rm -f "$CPC_BUILD/GEOBENCH.DSK"
for pass in 1 2 3 4 5 6; do
    (
        cd kernel
        "$RASM" package_cpc.asm -eo -DPACKAGE_PASS="$pass" >/dev/null
    )
done
cp "$CPC_BUILD/GEOBENCH.DSK" "$CPC_FLOPPIES/GEOBENCH.DSK"

rm -rf "$CPC_CARD"
mkdir -p "$CPC_SYS"
printf '10 MEMORY &3FFF\r\n20 LOAD"M4DETECT",&4000\r\n30 CALL &4000\r\n40 IF PEEK(16432)=1 THEN RUN"GBM4\r\n50 RUN"GBALB\r\n' \
    > "$CPC_CARD/GB.BAS"
python3 tools/make_autoexec_bas.py "$CPC_CARD/AUTOEXEC.BAS"
python3 tools/amsdos_header.py build/M4DETECT.RAW \
    "$CPC_CARD/M4DETECT.BIN" M4DETECT BIN 0x4000
python3 tools/amsdos_header.py "$CPC_BUILD/GBALB.RAW" \
    "$CPC_CARD/GBALB.BIN" GBALB BIN 0x8000
python3 tools/amsdos_header.py "$CPC_BUILD/GBM4.RAW" \
    "$CPC_CARD/GBM4.BIN" GBM4 BIN 0x8000
cp "$CPC_BUILD/GEOBENCH.CFG" "$CPC_CARD/GEOBENCH.CFG"
cp "$CPC_BUILD/DESKTOP.RAW" "$CPC_SYS/DESKTOP.APP"
cp "$CPC_BUILD/FILEMGR.RAW" "$CPC_SYS/FILEMGR.APP"
cp build/universal/ABIPROBE.APP "$CPC_SYS/ABIPROBE.APP"
cp build/universal/CLOCK.APP "$CPC_SYS/CLOCK.APP"
cp build/universal/CALC.APP "$CPC_SYS/CALC.APP"
cp "$CPC_BUILD/GBCFG.RAW" "$CPC_SYS/GBCFG.MOD"
cp "$CPC_BUILD/GBSCHED.RAW" "$CPC_SYS/GBSCHED.MOD"
cp build/GBTITLE.RAW "$CPC_SYS/GBTITLE.MOD"
cp "$CPC_BUILD/GBAPV4.RAW" "$CPC_SYS/GBAPV4.MOD"
cp "$CPC_BUILD/GBDRAG.RAW" "$CPC_SYS/GBDRAG.MOD"
cp build/M4SAVE.RAW "$CPC_SYS/M4SAVE.MOD"
cp build/GBUI.RAW "$CPC_SYS/GBUI.MOD"
cp "$CPC_BUILD/DEFAULT.FNT" "$CPC_BUILD/DEFAULT.IST" "$CPC_BUILD/REFINED.IST" \
    "$CPC_BUILD/DEFAULT.SPR" "$CPC_BUILD/SPLASH.BIN" "$CPC_SYS/"
mv "$CPC_SYS/SPLASH.BIN" "$CPC_SYS/SPLASH.MOD"

bash tools/build_card_img.sh "$CPC_CARD" "$CPC_QA/GEOBENCH.IMG"
python3 tools/test_cpc_universal_stage.py
echo "CPC bootstrap built: $CPC_FLOPPIES/GEOBENCH.DSK + $CPC_CARD + $CPC_QA/GEOBENCH.IMG"
