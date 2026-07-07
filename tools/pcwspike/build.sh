#!/usr/bin/env bash
# build.sh - assemble + run the PCW boot/video spike (#331 Phase 1).
#
# Boots a GEOBENCH-format disc in the 1985 emulator headless and
# screenshots the CGA test pattern:
#   bash tools/pcwspike/build.sh
# Outputs: build/pcwspike.dsk, build/pcwspike.png
set -euo pipefail

cd "$(dirname "$0")/../.."
RASM="${RASM:-rasm}"
E1985="${E1985:-$HOME/Dev/1985/1985}"
mkdir -p build

python3 tools/genfont.py build/DEFAULT.FNT   # 6x8 font for the text test

# rasm exits 0 on assembly errors - remove outputs first, assert after
rm -f build/pcwboot.bin build/pcwspike.bin
"$RASM" kernel/pcwboot.asm
[ -s build/pcwboot.bin ] || { echo "ERROR: pcwboot.bin not produced" >&2; exit 1; }
"$RASM" tools/pcwspike/spike.asm -s -o build/pcwspike
[ -s build/pcwspike.bin ] || { echo "ERROR: pcwspike.bin not produced" >&2; exit 1; }

# RASM has been caught emitting phase-inconsistent binaries for some source
# layouts (#331: a CALL kept a stale pass-1 target while the data refs around
# it were final - the spike then crashed 3 bytes into nowhere). Cross-check
# every CALL in the code region against the symbol table and refuse to ship
# a broken image.
python3 - build/pcwspike.bin build/pcwspike.sym <<'EOF'
import sys
binf, symf = sys.argv[1], sys.argv[2]
data = open(binf, 'rb').read()
syms = {}
for line in open(symf):
    parts = line.split()
    if len(parts) >= 2 and parts[1].startswith('#'):
        syms[int(parts[1][1:], 16)] = parts[0]
code_end = min((a for a in syms if syms[a] in ('BD_TILE', 'GLYPH')), default=len(data)+0x2000) - 0x2000
bad = 0
for off in range(code_end - 2):
    if data[off] == 0xCD:                       # CALL nn
        tgt = data[off+1] | (data[off+2] << 8)
        if 0x1000 <= tgt < 0x2000 + len(data) and tgt not in syms:
            print(f'PHASE ERROR: call at {0x1000+off:#06x} -> {tgt:#06x} matches no symbol')
            bad += 1
sys.exit(1 if bad else 0)
EOF

printf 'CP/M FS READ OK\r\n' > build/HELLO.TXT
python3 tools/mkpcwdsk.py build/pcwspike.dsk \
    --boot build/pcwboot.bin --sys build/pcwspike.bin --load 0x2000 \
    --add build/HELLO.TXT --add assets/WELCOME.TXT --add build/DEFAULT.FNT

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$E1985" \
    --config debug/1985-pcw.conf \
    --disk-a build/pcwspike.dsk \
    --paste-event "700:hello pcw 42" \
    --screenshot-at 1000:build/pcwspike.ppm \
    --exit-after 1050

python3 - <<'EOF'
from PIL import Image
Image.open('build/pcwspike.ppm').save('build/pcwspike.png')
print('build/pcwspike.png written')
EOF
