#!/usr/bin/env python3
"""mkpcwdsk.py - build an Amstrad PCW EXTENDED .DSK floppy image (#331).

Produces the exact container the 1985 emulator (and real hardware via
SAMdisk) expects: EXTENDED CPC DSK, 256-byte Disk-Info, per-track
Track-Info headers with data rate 0x02 / recording mode 0x02 (CP/M+
refuses to write without those), sectors in the PCW skew order
{1,6,2,7,3,8,4,9,5}, filler 0xE5.

Geometry:
  cf2    3" SS DD  40 tracks x 1 side  x 9 x 512 = 180K  (boots in every PCW)
  cf2dd  3" DS DD  80 tracks x 2 sides x 9 x 512 = 720K

Boot layout (GEOBENCH.DSK): the PCW has no ROM - the printer-MCU
bootstrap loads track 0 / sector R=1 (512 bytes) to 0xF000, requires
the 8-bit sum of the whole sector to be 0xFF, and jumps to 0xF010
(past the 16-byte disc spec).  --boot installs kernel/pcwboot.bin
there; --sys writes a raw system image on the sectors after it
(T0/R2..R9, then whole reserved tracks).  The loader parameters are
patched into the spare disc-spec bytes the boot sector reads back:

  spec[10]    payload sector count
  spec[11]    load address high byte
  spec[12:14] entry address (little-endian)
  spec[15]    checksum filler so sum(sector) % 256 == 0xFF

spec[5] (OFF, reserved tracks) is raised to cover the system image so
the CP/M filesystem area never overlaps it.

Usage:
  mkpcwdsk.py OUT.dsk [--type cf2|cf2dd]
              [--boot BOOT.BIN --sys SYS.BIN --load 0x1000 --entry 0x1000]
  mkpcwdsk.py COMPANION.dsk            # plain formatted data disc
"""

import argparse
import sys

SKEW = [1, 6, 2, 7, 3, 8, 4, 9, 5]
SPT = 9
SEC_SIZE = 512
N_CODE = 2                       # 128 << 2 = 512
TRACK_SIZE = 256 + SPT * SEC_SIZE  # 4864


def build_spec(is_dd, off):
    """16-byte PCW disc specification (track 0 / sector R=1, offset 0)."""
    return bytearray([
        0x03 if is_dd else 0x00,   # [0] format
        0x81 if is_dd else 0x00,   # [1] sided (bit7 = alternating flag)
        80 if is_dd else 40,       # [2] tracks per side
        SPT,                       # [3] sectors per track
        N_CODE,                    # [4] psh
        off,                       # [5] OFF reserved tracks
        0x04 if is_dd else 0x03,   # [6] BSH
        0x04 if is_dd else 0x02,   # [7] directory blocks
        0x2A,                      # [8] GAP3 read/write
        0x52,                      # [9] GAP3 format
        0, 0, 0, 0, 0, 0,
    ])


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('out')
    ap.add_argument('--type', choices=('cf2', 'cf2dd'), default='cf2')
    ap.add_argument('--boot', help='512-byte-max boot sector binary (org 0xF000)')
    ap.add_argument('--sys', help='raw system image for the reserved tracks')
    ap.add_argument('--load', default='0x1000',
                    help='system image load address (page-aligned, default 0x1000)')
    ap.add_argument('--entry', default=None,
                    help='system entry address (default = load address)')
    ap.add_argument('--add', action='append', default=[], metavar='FILE[=NAME]',
                    help='add a file to the CP/M filesystem (8.3 name from the '
                         'basename unless =NAME overrides; repeatable)')
    args = ap.parse_args()

    is_dd = args.type == 'cf2dd'
    tracks = 80 if is_dd else 40
    sides = 2 if is_dd else 1

    load = int(args.load, 0)
    entry = int(args.entry, 0) if args.entry else load
    if load & 0xFF:
        sys.exit('mkpcwdsk: --load must be page-aligned (low byte 0)')

    sysimg = b''
    if args.sys:
        with open(args.sys, 'rb') as f:
            sysimg = f.read()
    sys_secs = (len(sysimg) + SEC_SIZE - 1) // SEC_SIZE
    # Sectors available for the image: T0 has 8 (R=2..9 after the boot
    # sector), every further reserved track has 9.
    off = 1 if sys_secs <= 8 else 1 + (sys_secs - 8 + SPT - 1) // SPT
    if off >= tracks - 2:
        sys.exit('mkpcwdsk: system image too large for the disc')

    spec = build_spec(is_dd, off)

    boot = bytearray(SEC_SIZE)
    boot[:] = b'\xE5' * SEC_SIZE
    boot[0:16] = spec
    if args.boot:
        with open(args.boot, 'rb') as f:
            code = f.read()
        if len(code) > SEC_SIZE:
            sys.exit(f'mkpcwdsk: boot sector is {len(code)} bytes (max 512)')
        boot[:len(code)] = code
        boot[5] = off                       # keep OFF in sync
        boot[10] = sys_secs                 # loader params (see header)
        boot[11] = load >> 8
        boot[12] = entry & 0xFF
        boot[13] = entry >> 8
        boot[15] = 0
        boot[15] = (0xFF - sum(boot)) & 0xFF   # MCU bootstrap checksum
        assert sum(boot) & 0xFF == 0xFF
    elif args.sys:
        sys.exit('mkpcwdsk: --sys needs --boot')

    # Flat logical sector map of the whole disc, then serialize with skew.
    nsec = tracks * sides * SPT
    secs = [b'\xE5' * SEC_SIZE] * nsec
    secs[0] = bytes(boot)
    for i in range(sys_secs):
        chunk = sysimg[i * SEC_SIZE:(i + 1) * SEC_SIZE]
        secs[1 + i] = chunk + b'\xE5' * (SEC_SIZE - len(chunk))

    # --- CP/M 2.2 filesystem population (--add) --------------------------
    # Data area = tracks OFF.. as 1K blocks (2K on cf2dd); blocks 0..dirblk-1
    # hold the directory (32-byte entries). One dir entry per 16K extent:
    # user 0, 8.3 name, EX, RC (#80 = full extent), AL[] block numbers.
    if args.add:
        bls = 2048 if is_dd else 1024
        spb = bls // SEC_SIZE                # sectors per block
        dirblk = spec[7]
        nblocks = (tracks * sides - off) * SPT * SEC_SIZE // bls
        if nblocks > 256 and not is_dd:
            sys.exit('mkpcwdsk: unexpected block count')

        def put_lsn(lsn, data):
            """write 512 bytes at data-area logical sector lsn"""
            secs[off * SPT + lsn] = bytes(data) + b'\xE5' * (SEC_SIZE - len(data))

        dirents = []
        next_blk = dirblk                    # first free data block
        for spec_arg in args.add:
            path, _, name = spec_arg.partition('=')
            if not name:
                name = path.rsplit('/', 1)[-1]
            base, _, ext = name.upper().partition('.')
            n83 = (base[:8].ljust(8) + ext[:3].ljust(3)).encode()
            with open(path, 'rb') as f:
                data = f.read()
            data += b'\x1A' * (-len(data) % 128)     # CP/M EOF padding
            recs_total = len(data) // 128
            pos = 0
            ex = 0
            while True:
                recs = min(recs_total - ex * 128, 128)
                al = []
                for _ in range((recs * 128 + bls - 1) // bls):
                    if next_blk >= nblocks:
                        sys.exit(f'mkpcwdsk: disc full adding {name}')
                    blk = next_blk
                    next_blk += 1
                    al.append(blk)
                    chunk = data[pos:pos + bls]
                    pos += len(chunk)
                    for s in range(spb):
                        part = chunk[s * SEC_SIZE:(s + 1) * SEC_SIZE]
                        if part:
                            put_lsn(blk * spb + s, part)
                ent = bytearray(32)
                ent[0] = 0                   # user 0
                ent[1:12] = n83
                ent[12] = ex
                ent[15] = recs
                for i, blk in enumerate(al):
                    if is_dd:                # 16-bit ALs, 8 per extent
                        ent[16 + i * 2] = blk & 0xFF
                        ent[17 + i * 2] = blk >> 8
                    else:
                        ent[16 + i] = blk
                dirents.append(bytes(ent))
                if recs < 128 or ex * 128 + recs >= recs_total:
                    break
                ex += 1
        maxent = dirblk * (bls // 32)
        if len(dirents) > maxent:
            sys.exit('mkpcwdsk: directory full')
        dirdata = b''.join(dirents) + b'\xE5' * 32 * (maxent - len(dirents))
        for s in range(dirblk * spb):
            put_lsn(s, dirdata[s * SEC_SIZE:(s + 1) * SEC_SIZE])
        print(f'  fs: {len(args.add)} files, {len(dirents)} dir entries, '
              f'{next_blk - dirblk}/{nblocks - dirblk} blocks used')

    out = bytearray()
    hdr = bytearray(256)
    hdr[0:34] = b'EXTENDED CPC DSK File\r\nDisk-Info\r\n'
    hdr[0x22:0x22 + 12] = b'mkpcwdsk    '
    hdr[0x30] = tracks
    hdr[0x31] = sides
    for i in range(tracks * sides):
        hdr[0x34 + i] = TRACK_SIZE // 256
    out += hdr

    for t in range(tracks):
        for side in range(sides):
            ti = bytearray(256)
            ti[0:12] = b'Track-Info\r\n'
            ti[0x10] = t
            ti[0x11] = side
            ti[0x12] = 0x02            # data rate 250 kbps
            ti[0x13] = 0x02            # recording mode MFM
            ti[0x14] = N_CODE
            ti[0x15] = SPT
            ti[0x16] = 0x4E            # GAP3
            ti[0x17] = 0xE5            # filler
            for i, r in enumerate(SKEW):
                si = 0x18 + i * 8
                ti[si + 0] = t
                ti[si + 1] = side
                ti[si + 2] = r
                ti[si + 3] = N_CODE
                ti[si + 6] = SEC_SIZE & 0xFF
                ti[si + 7] = SEC_SIZE >> 8
            out += ti
            base = (t * sides + side) * SPT
            for r in SKEW:
                out += secs[base + r - 1]

    with open(args.out, 'wb') as f:
        f.write(out)
    print(f'{args.out}: {args.type} {len(out)} bytes, OFF={off}, '
          f'sys={len(sysimg)}B/{sys_secs} sectors @{load:#06x} entry {entry:#06x}')


if __name__ == '__main__':
    main()
