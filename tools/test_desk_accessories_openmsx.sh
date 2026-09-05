#!/usr/bin/env bash
# Exercise on-demand Desk launch, exact activation, close, and relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/DESKTOP.RAW ]
[ -s build/universal/CLOCK.APP ]
[ -s build/universal/CALC.APP ]
cmp -s build/msx/DESKTOP.RAW QA/MSX/CARD/GBENCH/DESKTOP.APP
cmp -s build/universal/CLOCK.APP QA/MSX/CARD/GBENCH/CLOCK.APP
cmp -s build/universal/CALC.APP QA/MSX/CARD/GBENCH/CALC.APP

app_signature() {
    local image="$1" noi="$2" main offset
    main=$(awk '$1 == "DEF" && $2 == "_main" { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$noi")
    offset=$((main - 0x4000))
    printf '%s ' "$main"
    od -An -t u1 -j "$offset" -N 3 "$image"
}

read -r clock_main clock_sig0 clock_sig1 clock_sig2 < <(app_signature \
    build/universal/CLOCK.APP build/universal-obj/uclock/app.noi)
read -r calc_main calc_sig0 calc_sig1 calc_sig2 < <(app_signature \
    build/universal/CALC.APP build/universal-obj/ucalculator/app.noi)
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
sed -i "s/^MSXMODE=.*/MSXMODE=${MSX_TEST_MODE:-7}/" "$stage/card/GEOBENCH.CFG"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
tools/build_msx_img.sh "$stage/card" "$stage/desk-accessories.img"

export GEMBENCH_ACCESSORY_OUTPUT="$PWD/build/msx/desk-accessories-${MSX_TEST_MODE:-7}-openmsx.txt"
export GEMBENCH_ACCESSORY_LAYOUT="$PWD/kernel/lowram.inc"
export GEMBENCH_ACCESSORY_SCREENSHOT="$PWD/build/msx/desk-accessories-${MSX_TEST_MODE:-7}-openmsx.png"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=${GEOBENCH_ACCESSORY_SCRIPT:-debug/desk_accessories_openmsx.tcl}
tools/run_msx.sh "$stage/desk-accessories.img"

sed -n '1,40p' "$GEMBENCH_ACCESSORY_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_ACCESSORY_OUTPUT"
