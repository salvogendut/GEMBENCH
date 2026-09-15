#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

stage="${GEMBENCH_GBR_MSX_STAGE:-build/v1-m2/gbrdemo-msx}"
[ -s "$stage/manifest.json" ] || {
    echo "ERROR: missing private fixtures; run the milestone media target" >&2
    exit 1
}
data=$(awk '$2=="s__DATA" {print $3;exit}' build/universal-obj/ugbrdemo/app.noi)
ready_off=$(awk '$2=="_ready" {print $3;exit}' build/universal-obj/ugbrdemo/main.sym)
states_off=$(awk '$2=="_object_states" {print $3;exit}' build/universal-obj/ugbrdemo/main.sym)
entry=$(awk '$2=="s__CODE" {print $3;exit}' build/universal-obj/ugbrdemo/app.noi)
export GEMBENCH_GBR_READY=$((data+16#$ready_off))
export GEMBENCH_GBR_STATES=$((data+16#$states_off))
export GEMBENCH_GBR_ENTRY=$((entry))
export MSX_UNAPI=0 MSX_MOUSE=0 MSX_HEADLESS=1
export MSX_SCRIPT=debug/universal_gbrdemo_openmsx.tcl

for mode in 6 7; do
    for case in good checksum truncated oversized; do
        export GEMBENCH_GBR_CASE=$case
        export GEMBENCH_GBR_OUTPUT="$PWD/$stage/mode${mode}-${case}/result.txt"
        export GEMBENCH_GBR_SCREENSHOT="$PWD/$stage/mode${mode}-${case}/result.png"
        tools/run_msx.sh "$stage/mode${mode}-${case}/filesystem.img"
        grep -qx 'STATUS=PASS' "$GEMBENCH_GBR_OUTPUT"
        printf 'PASS openMSX Screen %s GBRDEMO %s\n' "$mode" "$case"
    done
done
