#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

stage="${GEMBENCH_FORMREF_MSX_STAGE:-build/v1-m2/formref-msx}"
[ -s "$stage/manifest.json" ] || {
    echo "ERROR: missing private fixtures; run make geobench-v1-m2-formref-msx-media" >&2
    exit 1
}

data=$(awk '$2=="s__DATA" {print $3;exit}' build/universal-obj/uformref/app.noi)
entry=$(awk '$2=="s__CODE" {print $3;exit}' build/universal-obj/uformref/app.noi)
focus_off=$(awk '$2=="_focus" {print $3;exit}' build/universal-obj/uformref/main.sym)
ready_off=$(awk '$2=="_resource_ready" {print $3;exit}' build/universal-obj/uformref/main.sym)
states_off=$(awk '$2=="_form_states" {print $3;exit}' build/universal-obj/uformref/main.sym)
modal=$(awk '$2=="_gb_form_modal_run" {print $3;exit}' build/universal-obj/uformref/app.noi)
export GEMBENCH_FORM_FOCUS=$((data+16#$focus_off))
export GEMBENCH_FORM_READY=$((data+16#$ready_off))
export GEMBENCH_FORM_STATES=$((data+16#$states_off))
export GEMBENCH_FORM_MODAL=$((modal))
export GEMBENCH_GBR_ENTRY=$((entry))
export MSX_UNAPI=0 MSX_MOUSE=0 MSX_HEADLESS=1
export MSX_SCRIPT=debug/universal_formref_openmsx.tcl

for mode in 6 7; do
    result="$stage/mode${mode}/openmsx-result.txt"
    screenshot="$stage/mode${mode}/openmsx-result.png"
    before=$(sha256sum "$stage/mode${mode}/filesystem.img" | cut -d' ' -f1)
    export GEMBENCH_GBR_OUTPUT="$PWD/$result"
    export GEMBENCH_GBR_SCREENSHOT="$PWD/$screenshot"
    tools/run_msx.sh "$stage/mode${mode}/filesystem.img"
    grep -qx 'STATUS=PASS' "$result"
    after=$(sha256sum "$stage/mode${mode}/filesystem.img" | cut -d' ' -f1)
    [ "$before" = "$after" ] || {
        echo "ERROR: openMSX changed the private Screen $mode source image" >&2
        exit 1
    }
    printf 'PASS openMSX Screen %s FormRef launch/form/input/cleanup\n' "$mode"
done
