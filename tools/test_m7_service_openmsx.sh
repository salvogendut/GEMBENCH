#!/usr/bin/env bash
# Exercise Architecture M7 shared-service lifecycle on the real MSX target.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make geobench-msx' first" >&2
    exit 1
}
for image in FAILSVC SVCTSTA SVCTSTB SVCTSTC SVCTSTD NETSVC; do
    [ -s "build/msx/$image.RAW" ] || {
        echo "ERROR: build/msx/$image.RAW is missing" >&2
        exit 1
    }
done

stage=$(mktemp -d -p build/msx m7-service-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir -p "$stage/card/GBENCH"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
sed -i 's/^SAVERTIME=.*/SAVERTIME=0/' "$stage/card/GEOBENCH.CFG"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp build/msx/SVCTSTA.RAW "$stage/card/GBENCH/FILEMGR.APP"
cp build/msx/SVCTSTB.RAW "$stage/card/GBENCH/SVCTSTB.APP"
cp build/msx/SVCTSTC.RAW "$stage/card/GBENCH/SVCTSTC.APP"
cp build/msx/SVCTSTD.RAW "$stage/card/GBENCH/SVCTSTD.APP"
cp build/msx/FAILSVC.RAW "$stage/card/GBENCH/FAILSVC.APP"
cp build/msx/NETSVC.RAW "$stage/card/GBENCH/NETSVC.APP"
tools/build_msx_img.sh "$stage/card" "$stage/m7-service.img"

export GEMBENCH_M7_SERVICE_OUTPUT="$PWD/build/msx/m7-service-openmsx.txt"
export GEMBENCH_M7_K_POLL="0x$(awk '$1 == "K_POLL" { value=$2; sub(/^#/, "", value); print value; exit }' build/msx/gbkernm7.sym)"
export MSX_UNAPI=0
export MSX_MOUSE=0
export MSX_HEADLESS=1
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/m7_service_openmsx.tcl
tools/run_msx.sh "$stage/m7-service.img"

sed -n '1,80p' "$GEMBENCH_M7_SERVICE_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_M7_SERVICE_OUTPUT"
