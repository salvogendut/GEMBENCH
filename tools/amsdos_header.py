#!/usr/bin/env python3
"""Prepend a 128-byte AMSDOS header to a raw binary.

AMSDOS (and UniDOS) need the header to know a file's load/exec address when it
is RUN"d. RASM's DSK save writes a headed file inside an EDSK, but for files we
drop onto a FAT image (the Cyboard/SymbiFace IDE volume) with mtools we have to
build the header ourselves.

Usage: amsdos_header.py <raw_in> <bin_out> <NAME> <EXT> <load_addr>
       amsdos_header.py build/GEOBENCH.RAW build/GEOBENCH.BIN GEOBENCH BIN 0x4000
The exec address is taken equal to the load address.
"""
import sys


def build(raw: bytes, name: str, ext: str, load: int) -> bytes:
    h = bytearray(128)
    h[1:9] = name.upper().ljust(8)[:8].encode("ascii")
    h[9:12] = ext.upper().ljust(3)[:3].encode("ascii")
    h[18] = 2                                  # file type: unprotected binary
    ln = len(raw)
    h[21] = load & 0xFF
    h[22] = (load >> 8) & 0xFF                  # load address
    h[24] = ln & 0xFF
    h[25] = (ln >> 8) & 0xFF                    # logical length
    h[26] = load & 0xFF
    h[27] = (load >> 8) & 0xFF                  # entry / exec address
    h[64] = ln & 0xFF
    h[65] = (ln >> 8) & 0xFF
    h[66] = (ln >> 16) & 0xFF                   # 24-bit file length
    chk = sum(h[0:67]) & 0xFFFF                 # checksum of bytes 0..66
    h[67] = chk & 0xFF
    h[68] = (chk >> 8) & 0xFF
    return bytes(h) + raw


def main() -> None:
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    raw_in, bin_out, name, ext, load_s = sys.argv[1:6]
    load = int(load_s, 0)
    with open(raw_in, "rb") as f:
        raw = f.read()
    with open(bin_out, "wb") as f:
        f.write(build(raw, name, ext, load))
    print(f"{bin_out}: {len(raw)} bytes, load/exec {load:#06x}")


if __name__ == "__main__":
    main()
