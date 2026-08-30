#!/usr/bin/env bash
# Validate Paint's MSX2 multi-window application lifecycle in openMSX.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s assets/pictures/LOGO.PIC ] || {
    echo "ERROR: assets/pictures/LOGO.PIC is missing" >&2
    exit 1
}
[ -s build/msx/PAINT.RAW ] || {
    echo "ERROR: build/msx/PAINT.RAW is missing; run 'make gembench-msx' first" >&2
    exit 1
}

export GEMBENCH_M2_PAINT_OUTPUT="$PWD/build/msx/m2-paint-openmsx.txt"
export GEMBENCH_M2_PAINT_SCREENSHOT="$PWD/build/msx/m2-paint-openmsx.png"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/m2_paint_openmsx.tcl

stage=$(mktemp -d -p build/msx m2-paint-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp assets/pictures/LOGO.PIC "$stage/card/A.PIC"
# The normal .PIC association is Viewer. Replace only the disposable test
# image's VIEWER.APP with Paint so File Manager passes A.PIC as Paint's launch
# document without changing the release catalog or production association.
cp build/msx/PAINT.RAW "$stage/card/GBENCH/VIEWER.APP"
tools/build_msx_img.sh "$stage/card" "$stage/m2-paint.img"
tools/run_msx.sh "$stage/m2-paint.img"

sed -n '1,30p' "$GEMBENCH_M2_PAINT_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_M2_PAINT_OUTPUT"
