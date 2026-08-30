#!/usr/bin/env bash
# Exercise GBAP v3 success and transactional rejection through the real MSX2 loader.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s build/msx/FORMREF.RAW ] && [ -s build/msx-obj/formref/app.noi ] || {
    echo "ERROR: v3 FormRef is missing; run 'make gembench-msx' first" >&2
    exit 1
}
python3 tools/embed_app_icon.py check build/msx/FORMREF.RAW | grep -q 'GBAP v3'

export GEMBENCH_M5_K_POLL="0x$(awk '$1 == "K_POLL" { value=$2; sub(/^#/, "", value); print value; exit }' build/msx/gbkernm7.sym)"
export GEMBENCH_M5_MAIN="$(awk '$2 == "_main" { print $3; exit }' build/msx-obj/formref/app.noi)"
export GEMBENCH_M5_ENTRY="$(awk '$2 == "_start" { print $3; exit }' build/msx-obj/formref/app.noi)"
export GEMBENCH_M5_PAGES="$(python3 -c 'import pathlib,sys; sys.path.insert(0,"tools"); from embed_app_icon import parse_manifest; print(parse_manifest(pathlib.Path("build/msx/FORMREF.RAW").read_bytes())["minimum_pages"])')"
export MSX_UNAPI=0
export MSX_MOUSE=0
export MSX_HEADLESS=1
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/m5_gbap3_openmsx.tcl

stage=$(mktemp -d -p build/msx m5-gbap3-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

for mode in good bad; do
    mkdir -p "$stage/$mode/card"
    cp -a QA/MSX/CARD/. "$stage/$mode/card/"
    rm -f -- "$stage/$mode/card/UNAPINET.COM" "$stage/$mode/card/UNAPI.TXT"
    sed -i 's/^SAVERTIME=.*/SAVERTIME=0/' "$stage/$mode/card/GEOBENCH.CFG"
    printf 'GBMSX\r\n' > "$stage/$mode/card/AUTOEXEC.BAT"
    cp build/msx/FORMREF.RAW "$stage/$mode/card/GBENCH/FILEMGR.APP"
done

# Dual-icon FormRef has its manifest at offset 32; byte +7 is the platform mask.
# Zeroing it is a structurally malformed/incompatible v3 package that still
# reaches the standard guard through its intact outer JP.
printf '\0' | dd of="$stage/bad/card/GBENCH/FILEMGR.APP" \
    bs=1 seek=39 conv=notrunc status=none

for mode in good bad; do
    tools/build_msx_img.sh "$stage/$mode/card" "$stage/$mode/m5-$mode.img"
    export GEMBENCH_M5_MODE="$mode"
    export GEMBENCH_M5_OUTPUT="$PWD/build/msx/m5-gbap3-$mode.txt"
    tools/run_msx.sh "$stage/$mode/m5-$mode.img"
    sed -n '1,20p' "$GEMBENCH_M5_OUTPUT"
    grep -qx 'STATUS=PASS' "$GEMBENCH_M5_OUTPUT"
done
