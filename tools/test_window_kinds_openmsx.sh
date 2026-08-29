#!/usr/bin/env bash
# Exercise explicitly versioned MSX2 window furniture and geometry messages in openMSX.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s build/msx-obj/filemgr/main.sym ] || {
    echo "ERROR: File Manager symbols are missing; run 'make gembench-msx' first" >&2
    exit 1
}

fm_rel=$(awk '$2 == "_fm_proc" { print $3; exit }' build/msx-obj/filemgr/main.sym)
[ -n "$fm_rel" ] || { echo "ERROR: _fm_proc not found in File Manager symbols" >&2; exit 1; }
main_rel=$(awk '$2 == "_main" { print $3; exit }' build/msx-obj/filemgr/main.sym)
main_abs=$(awk '$1 == "DEF" && $2 == "_main" { print $3; exit }' build/msx-obj/filemgr/app.noi)
[ -n "$main_rel" ] && [ -n "$main_abs" ] || {
    echo "ERROR: _main relocation not found in File Manager symbols" >&2
    exit 1
}
printf -v fm_proc '0x%X' "$((0x${main_abs#0x} - 0x$main_rel + 0x$fm_rel))"
list_state_rel=$(awk '$1 == "1" && $2 == "_list_state" { print $3; exit }' build/msx-obj/filemgr/main.sym)
data_abs=$(awk '$1 == "DEF" && $2 == "s__DATA" { print $3; exit }' build/msx-obj/filemgr/app.noi)
[ -n "$list_state_rel" ] && [ -n "$data_abs" ] || {
    echo "ERROR: File Manager list-state relocation not found" >&2
    exit 1
}
printf -v list_state '0x%X' "$((0x${data_abs#0x} + 0x$list_state_rel))"
view_rel=$(awk '$2 == "_view" { print $3; exit }' build/msx-obj/filemgr/main.sym)
view_menu_rel=$(awk '$2 == "_view_menu" { print $3; exit }' build/msx-obj/filemgr/main.sym)
init_abs=$(awk '$1 == "DEF" && $2 == "s__INITIALIZED" { print $3; exit }' build/msx-obj/filemgr/app.noi)
[ -n "$view_rel" ] && [ -n "$view_menu_rel" ] && [ -n "$init_abs" ] || {
    echo "ERROR: File Manager resource-menu symbols not found" >&2
    exit 1
}
printf -v view_addr '0x%X' "$((0x${init_abs#0x} + 0x$view_rel))"
# gbr_menu_t keeps its caller-owned state array at byte offset 8.
printf -v menu_state '0x%X' "$((0x${data_abs#0x} + 0x$view_menu_rel + 8))"
cursor_x_raw=$(awk '$1 == "CURSOR_X" { print $2; exit }' build/msx/gbkernm7.sym)
[ -n "$cursor_x_raw" ] || { echo "ERROR: CURSOR_X not found in kernel symbols" >&2; exit 1; }
printf -v cursor_x '0x%s' "${cursor_x_raw#\#}"

export GEMBENCH_WINDOW_KINDS_OUTPUT="$PWD/build/msx/window-kinds-openmsx.txt"
export GEMBENCH_WINDOW_KINDS_SCREENSHOT="$PWD/build/msx/window-kinds.png"
if [ "${MSX_HEADLESS:-0}" = 1 ]; then
    export GEMBENCH_WINDOW_KINDS_SCREENSHOTS=0
else
    export GEMBENCH_WINDOW_KINDS_SCREENSHOTS=1
fi
export GEMBENCH_WINDOW_KINDS_FM_PROC="$fm_proc"
export GEMBENCH_WINDOW_KINDS_LIST_STATE="$list_state"
export GEMBENCH_WINDOW_KINDS_CURSOR_X="$cursor_x"
export GEMBENCH_WINDOW_KINDS_VIEW="$view_addr"
export GEMBENCH_WINDOW_KINDS_MENU_STATE="$menu_state"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/window_kinds_openmsx.tcl

stage=$(mktemp -d -p build/msx window-kinds-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
tools/build_msx_img.sh "$stage/card" "$stage/window-kinds.img"
tools/run_msx.sh "$stage/window-kinds.img"

sed -n '1,30p' "$GEMBENCH_WINDOW_KINDS_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_WINDOW_KINDS_OUTPUT"
