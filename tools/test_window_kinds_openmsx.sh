#!/usr/bin/env bash
# Exercise tagged MSX2 window furniture and geometry messages in openMSX.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s QA/MSX/GBMSX.IMG ] || {
    echo "ERROR: QA/MSX/GBMSX.IMG is missing; run 'make gembench-msx' first" >&2
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
cursor_x_raw=$(awk '$1 == "CURSOR_X" { print $2; exit }' build/msx/gbkernm7.sym)
[ -n "$cursor_x_raw" ] || { echo "ERROR: CURSOR_X not found in kernel symbols" >&2; exit 1; }
printf -v cursor_x '0x%s' "${cursor_x_raw#\#}"

export GEMBENCH_WINDOW_KINDS_OUTPUT="$PWD/build/msx/window-kinds-openmsx.txt"
export GEMBENCH_WINDOW_KINDS_SCREENSHOT="$PWD/build/msx/window-kinds.png"
export GEMBENCH_WINDOW_KINDS_FM_PROC="$fm_proc"
export GEMBENCH_WINDOW_KINDS_CURSOR_X="$cursor_x"
export MSX_UNAPI=0
export MSX_MOUSE=0
export MSX_SCRIPT=debug/window_kinds_openmsx.tcl
tools/run_msx.sh QA/MSX/GBMSX.IMG

sed -n '1,30p' "$GEMBENCH_WINDOW_KINDS_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_WINDOW_KINDS_OUTPUT"
