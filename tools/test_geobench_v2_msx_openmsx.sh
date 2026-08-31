#!/usr/bin/env bash
# Exercise GBAP v4 success and pre-entry transactional rejection on real MSX2.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make geobench-msx' first" >&2
    exit 1
}
for path in build/universal/ABIPROBE.APP build/msx/GBAPV4.RAW \
            build/universal-obj/abiprobe/app.noi; do
    [ -s "$path" ] || {
        echo "ERROR: Gate-2 artifact $path is missing; run 'make geobench-msx'" >&2
        exit 1
    }
done
python3 tools/test_geobench_v2_msx_gate.py \
    --staged QA/MSX/CARD/GBENCH/ABIPROBE.APP

export GEMBENCH_M5_K_POLL="0x$(awk '$1 == "K_POLL" { value=$2; sub(/^#/, "", value); print value; exit }' build/msx/gbkernm7.sym)"
export GEMBENCH_M5_MAIN="$(awk '$2 == "_main" { print $3; exit }' build/universal-obj/abiprobe/app.noi)"
export GEMBENCH_M5_ENTRY="$(awk '$2 == "_start" { print $3; exit }' build/universal-obj/abiprobe/app.noi)"
export GEMBENCH_M5_PAGES="$(python3 -c 'import pathlib,sys; sys.path.insert(0,"tools"); from embed_app_icon import parse_manifest; print(parse_manifest(pathlib.Path("build/universal/ABIPROBE.APP").read_bytes())["minimum_pages"])')"
export GEMBENCH_M5_BAD_PREENTRY=1
export MSX_UNAPI=0
export MSX_MOUSE=0
export MSX_HEADLESS=1
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/m5_gbap3_openmsx.tcl

stage=$(mktemp -d -p build/msx v2-gbap4-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

for mode in good bad; do
    mkdir -p "$stage/$mode/card"
    cp -a QA/MSX/CARD/. "$stage/$mode/card/"
    rm -f -- "$stage/$mode/card/UNAPINET.COM" "$stage/$mode/card/UNAPI.TXT"
    sed -i 's/^SAVERTIME=.*/SAVERTIME=0/' "$stage/$mode/card/GEOBENCH.CFG"
    printf 'GBMSX\r\n' > "$stage/$mode/card/AUTOEXEC.BAT"
    cp build/universal/ABIPROBE.APP "$stage/$mode/card/GBENCH/FILEMGR.APP"
done

# Flip one code byte while leaving every header, bound, and entry intact. This
# drives the complete assembly validator through its CRC path; it must reject
# before _start and release the pending owner/page.
python3 -c 'from pathlib import Path; p=Path(__import__("sys").argv[1]); d=bytearray(p.read_bytes()); d[-1] ^= 1; p.write_bytes(d)' \
    "$stage/bad/card/GBENCH/FILEMGR.APP"

for mode in good bad; do
    tools/build_msx_img.sh "$stage/$mode/card" "$stage/$mode/v2-$mode.img"
    export GEMBENCH_M5_MODE="$mode"
    export GEMBENCH_M5_OUTPUT="$PWD/build/msx/v2-gbap4-$mode.txt"
    tools/run_msx.sh "$stage/$mode/v2-$mode.img"
    sed -n '1,20p' "$GEMBENCH_M5_OUTPUT"
    grep -qx 'STATUS=PASS' "$GEMBENCH_M5_OUTPUT"
done
