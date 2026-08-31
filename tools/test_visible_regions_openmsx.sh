#!/usr/bin/env bash
# Compatibility entry point for the global MSX2 visibility compositor tests.
set -euo pipefail
cd "$(dirname "$0")/.."

# Architecture M9 supersedes the Desktop-only GB_REGIONS experiment. Exercise
# both a partially/fully covered background Clock and PAINT's independent pane
# moves/focus changes; neither application opts into compositor-specific code.
bash tools/test_multi_event_openmsx.sh
bash tools/test_m2_paint_openmsx.sh

{
    printf 'STATUS=PASS\n'
    printf 'CLOCK_TRACE=build/msx/multi-event-openmsx.txt\n'
    printf 'PAINT_TRACE=build/msx/m2-paint-openmsx.txt\n'
} > build/msx/visible-regions-openmsx.txt

sed -n '1,20p' build/msx/visible-regions-openmsx.txt
