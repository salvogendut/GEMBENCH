#!/usr/bin/env bash
# Exercise Architecture Milestone 1 through its public MSX2 API in openMSX.
set -euo pipefail
cd "$(dirname "$0")/.."

make gembench-m1-sysinfo
[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make geobench-msx' first" >&2
    exit 1
}

sym=build/msx-obj/sysinfo/main.sym
noi=build/msx-obj/sysinfo/app.noi
data_abs=$(awk '$1 == "DEF" && $2 == "s__DATA" { print $3; exit }' "$noi")
[ -n "$data_abs" ] || { echo "ERROR: SYSINFO data base not found" >&2; exit 1; }
symbol_offset() {
    awk -v symbol="$1" '$2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$sym"
}
hexsum() { printf '0x%X\n' "$(( $1 + $2 ))"; }

export GEMBENCH_M1_TESTS="$(hexsum "$data_abs" "0x$(symbol_offset _tests)")"
export GEMBENCH_M1_INITIAL="$(hexsum "$data_abs" "0x$(symbol_offset _initial_free)")"
export GEMBENCH_M1_FINAL="$(hexsum "$data_abs" "0x$(symbol_offset _final_free)")"
export GEMBENCH_M1_OWNER="$(hexsum "$data_abs" "0x$(symbol_offset _owner)")"
export GEMBENCH_M1_RETAINED="$(hexsum "$data_abs" "0x$(symbol_offset _retained_page)")"
export GEMBENCH_M1_SYSINFO="$(hexsum "$data_abs" "0x$(symbol_offset _sysinfo_address)")"
export GEMBENCH_M3_TESTS="$(hexsum "$data_abs" "0x$(symbol_offset _defer_tests)")"
export GEMBENCH_M4_TESTS="$(hexsum "$data_abs" "0x$(symbol_offset _fsctx_tests)")"
fm_sym=build/msx-obj/filemgr/main.sym
fm_noi=build/msx-obj/filemgr/app.noi
fm_data_abs=$(awk '$1 == "DEF" && $2 == "s__DATA" { print $3; exit }' "$fm_noi")
fm_symbol_offset() {
    awk -v symbol="$1" '$2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$fm_sym"
}
export GEMBENCH_FM_TOTAL="$(hexsum "$fm_data_abs" "0x$(fm_symbol_offset _total)")"
export GEMBENCH_FM_NAMES="$(hexsum "$fm_data_abs" "0x$(fm_symbol_offset _names)")"
export GEMBENCH_FM_ORDER="$(hexsum "$fm_data_abs" "0x$(fm_symbol_offset _order)")"
export GEMBENCH_FM_LIST_STATE="$(hexsum "$fm_data_abs" "0x$(fm_symbol_offset _list_state)")"
export GEMBENCH_FM_ICON_POS="$(hexsum "$fm_data_abs" "0x$(fm_symbol_offset _icon_scan_pos)")"
export GEMBENCH_FM_VIEW="$(hexsum "$fm_data_abs" "0x$(fm_symbol_offset _view)")"
export GEMBENCH_K_POLL="0x$(awk '$1 == "K_POLL" { value=$2; sub(/^#/, "", value); print value; exit }' build/msx/gbkernm7.sym)"
# Standard RASM -s omits EQU constants. Seed boot readiness from the matching
# layout source; the launched diagnostic then supplies the actual API pointer.
sysinfo_record=$(awk '$1 == "MSX_SYSINFO" && $2 == "equ" {
    value=$3; sub(/^#/, "", value); print value; found=1; exit
} END { if (!found) exit 1 }' lib/msx/glue.inc)
export GEMBENCH_M1_SYSINFO_RECORD="0x$sysinfo_record"
export GEMBENCH_M1_OUTPUT="$PWD/build/msx/m1-architecture-openmsx.txt"
export GEMBENCH_M1_SCREENSHOT="$PWD/build/msx/m1-architecture.png"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/m1_architecture_openmsx.tcl

stage=$(mktemp -d -p build/msx m1-architecture-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
sed -i 's/^SAVERTIME=.*/SAVERTIME=0/' "$stage/card/GEOBENCH.CFG"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp build/msx/SYSINFO.RAW "$stage/card/A.APP"
tools/build_msx_img.sh "$stage/card" "$stage/m1-architecture.img"
tools/run_msx.sh "$stage/m1-architecture.img"

sed -n '1,40p' "$GEMBENCH_M1_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_M1_OUTPUT"
