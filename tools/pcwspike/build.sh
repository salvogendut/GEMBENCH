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
addrs = sorted(syms)
import bisect
for off in range(code_end - 2):
    if data[off] == 0xCD:                       # CALL nn - but 0xCD also appears
        tgt = data[off+1] | (data[off+2] << 8)  # as jp/jr operand bytes, so only
        if not (0x2000 <= tgt < 0x2000 + len(data)) or tgt in syms:
            continue                            # flag SMALL drifts off a real
        i = bisect.bisect_left(addrs, tgt)      # symbol (the actual RASM phase-
        near = min((abs(addrs[j]-tgt) for j in (i-1, i) if 0 <= j < len(addrs)),
                   default=99)                  # bug signature); random operand
        if near <= 8:                           # bytes point nowhere near one
            print(f'PHASE ERROR: call at {0x2000+off:#06x} -> {tgt:#06x} '
                  f'is {near} bytes off a symbol')
            bad += 1
sys.exit(1 if bad else 0)
EOF

printf 'CP/M FS READ OK\r\n' > build/HELLO.TXT
python3 -c "open('build/BIGTEST.BIN','wb').write(bytes((i*7+13)&255 for i in range(20000)))"
python3 -c "open('build/DDPAD.BIN','wb').write(bytes((i*11+5)&255 for i in range(480*1024)))"
python3 tools/mkpcwdsk.py build/pcwspike.dsk \
    --boot build/pcwboot.bin --sys build/pcwspike.bin --load 0x2000 \
    --add build/HELLO.TXT --add assets/WELCOME.TXT --add build/DEFAULT.FNT \
    --add build/BIGTEST.BIN
printf 'A file that lives on drive B\r\n' > build/BFILE.TXT
python3 tools/mkpcwdsk.py build/pcwb.dsk \
    --add build/BFILE.TXT --add build/BIGTEST.BIN
python3 tools/mkpcwdsk.py build/pcwbdd.dsk --type cf2dd \
    --add build/BFILE.TXT --add build/DDPAD.BIN --add build/BIGTEST.BIN
sed 's/ext_second_drive        = false/ext_second_drive        = true/' \
    debug/1985-pcw.conf > build/1985-pcw-2drive.conf

# Real drive-B mechanisms differ: an 8512's B is an 80-track CF2DD that
# double-steps CF2 media, but a Gotek (or a 40-track bolt-on B) maps
# tracks 1:1 (#331 real-HW "Companion shows empty"). Pad a copy of the B
# disc to 43 tracks: 1985's AUTO heuristic (track_count > 42) then serves
# it 1:1 - a headless stand-in for the Gotek. pcwfdc_detect must measure
# BOTH mechanisms (#0F02) and the directory must list on both (#0F03).
python3 - <<'EOF'
d = bytearray(open('build/pcwb.dsk','rb').read())
ntrk, hi = d[0x30], d[0x34]
tsize = hi*256
blk = d[256+(ntrk-1)*tsize : 256+ntrk*tsize]
for t in range(ntrk, 43):
    nb = bytearray(blk)
    nb[0x10] = t                 # Track-Info track number
    for i in range(9):
        nb[0x18+i*8] = t         # each sector header's C
    d += nb
    d[0x34+t] = hi
d[0x30] = 43
open('build/pcwb43.dsk','wb').write(d)
EOF
cp build/pcwspike.dsk build/pcwspike43.dsk    # pristine A for the second run
cp build/pcwspike.dsk build/pcwspikedd-a.dsk  # pristine A for the CF2DD run

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$E1985" \
    --config build/1985-pcw-2drive.conf \
    --disk-a build/pcwspike43.dsk \
    --disk-b build/pcwb43.dsk \
    --unthrottled \
    --save-sna-at 3600:build/pcwspike43.sna \
    --exit-after 3700

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$E1985" \
    --config build/1985-pcw-2drive.conf \
    --disk-a build/pcwspike.dsk \
    --disk-b build/pcwb.dsk \
    --unthrottled \
    --paste-event "3200:hello pcw 42" \
    --screenshot-at 3600:build/pcwspike.ppm \
    --save-sna-at 3600:build/pcwspike.sna \
    --exit-after 3700

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$E1985" \
    --config build/1985-pcw-2drive.conf \
    --disk-a build/pcwspikedd-a.dsk \
    --disk-b build/pcwbdd.dsk \
    --unthrottled \
    --save-sna-at 3600:build/pcwspikedd.sna \
    --exit-after 3700

# Drive-B stepping: assert both measured modes + both stage verdicts.
python3 - <<'EOF'
import sys
def cell(path, addr):
    return open(path, 'rb').read()[256 + addr]
ok = True
for path, want, label in (('build/pcwspike.sna',   1, 'CF2DD B (double-step)'),
                          ('build/pcwspike43.sna', 0, 'Gotek-like B (1:1)'),
                          ('build/pcwspikedd.sna', 0, 'native CF2DD B (1:1)')):
    dbl, verdict = cell(path, 0x0F02), cell(path, 0x0F03)
    good = dbl == want and verdict == 0xB0
    print(('OK  ' if good else 'FAIL') +
          f' {label}: dbl={dbl} (want {want}) stage={verdict:#04x} (want 0xb0)')
    ok = ok and good
sys.exit(0 if ok else 1)
EOF

python3 - <<'EOF'
from PIL import Image
Image.open('build/pcwspike.ppm').save('build/pcwspike.png')
print('build/pcwspike.png written')
EOF

# --- host-side verification of the write path (#331 Phase 5b) -----------
# Extract the spike's outputs from both CF2 and CF2DD CP/M filesystems. The
# pre-filled CF2DD image forces COPYOUT.BIN above allocation block 255.
python3 - <<'EOF'
import sys
SPT = 9

def filesystem(path):
    data = open(path, 'rb').read()
    tracks, sides = data[0x30], data[0x31]
    sectors = {}
    pos = 256
    for ti in range(tracks * sides):
        tlen = data[0x34 + ti] * 256
        track = data[pos:pos + tlen]
        payload = 256
        for i in range(track[0x15]):
            si = 0x18 + i * 8
            size = track[si + 6] | (track[si + 7] << 8)
            if not size:
                size = 128 << track[si + 3]
            key = (track[si], track[si + 1], track[si + 2])
            sectors[key] = track[payload:payload + size]
            payload += size
        pos += tlen

    spec = sectors[(0, 0, 1)]
    off, dirblk = spec[5], spec[7]
    bls = 128 << spec[6]
    spb = bls // 512
    al16 = spec[6] == 4

    def lsn(n):
        logical_track = off + n // SPT
        side = logical_track & 1 if sides == 2 else 0
        track = logical_track >> 1 if sides == 2 else logical_track
        return sectors[(track, side, 1 + n % SPT)]

    directory = b''.join(lsn(i) for i in range(dirblk * spb))

    def extract(n83):
        exts = {}
        for e in range(0, len(directory), 32):
            ent = directory[e:e + 32]
            if ent[0] != 0:
                continue
            if bytes(c & 0x7F for c in ent[1:12]) == n83:
                exts[ent[12] & 0x1F] = ent
        if not exts:
            return None, []
        out = bytearray()
        used = []
        for ex in sorted(exts):
            ent = exts[ex]
            left = ent[15] * 128
            if al16:
                blocks = [ent[i] | (ent[i + 1] << 8)
                          for i in range(16, 32, 2)]
            else:
                blocks = list(ent[16:32])
            for block in blocks:
                if not block or left <= 0:
                    break
                used.append(block)
                payload = b''.join(lsn(block * spb + s)
                                   for s in range(spb))
                take = min(bls, left)
                out += payload[:take]
                left -= take
        return bytes(out), used

    return extract, 'CF2DD' if al16 else 'CF2'

big = open('build/BIGTEST.BIN', 'rb').read()
ok = True
for path, need_high in (('build/pcwspike.dsk', False),
                        ('build/pcwbdd.dsk', True)):
    extract, geometry = filesystem(path)
    save, _ = extract(b'PCWSAVE TST')
    copy, blocks = extract(b'COPYOUT BIN')
    dele, _ = extract(b'PCWDEL  TST')
    if not save or not save.startswith(b'PCW write path OK'):
        print(f'FAIL: {path}: PCWSAVE.TST wrong/missing'); ok = False
    if dele is not None:
        print(f'FAIL: {path}: PCWDEL.TST still present'); ok = False
    if not copy or copy[:len(big)] != big:
        print(f'FAIL: {path}: COPYOUT.BIN mismatch '
              f'(got {len(copy) if copy else 0})'); ok = False
    if need_high and (not blocks or max(blocks) <= 255):
        print(f'FAIL: {path}: did not allocate above block 255'); ok = False
    if ok:
        high = f', highest block {max(blocks)}' if blocks else ''
        print(f'{geometry} write verification OK: save + delete + '
              f'{len(big)}-byte chunked copy{high}')
sys.exit(0 if ok else 1)
EOF
