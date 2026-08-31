#!/usr/bin/env bash
# Validate Paint's MSX2 multi-window application lifecycle in openMSX.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make geobench-msx' first" >&2
    exit 1
}
[ -s assets/pictures/LOGO.PIC ] || {
    echo "ERROR: assets/pictures/LOGO.PIC is missing" >&2
    exit 1
}
[ -s build/msx/PAINT.RAW ] || {
    echo "ERROR: build/msx/PAINT.RAW is missing; run 'make geobench-msx' first" >&2
    exit 1
}
[ -s build/msx/gbkernm7.sym ] || {
    echo "ERROR: build/msx/gbkernm7.sym is missing; run 'make geobench-msx' first" >&2
    exit 1
}
[ -s build/msx-obj/paint/app.noi ] && [ -s build/msx-obj/paint/main.sym ] || {
    echo "ERROR: Paint symbols are missing; run 'make geobench-msx' first" >&2
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

paint_code_address() {
    local linked_main object_main offset
    linked_main="$(awk '$2 == "_main" { print $3; exit }' \
        build/msx-obj/paint/app.noi)"
    object_main="$(awk '$2 == "_main" { print "0x" $3; exit }' \
        build/msx-obj/paint/main.sym)"
    offset="$(awk -v symbol="$1" '$2 == symbol { print "0x" $3; exit }' \
        build/msx-obj/paint/main.sym)"
    [ -n "$linked_main" ] && [ -n "$object_main" ] && [ -n "$offset" ] || return 1
    printf '0x%X' "$((linked_main - object_main + offset))"
}

filemgr_code_address() {
    local linked_main object_main offset
    linked_main="$(awk '$2 == "_main" { print $3; exit }' \
        build/msx-obj/filemgr/app.noi)"
    object_main="$(awk '$2 == "_main" { print "0x" $3; exit }' \
        build/msx-obj/filemgr/main.sym)"
    offset="$(awk -v symbol="$1" '$2 == symbol { print "0x" $3; exit }' \
        build/msx-obj/filemgr/main.sym)"
    [ -n "$linked_main" ] && [ -n "$object_main" ] && [ -n "$offset" ] || return 1
    printf '0x%X' "$((linked_main - object_main + offset))"
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
export GEMBENCH_M2_REPAINT_TOOL="$(paint_code_address _repaint_tool_window)"
export GEMBENCH_M2_REPAINT_PREVIEW="$(paint_code_address _repaint_preview_window)"
export GEMBENCH_M2_REPAINT_WORK="$(paint_code_address _repaint_work_window)"
export GEMBENCH_M2_PAINT_MAIN="$(awk '$2 == "_main" { print $3; exit }' \
    build/msx-obj/paint/app.noi)"
export GEMBENCH_M2_FM_OPEN_ENTRY="$(filemgr_code_address _open_entry)"
export GEMBENCH_M2_K_POLL="$(symbol_address K_POLL)"
fm_sym=build/msx-obj/filemgr/main.sym
fm_noi=build/msx-obj/filemgr/app.noi
fm_data_abs=$(awk '$1 == "DEF" && $2 == "s__DATA" { print $3; exit }' "$fm_noi")
fm_initialized_abs=$(awk '$1 == "DEF" && $2 == "s__INITIALIZED" { print $3; exit }' "$fm_noi")
fm_data_address() {
    local record area offset base
    record=$(awk -v symbol="$1" '$2 == symbol { print $1, $3; exit }' "$fm_sym")
    [ -n "$record" ] || return 1
    read -r area offset <<< "$record"
    case "$area" in
        1) base=$fm_data_abs ;;
        2) base=$fm_initialized_abs ;;
        *) return 1 ;;
    esac
    printf '0x%X' "$((base + 0x$offset))"
}
export GEMBENCH_M2_FM_TOTAL="$(fm_data_address _total)"
export GEMBENCH_M2_FM_NAMES="$(fm_data_address _names)"
export GEMBENCH_M2_FM_ORDER="$(fm_data_address _order)"
export GEMBENCH_M2_FM_LIST_STATE="$(fm_data_address _list_state)"
export GEMBENCH_M2_FM_VIEW="$(fm_data_address _view)"
export GEMBENCH_M2_FM_TOP="$(fm_data_address _top)"
export GEMBENCH_M2_FM_NSEL="$(fm_data_address _nsel)"
export GEMBENCH_M2_FM_DC_IDX="$(fm_data_address _dc_idx)"
export GEMBENCH_M2_FM_DC_TIMER="$(fm_data_address _dc_timer)"
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
sed -i 's/^SAVERTIME=.*/SAVERTIME=0/' "$stage/card/GEOBENCH.CFG"
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
