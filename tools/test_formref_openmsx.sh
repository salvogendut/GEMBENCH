#!/usr/bin/env bash
# Build a disposable openMSX image and exercise the MSX2 GBR-backed FormRef.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/FORMREF.RAW ] || {
    echo "ERROR: build/msx/FORMREF.RAW is missing; run 'make formref' first" >&2
    exit 1
}

mkdir -p build/msx
stage=$(mktemp -d -p build/msx formref-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
# A short root-level alias makes File Manager navigation deterministic. The
# payload remains byte-for-byte identical to the shipped FormRef application.
cp build/msx/FORMREF.RAW "$stage/card/A.APP"
tools/build_msx_img.sh "$stage/card" "$stage/formref.img"

export GEMBENCH_FORMREF_OUTPUT="$PWD/build/msx/formref-openmsx.txt"
export GEMBENCH_FORMREF_FOCUS_SCREENSHOT="$PWD/build/msx/formref-focus.png"
export GEMBENCH_FORMREF_FINAL_SCREENSHOT="$PWD/build/msx/formref-final.png"
export MSX_UNAPI=0
export MSX_MOUSE=0
export MSX_SCRIPT=debug/formref_openmsx.tcl
tools/run_msx.sh "$stage/formref.img"

sed -n '1,40p' "$GEMBENCH_FORMREF_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_FORMREF_OUTPUT"
