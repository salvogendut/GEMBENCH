#!/usr/bin/env bash
# tools/run_msx.sh - launch the MSX2 target in openMSX (issue #287).
#
# Emulated machine: Philips NMS 8250 (PAL MSX2, 128K RAM / 128K VRAM) with the
# bundled SunriseIDE_Nextor extension (Nextor 2.1.1 kernel ROM) and, by
# default, a 512K RAM expansion - the stock 128K machine leaves only ONE free
# mapper segment after DOS2/Nextor take theirs (measured by GBSPIKE), which
# boots the desktop but allows no extra app windows. Test the stock-RAM story
# with MSX_RAM=stock.
#
# System ROMs are found in ~/.openMSX/share/systemroms (tools/fetch_msx_deps.sh
# sets them up). The disk image defaults to QA/GBMSX.IMG (tools/build_msx_img.sh).
#
# Usage:
#   tools/run_msx.sh [image]                    interactive session
#   MSX_SCRIPT=file.tcl tools/run_msx.sh        drive it from a Tcl script
#   MSX_SHOTS="10 20 30" tools/run_msx.sh       headless: screenshots at those
#                                               emu-time seconds into build/msx/
#                                               (throttle off, exits after last)
#   MSX_RAM=stock tools/run_msx.sh              no 512K expansion
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${1:-QA/GBMSX.IMG}"
MACHINE="${MSX_MACHINE:-Philips_NMS_8250}"
[ -s "$IMG" ] || { echo "ERROR: $IMG not found - run tools/build_msx_img.sh" >&2; exit 1; }

EXT=(-ext SunriseIDE_Nextor)
[ "${MSX_RAM:-512k}" != stock ] && EXT+=(-ext ram512k)

ARGS=(-machine "$MACHINE" "${EXT[@]}" -hda "$IMG")

if [ -n "${MSX_SHOTS:-}" ]; then
    mkdir -p build/msx
    SCRIPT=$(mktemp --suffix=.tcl)
    trap 'rm -f "$SCRIPT"' EXIT
    {
        echo 'set throttle off'
        last=0
        for t in $MSX_SHOTS; do last=$t; done
        for t in $MSX_SHOTS; do
            action="catch { screenshot $PWD/build/msx/msx-t$t.png }"
            [ "$t" = "$last" ] && action="$action ; exit"
            echo "after time $t { $action }"
        done
    } > "$SCRIPT"
    ARGS+=(-script "$SCRIPT")
    echo "headless run: screenshots at ${MSX_SHOTS}s -> build/msx/msx-t*.png"
elif [ -n "${MSX_SCRIPT:-}" ]; then
    ARGS+=(-script "$MSX_SCRIPT")
else
    # Interactive: fast-forward the ~18s Nextor boot, then drop to real 50Hz.
    # The switch is on a WALL-CLOCK timer ("after realtime"), NOT a breakpoint on
    # a kernel address - the kernel grows and any hardcoded k_poll address goes
    # stale, leaving the run stuck at fast-forward (pointer leaps, saver fires in
    # seconds). ~4s of wall-clock throttle-off is well past the boot.
    SCRIPT=$(mktemp --suffix=.tcl)
    trap 'rm -f "$SCRIPT"' EXIT
    printf 'set throttle off\nafter realtime %s { set throttle on }\n' "${MSX_FF:-4}" > "$SCRIPT"
    ARGS+=(-script "$SCRIPT")
fi

exec openmsx "${ARGS[@]}"
