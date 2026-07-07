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
    if data[off] == 0xCD:                       # CALL nn (may be an operand byte:
        tgt = data[off+1] | (data[off+2] << 8)  # only in-image non-symbol targets
        if 0x2000 <= tgt < 0x2000 + len(data) and tgt not in syms:
            print(f'PHASE ERROR: call at {0x2000+off:#06x} -> {tgt:#06x} matches no symbol')
            bad += 1
sys.exit(1 if bad else 0)
EOF

printf 'CP/M FS READ OK\r\n' > build/HELLO.TXT
python3 -c "open('build/BIGTEST.BIN','wb').write(bytes((i*7+13)&255 for i in range(20000)))"
python3 tools/mkpcwdsk.py build/pcwspike.dsk \
    --boot build/pcwboot.bin --sys build/pcwspike.bin --load 0x2000 \
    --add build/HELLO.TXT --add assets/WELCOME.TXT --add build/DEFAULT.FNT \
    --add build/BIGTEST.BIN

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$E1985" \
    --config debug/1985-pcw.conf \
    --disk-a build/pcwspike.dsk \
    --unthrottled \
    --paste-event "3200:hello pcw 42" \
    --screenshot-at 3600:build/pcwspike.ppm \
    --exit-after 3700

python3 - <<'EOF'
from PIL import Image
Image.open('build/pcwspike.ppm').save('build/pcwspike.png')
print('build/pcwspike.png written')
EOF

# --- host-side verification of the write path (#331 Phase 5b) -----------
# The emulator wrote back build/pcwspike.dsk; extract the spike's outputs
# from the CP/M fs and byte-compare.
python3 - <<'EOF'
import sys
data = open('build/pcwspike.dsk','rb').read()
SPT, SS = 9, 512
tracks = data[0x30]
tsize = 256 + SPT*SS
def sector(t, r):
    off = 256 + t*tsize
    for i in range(SPT):
        si = off + 0x18 + i*8
        if data[si+2] == r:
            return data[off+256+i*SS: off+256+(i+1)*SS]
    raise KeyError((t, r))
spec = sector(0, 1)
OFF, dirblk = spec[5], spec[7]
def lsn(n):
    return sector(OFF + n//SPT, 1 + n%SPT)
dirdata = b''.join(lsn(i) for i in range(dirblk*2))
def extract(n83):
    exts = {}
    for e in range(0, len(dirdata), 32):
        ent = dirdata[e:e+32]
        if ent[0] != 0: continue
        if bytes(c & 0x7F for c in ent[1:12]) != n83: continue
        exts[ent[12] & 0x1F] = ent
    if not exts: return None
    out = bytearray()
    for ex in sorted(exts):
        ent = exts[ex]
        recs = ent[15]
        n = recs * 128
        for al in ent[16:32]:
            if al == 0 or n <= 0: break
            blk = lsn(al*2) + lsn(al*2+1)
            take = min(1024, n)
            out += blk[:take]
            n -= take
    return bytes(out)
big = open('build/BIGTEST.BIN','rb').read()
save = extract(b'PCWSAVE TST')
copy = extract(b'COPYOUT BIN')
dele = extract(b'PCWDEL  TST')
ok = True
if not save or not save.startswith(b'PCW write path OK'):
    print('FAIL: PCWSAVE.TST wrong/missing'); ok = False
if dele is not None:
    print('FAIL: PCWDEL.TST still present'); ok = False
if not copy or copy[:len(big)] != big:
    print(f'FAIL: COPYOUT.BIN mismatch (got {len(copy) if copy else 0})'); ok = False
if ok:
    print(f'fs write verification OK: save + delete + {len(big)}-byte chunked copy')
sys.exit(0 if ok else 1)
EOF
