#!/usr/bin/env python3
"""Write an AMSDOS-headed AUTOEXEC.BAS that runs the GEOBENCH loader.

M4ROM's cold-boot autoexec path loads a tokenized BASIC file. A plain ASCII
RUN"GB line is read but not executed, so the card image needs the same format
Locomotive BASIC writes for:

    10 RUN"GB
"""
import sys


def build(name: str = "AUTOEXEC", ext: str = "BAS") -> bytes:
    # Tokenized Locomotive BASIC:
    # line length, line number 10, RUN token, "GB", line end, program end.
    body = bytes([0x09, 0x00, 0x0A, 0x00, 0xCA, 0x22, 0x47, 0x42, 0x00, 0x00, 0x00])
    header = bytearray(128)
    header[1:9] = name.upper().ljust(8)[:8].encode("ascii")
    header[9:12] = ext.upper().ljust(3)[:3].encode("ascii")
    header[18] = 0                         # file type: BASIC
    header[21] = 0x70
    header[22] = 0x01                       # BASIC program load address
    header[24] = len(body) & 0xFF
    header[25] = (len(body) >> 8) & 0xFF
    header[64] = len(body) & 0xFF
    header[65] = (len(body) >> 8) & 0xFF
    header[66] = (len(body) >> 16) & 0xFF
    checksum = sum(header[:67]) & 0xFFFF
    header[67] = checksum & 0xFF
    header[68] = checksum >> 8
    return bytes(header) + body


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: make_autoexec_bas.py <out.bas>")
    with open(sys.argv[1], "wb") as f:
        f.write(build())


if __name__ == "__main__":
    main()
