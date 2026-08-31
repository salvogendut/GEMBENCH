#!/usr/bin/env bash
# Build and boot the bundled BASRUN graphics program without a sibling checkout.
set -euo pipefail
cd "$(dirname "$0")/.."

BASIC_DIR=components/gb-basic
[ -s QA/MSX/GBMSX.IMG ] || {
    echo "ERROR: QA/MSX/GBMSX.IMG is missing; run make geobench-msx first" >&2
    exit 1
}

GEOBENCH="$PWD" APPDEFS=-DGB_MSX2 NOGBWIN=1 DATA_LOC=0x7F40 \
    bash "$BASIC_DIR/tools/build_app.sh" apps/basrun build/msx/BASRUNBI.RAW

stage=$(mktemp -d -p build/msx gb-basic-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp "$BASIC_DIR/build/msx/BASRUNBI.RAW" "$stage/card/GBENCH/BASRUN.SAV"
cp "$BASIC_DIR/build/msx/BASRUN2.BIN" "$stage/card/GBENCH/BASRUN2.BIN"
cp "$BASIC_DIR/build/msx/BASRUNBI.RAW" "$stage/card/BASRUN.SAV"
cp "$BASIC_DIR/build/msx/BASRUN2.BIN" "$stage/card/BASRUN2.BIN"
printf 'SAVER=BASRUN\r\nSAVERTIME=1\r\nDEBUG=FALSE\r\n' \
    > "$stage/card/GEOBENCH.CFG"
tools/build_msx_img.sh "$stage/card" "$stage/gb-basic.img"

export GEMBENCH_GBBASIC_OUTPUT="$PWD/build/msx/gb-basic-openmsx.txt"
export MSX_UNAPI=0
export MSX_MOUSE=0
export MSX_HEADLESS=1
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/gb_basic_openmsx.tcl
tools/run_msx.sh "$stage/gb-basic.img"

sed -n '1,20p' "$GEMBENCH_GBBASIC_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_GBBASIC_OUTPUT"
