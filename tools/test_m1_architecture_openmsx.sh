#!/usr/bin/env bash
# Exercise Architecture Milestone 1 through its public MSX2 API in openMSX.
set -euo pipefail
cd "$(dirname "$0")/.."

make gembench-m1-sysinfo
[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make gembench-msx' first" >&2
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
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp build/msx/SYSINFO.RAW "$stage/card/A.APP"
tools/build_msx_img.sh "$stage/card" "$stage/m1-architecture.img"
tools/run_msx.sh "$stage/m1-architecture.img"

sed -n '1,40p' "$GEMBENCH_M1_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_M1_OUTPUT"
