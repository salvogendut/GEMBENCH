#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 tools/test_gbrdemo_delivery.py
stage="$PWD/build/v1-m2/evidence/msx-delivery"
mkdir -p "$stage"
data=$(awk '$2=="s__DATA" {print $3;exit}' build/universal-obj/ugbrdemo/app.noi)
ready_off=$(awk '$2=="_ready" {print $3;exit}' build/universal-obj/ugbrdemo/main.sym)
states_off=$(awk '$2=="_object_states" {print $3;exit}' build/universal-obj/ugbrdemo/main.sym)
entry=$(awk '$2=="s__CODE" {print $3;exit}' build/universal-obj/ugbrdemo/app.noi)
export GEMBENCH_GBR_CASE=good
export GEMBENCH_GBR_READY=$((data+16#$ready_off))
export GEMBENCH_GBR_STATES=$((data+16#$states_off))
export GEMBENCH_GBR_ENTRY=$((entry))
export GEMBENCH_GBR_OUTPUT="$stage/openmsx-result.txt"
export GEMBENCH_GBR_SCREENSHOT="$stage/openmsx-result.png"
export MSX_UNAPI=0 MSX_MOUSE=0 MSX_HEADLESS=1
export MSX_SCRIPT=debug/universal_gbrdemo_openmsx.tcl
tools/run_msx.sh QA/MSX/GBMSX.IMG
grep -qx 'STATUS=PASS' "$GEMBENCH_GBR_OUTPUT"
printf 'PASS normal MSX Screen 7 GBRDEMO delivery\n'
