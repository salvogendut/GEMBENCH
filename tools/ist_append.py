#!/usr/bin/env python3
"""ist_append - append icon .asm bitmaps to an existing GEOBENCH .IST set.

packicons.py builds build/DEFAULT.IST fresh from lib/icon_*.asm every build, so a
new lib/icon_*.asm just slots in there. The hand-tuned card sets in
assets/iconsets/*.IST are tracked BINARY artifacts (edited with iconedit.py, no
.asm source), so a new desktop icon must be appended to them too or it renders
out of bounds. This does that: it bumps the count, shifts every existing absolute
offset by the grown directory, and appends the new icon(s) as the highest slots.

    tools/ist_append.py <set.IST> <icon.asm> [icon.asm ...]

See tools/packicons.py for the .IST format (16-byte header, count*4 directory of
<offset:u16, w:u8, h:u8>, then the bitmaps).
"""
import sys, re, struct

HDR = 16

def parse_icon(path):
    w = h = None
    data = bytearray()
    for line in open(path):
        s = line.strip()
        m = re.match(r'\w+_w\s+equ\s+(\d+)', s)
        if m: w = int(m.group(1))
        m = re.match(r'\w+_h\s+equ\s+(\d+)', s)
        if m: h = int(m.group(1))
        if s.startswith('db'):
            data += bytes(int(b, 16) for b in re.findall(r'#([0-9A-Fa-f]{2})', s))
    if w is None or h is None:
        sys.exit(f"{path}: missing _w/_h constants")
    if len(data) != w * h:
        sys.exit(f"{path}: {len(data)} bytes (expected {w}*{h}={w*h})")
    return w, h, bytes(data)

def main(argv):
    if len(argv) < 3:
        sys.exit("usage: ist_append.py <set.IST> <icon.asm> ...")
    ist, asms = argv[1], argv[2:]
    raw = open(ist, 'rb').read()
    if raw[0:4] != b'GBIS':
        sys.exit(f"{ist}: not a GBIS icon set")
    count = raw[5]
    entries = [struct.unpack_from('<HBB', raw, HDR + i * 4) for i in range(count)]
    blob = raw[HDR + count * 4:]

    new = [parse_icon(a) for a in asms]
    k = len(new)
    shift = 4 * k                                 # the directory grows by 4 bytes per added icon

    newdir = bytearray()
    for off, w, h in entries:
        newdir += struct.pack('<HBB', off + shift, w, h)
    nextoff = HDR + (count + k) * 4 + len(blob)    # new bitmaps land after the shifted blob
    newblob = bytearray()
    for w, h, data in new:
        newdir += struct.pack('<HBB', nextoff, w, h)
        newblob += data
        nextoff += len(data)

    header = bytearray(raw[:HDR])
    header[5] = count + k
    with open(ist, 'wb') as f:
        f.write(bytes(header) + bytes(newdir) + blob + bytes(newblob))
    print(f"{ist}: {count} -> {count + k} icons (+{k}: {', '.join(asms)})")

if __name__ == '__main__':
    main(sys.argv)
