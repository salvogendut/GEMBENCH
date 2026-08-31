#!/usr/bin/env bash
# Exercise the M6 secondary-code ABI, rejection policy, and owner cleanup.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make geobench-msx' first" >&2
    exit 1
}
[ -s build/msx/FORMREF.RAW ] && [ -s build/msx-obj/formref/app.noi ] || {
    echo "ERROR: M6 FormRef is missing; run 'make geobench-msx' first" >&2
    exit 1
}
python3 tools/embed_app_icon.py check build/msx/FORMREF.RAW | \
    grep -q 'segments 2'

noi=build/msx-obj/formref/app.noi
lst=build/msx-obj/formref/main.lst
noi_addr() {
    awk -v symbol="$1" '$1 == "DEF" && $2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$noi"
}
lst_offset() {
    awk -v symbol="$1" '$NF ~ /:$/ { label=$NF; sub(/:+$/, "", label) }
        label == symbol { print "0x" $1; found=1; exit }
        END { if (!found) exit 1 }' "$lst"
}

main_abs="$(noi_addr _main)"
main_local="$(lst_offset _main)"
code_base=$((main_abs - main_local))
export GEMBENCH_M6_K_POLL="0x$(awk '$1 == "K_POLL" { value=$2; sub(/^#/, "", value); print value; exit }' build/msx/gbkernm7.sym)"
export GEMBENCH_M6_APP_DRAW="$(printf '0x%X\n' "$((code_base + $(lst_offset _app_draw)))")"
export GEMBENCH_M6_CALL="$(noi_addr _gb_secondary_call)"
export GEMBENCH_M6_HANDLE="$(noi_addr _form_secondary)"
export GEMBENCH_M6_OUTPUT="$PWD/build/msx/m6-secondary-openmsx.txt"
export MSX_UNAPI=0
export MSX_MOUSE=0
export MSX_HEADLESS=1
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/m6_secondary_openmsx.tcl

stage=$(mktemp -d -p build/msx m6-secondary-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir -p "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
sed -i 's/^SAVERTIME=.*/SAVERTIME=0/' "$stage/card/GEOBENCH.CFG"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp build/msx/FORMREF.RAW "$stage/card/GBENCH/FILEMGR.APP"
tools/build_msx_img.sh "$stage/card" "$stage/m6-secondary.img"
tools/run_msx.sh "$stage/m6-secondary.img"
sed -n '1,80p' "$GEMBENCH_M6_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_M6_OUTPUT"
