#!/usr/bin/env bash
# Exercise the MSX2 Clock through GEMBENCH's non-blocking multi-event adapter.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/CLOCK.RAW ] || {
    echo "ERROR: build/msx/CLOCK.RAW is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s build/msx-obj/clock/app.noi ] || {
    echo "ERROR: Clock symbols are missing; run 'make gembench-msx' first" >&2
    exit 1
}
cmp -s build/msx/CLOCK.RAW QA/MSX/CARD/GBENCH/CLOCK.APP || {
    echo "ERROR: staged CLOCK.APP does not match build/msx/CLOCK.RAW; run 'make gembench-msx' first" >&2
    exit 1
}

sym=build/msx-obj/clock/main.sym
noi=build/msx-obj/clock/app.noi
symbol_offset() {
    awk -v symbol="$1" '$2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$sym"
}
call_return_offset() {
    call_offset=$(awk -v symbol="$1" '$NF == symbol && $(NF-1) == "call" {
            print "0x" $1; found=1; exit
        } END { if (!found) exit 1 }' build/msx-obj/clock/main.lst)
    printf '0x%X\n' "$((call_offset + 3))"
}
noi_addr() {
    awk -v symbol="$1" '$1 == "DEF" && $2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$noi"
}
hexsum() { printf '0x%X\n' "$(( $1 + $2 ))"; }

main_abs="$(noi_addr _main)"
main_offset="$(symbol_offset _main)"
code_base=$((main_abs - 0x$main_offset))
data_base=$(( $(noi_addr s__DATA) ))

export GEMBENCH_EVENT_MAIN="$main_abs"
export GEMBENCH_EVENT_C_DRAW="$(hexsum "$code_base" "0x$(symbol_offset _c_draw)")"
export GEMBENCH_EVENT_C_FRAME="$(hexsum "$code_base" "0x$(symbol_offset _c_frame)")"
export GEMBENCH_EVENT_C_CLICK="$(hexsum "$code_base" "0x$(symbol_offset _c_click)")"
export GEMBENCH_EVENT_AFTER_COLLECT="$(hexsum "$code_base" "$(call_return_offset _gb_event_collect)")"
export GEMBENCH_EVENT_SHOW_SEC="$(hexsum "$data_base" "0x$(symbol_offset _show_sec)")"
export GEMBENCH_EVENT_SUBSCRIPTION="$(hexsum "$data_base" "0x$(symbol_offset _clock_events)")"
export GEMBENCH_EVENT_RECORD="$(hexsum "$data_base" "0x$(symbol_offset _clock_event)")"

main_file_offset=$((main_abs - 0x4000))
read -r sig0 sig1 sig2 < <(od -An -t u1 -j "$main_file_offset" -N 3 build/msx/CLOCK.RAW)
export GEMBENCH_EVENT_SIG0="$sig0"
export GEMBENCH_EVENT_SIG1="$sig1"
export GEMBENCH_EVENT_SIG2="$sig2"

mkdir -p build/msx
stage=$(mktemp -d -p build/msx multi-event-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp build/msx/CLOCK.RAW "$stage/card/A.APP"
tools/build_msx_img.sh "$stage/card" "$stage/multi-event.img"

export GEMBENCH_EVENT_OUTPUT="$PWD/build/msx/multi-event-openmsx.txt"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/multi_event_openmsx.tcl
tools/run_msx.sh "$stage/multi-event.img"

sed -n '1,30p' "$GEMBENCH_EVENT_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_EVENT_OUTPUT"
