#!/usr/bin/env bash
# tools/build_msx_spike.sh - build the M0 toolchain spike (issue #287) and stage
# a bootable image that autoruns it: assembles tools/gbspike_msx.asm with RASM
# into build/msx/GBSPIKE.COM, stages it under QA/MSX/CARD/DIAG plus AUTOEXEC.BAT, and builds
# QA/MSX/GBMSX.IMG. Verify with:
#   MSX_SHOTS="20 24 28 45" tools/run_msx.sh
# The last screenshot must show the full report (DOS 2, segment counts, mapper
# r/w OK, 250 ticks, GBSPIKE OK) back at the A:\> prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rasm >/dev/null || { echo "ERROR: rasm not on PATH" >&2; exit 1; }

mkdir -p build/msx QA/MSX/CARD
( cd build/msx && rasm "$OLDPWD/tools/gbspike_msx.asm" )
[ -s build/msx/GBSPIKE.COM ] || { echo "ERROR: GBSPIKE.COM not produced" >&2; exit 1; }

mkdir -p QA/MSX/CARD/DIAG
rm -f QA/MSX/CARD/GBSPIKE.COM
cp build/msx/GBSPIKE.COM QA/MSX/CARD/DIAG/
printf 'DIAG\\GBSPIKE\r\n' > QA/MSX/CARD/AUTOEXEC.BAT

bash tools/build_msx_img.sh QA/MSX/CARD QA/MSX/GBMSX.IMG
echo "Spike staged: QA/MSX/GBMSX.IMG autoruns GBSPIKE at boot"
