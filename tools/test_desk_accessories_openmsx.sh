#!/usr/bin/env bash
# Exercise on-demand Desk launch, exact activation, close, and relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."

for app in DESKTOP CLOCK CALC; do
    [ -s "build/msx/$app.RAW" ] || {
        echo "ERROR: build/msx/$app.RAW is missing; run 'make geobench-msx' first" >&2
        exit 1
    }
done
cmp -s build/msx/DESKTOP.RAW QA/MSX/CARD/GBENCH/DESKTOP.APP
cmp -s build/msx/CLOCK.RAW QA/MSX/CARD/GBENCH/CLOCK.APP
cmp -s build/msx/CALC.RAW QA/MSX/CARD/GBENCH/CALC.APP

app_signature() {
    local app="$1" stem="$2" noi main offset
    noi="build/msx-obj/$stem/app.noi"
    main=$(awk '$1 == "DEF" && $2 == "_main" { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$noi")
    offset=$((main - 0x4000))
    printf '%s ' "$main"
    od -An -t u1 -j "$offset" -N 3 "build/msx/$app.RAW"
}

read -r clock_main clock_sig0 clock_sig1 clock_sig2 < <(app_signature CLOCK clock)
read -r calc_main calc_sig0 calc_sig1 calc_sig2 < <(app_signature CALC calculator)
export GEMBENCH_ACCESSORY_CLOCK_MAIN="$clock_main"
export GEMBENCH_ACCESSORY_CLOCK_SIG0="$clock_sig0"
export GEMBENCH_ACCESSORY_CLOCK_SIG1="$clock_sig1"
export GEMBENCH_ACCESSORY_CLOCK_SIG2="$clock_sig2"
export GEMBENCH_ACCESSORY_CALC_MAIN="$calc_main"
export GEMBENCH_ACCESSORY_CALC_SIG0="$calc_sig0"
export GEMBENCH_ACCESSORY_CALC_SIG1="$calc_sig1"
export GEMBENCH_ACCESSORY_CALC_SIG2="$calc_sig2"

mkdir -p build/msx
stage=$(mktemp -d -p build/msx desk-accessory-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
tools/build_msx_img.sh "$stage/card" "$stage/desk-accessories.img"

export GEMBENCH_ACCESSORY_OUTPUT="$PWD/build/msx/desk-accessories-openmsx.txt"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/desk_accessories_openmsx.tcl
tools/run_msx.sh "$stage/desk-accessories.img"

sed -n '1,40p' "$GEMBENCH_ACCESSORY_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_ACCESSORY_OUTPUT"
