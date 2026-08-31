#!/usr/bin/env bash
# Exercise the MSX2 Clock through GEMBENCH's non-blocking multi-event adapter.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/CLOCK.RAW ] || {
    echo "ERROR: build/msx/CLOCK.RAW is missing; run 'make geobench-msx' first" >&2
    exit 1
}
[ -s build/msx-obj/clock/app.noi ] || {
    echo "ERROR: Clock symbols are missing; run 'make geobench-msx' first" >&2
    exit 1
}
# This historical M8 probe deliberately exercises the retained legacy build.
# The release card now stages build/universal/CLOCK.APP.

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
export GEMBENCH_EVENT_CLOCK_WORKER="$(hexsum "$code_base" "0x$(symbol_offset _clock_timer)")"
export GEMBENCH_EVENT_AFTER_COLLECT="$(hexsum "$code_base" "$(call_return_offset _gb_event_collect)")"
export GEMBENCH_EVENT_SHOW_SEC="$(hexsum "$data_base" "0x$(symbol_offset _show_sec)")"
export GEMBENCH_EVENT_TIMER_PART="$(hexsum "$data_base" "0x$(symbol_offset _timer_part)")"
export GEMBENCH_EVENT_TIMER_DIGIT_DUE="$(hexsum "$data_base" "0x$(symbol_offset _timer_digit_due)")"
export GEMBENCH_EVENT_TIMER_WINDOW="$(hexsum "$data_base" "0x$(symbol_offset _timer_window)")"
export GEMBENCH_EVENT_SUBSCRIPTION="$(hexsum "$data_base" "0x$(symbol_offset _clock_events)")"
export GEMBENCH_EVENT_RECORD="$(hexsum "$data_base" "0x$(symbol_offset _clock_event)")"
export GEMBENCH_EVENT_TIMER_COLLECT="$(awk '$1 == "DEF" && $2 == "_gb_timer_collect" { print $3; found=1; exit } END { if (!found) exit 1 }' build/msx-obj/desktop/app.noi)"
export GEMBENCH_EVENT_K_POLL="0x$(awk '$1 == "K_POLL" { value=$2; sub(/^#/, "", value); print value; found=1; exit } END { if (!found) exit 1 }' build/msx/gbkernm7.sym)"
export GEMBENCH_EVENT_PAINTLOCK="0x$(awk '$1 == "CUR_PAINTLOCK" { value=$2; sub(/^#/, "", value); print value; found=1; exit } END { if (!found) exit 1 }' build/msx/gbkernm7.sym)"

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
export GEMBENCH_EVENT_FM_TOTAL="$(fm_data_address _total)"
export GEMBENCH_EVENT_FM_NAMES="$(fm_data_address _names)"
export GEMBENCH_EVENT_FM_ORDER="$(fm_data_address _order)"
export GEMBENCH_EVENT_FM_LIST_STATE="$(fm_data_address _list_state)"
export GEMBENCH_EVENT_FM_VIEW="$(fm_data_address _view)"

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
