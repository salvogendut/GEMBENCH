#!/usr/bin/env bash
# Run against a built MSX reference card; the Desk harness copies its media.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${MSX_TEST_MODE:-7}"
case "$mode" in
    6) symbols=build/msx/gbkernm.sym ;;
    7) symbols=build/msx/gbkernm7.sym ;;
    *) echo 'MSX_TEST_MODE must be 6 or 7' >&2; exit 1 ;;
esac
[ -s "$symbols" ]
export GEMBENCH_CLOCK_KERNEL_SYMBOLS="$PWD/$symbols"
export GEMBENCH_CLOCK_REFERENCE_OUTPUT="$PWD/build/msx/clock-runtime-$mode-openmsx.txt"
export GEOBENCH_ACCESSORY_SCRIPT=debug/clock_runtime_openmsx.tcl
bash tools/test_desk_accessories_openmsx.sh
sed -n '1,10p' "$GEMBENCH_CLOCK_REFERENCE_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_CLOCK_REFERENCE_OUTPUT"
