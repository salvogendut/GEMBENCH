#!/usr/bin/env bash
# Smoke both mode-specific loaders after the M3 kernel approached the 16 KiB ceiling.
set -euo pipefail
cd "$(dirname "$0")/.."

stage="$(mktemp -d -p build/msx m3-boot-modes.XXXXXX)"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

for mode in 6 7; do
    mkdir "$stage/card-$mode"
    cp -a QA/MSX/CARD/. "$stage/card-$mode/"
    rm -f -- "$stage/card-$mode/UNAPINET.COM" "$stage/card-$mode/UNAPI.TXT"
    sed -i "s/^MSXMODE=.*/MSXMODE=$mode/" "$stage/card-$mode/GEOBENCH.CFG"
    tools/build_msx_img.sh "$stage/card-$mode" "$stage/mode-$mode.img"
    export GEMBENCH_M3_BOOT_OUTPUT="$PWD/build/msx/m3-boot-mode-$mode.txt"
    export GEMBENCH_M3_BOOT_SCREENSHOT="$PWD/build/msx/m3-boot-mode-$mode.png"
    export MSX_UNAPI=0
    export MSX_MOUSE=0
    export SDL_AUDIODRIVER=dummy
    export MSX_SCRIPT=debug/m3_boot_probe.tcl
    tools/run_msx.sh "$stage/mode-$mode.img"
    grep -qx 'NWIN=1' "$GEMBENCH_M3_BOOT_OUTPUT"
    grep -qx 'POOL_TOTAL=25' "$GEMBENCH_M3_BOOT_OUTPUT"
    grep -qx 'SYS_SIZE=32' "$GEMBENCH_M3_BOOT_OUTPUT"
    grep -qx 'SYS_VERSION=4' "$GEMBENCH_M3_BOOT_OUTPUT"
    grep -qx 'DEFER_COUNT=0' "$GEMBENCH_M3_BOOT_OUTPUT"
done

echo "Architecture M3 Screen 6/7 boot smoke: PASS"
