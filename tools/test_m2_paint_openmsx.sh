#!/usr/bin/env bash
# Validate Paint's MSX2 multi-window application lifecycle in openMSX.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s assets/pictures/LOGO.PIC ] || {
    echo "ERROR: assets/pictures/LOGO.PIC is missing" >&2
    exit 1
}
[ -s build/msx/PAINT.RAW ] || {
    echo "ERROR: build/msx/PAINT.RAW is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s build/msx/gbkernm7.sym ] || {
    echo "ERROR: build/msx/gbkernm7.sym is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s build/msx-obj/paint/app.noi ] && [ -s build/msx-obj/paint/main.sym ] || {
    echo "ERROR: Paint symbols are missing; run 'make gembench-msx' first" >&2
    exit 1
}

symbol_address() {
    awk -v symbol="$1" '$1 == symbol { sub(/^#/, "0x", $2); print $2; exit }' \
        build/msx/gbkernm7.sym
}

paint_data_base="$(awk '$2 == "s__DATA" { print $3; exit }' \
    build/msx-obj/paint/app.noi)"
paint_data_address() {
    local offset
    offset="$(awk -v symbol="$1" '$2 == symbol { print "0x" $3; exit }' \
        build/msx-obj/paint/main.sym)"
    [ -n "$paint_data_base" ] && [ -n "$offset" ] || return 1
    printf '0x%X' "$((paint_data_base + offset))"
}

export GEMBENCH_M2_PAINT_OUTPUT="$PWD/build/msx/m2-paint-openmsx.txt"
export GEMBENCH_M2_PAINT_SCREENSHOT="$PWD/build/msx/m2-paint-openmsx.png"
export GEMBENCH_M2_REPAINT_START="$(symbol_address WM_REPAINT_ALL)"
export GEMBENCH_M2_REPAINT_DONE="$(symbol_address WRA_DONE)"
export GEMBENCH_M2_TOOL_X="$(paint_data_address _tc_x)"
export GEMBENCH_M2_TOOL_Y="$(paint_data_address _tc_y)"
export GEMBENCH_M2_PREVIEW_X="$(paint_data_address _pv_x)"
export GEMBENCH_M2_PREVIEW_Y="$(paint_data_address _pv_y)"
export GEMBENCH_M2_WORK_X="$(paint_data_address _wk_x)"
export GEMBENCH_M2_WORK_Y="$(paint_data_address _wk_y)"
[ -n "$GEMBENCH_M2_REPAINT_START" ] && [ -n "$GEMBENCH_M2_REPAINT_DONE" ] || {
    echo "ERROR: repaint symbols are missing from build/msx/gbkernm7.sym" >&2
    exit 1
}
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/m2_paint_openmsx.tcl

stage=$(mktemp -d -p build/msx m2-paint-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp assets/pictures/LOGO.PIC "$stage/card/A.PIC"
# The normal .PIC association is Viewer. Replace only the disposable test
# image's VIEWER.APP with Paint so File Manager passes A.PIC as Paint's launch
# document without changing the release catalog or production association.
cp build/msx/PAINT.RAW "$stage/card/GBENCH/VIEWER.APP"
tools/build_msx_img.sh "$stage/card" "$stage/m2-paint.img"
tools/run_msx.sh "$stage/m2-paint.img"

sed -n '1,30p' "$GEMBENCH_M2_PAINT_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_M2_PAINT_OUTPUT"
