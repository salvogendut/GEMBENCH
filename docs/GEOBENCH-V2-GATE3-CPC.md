# GEOBENCH-2 Gate 3: CPC reference runtime

Issue 54-A restores a 512 KiB Amstrad CPC target against the compile-once
GEOBENCH-2 ABI. It is an experimental reference port; MSX2 remains the default
and production distribution, and PCW remains a later gate.

## Runtime boundary

The CPC kernel retains the fixed jump table at `0x8000` and publishes the
48-byte sysinfo v6 record from cooperative low RAM. It reports CPC Mode 1,
320x200 pixels, 80x200 logical columns/lines, four semantic pens, and the common
`0x4000..0x7EFF` application range. A 512 KiB machine exposes 27 usable 16 KiB
pages; public page and window handles carry nonzero reuse generations.

The strict 1201-byte GBAP v4 gate is loaded into the temporary `0x2200`
workspace before every application admission. It checks package identity,
capabilities, bounds, and CRC before `_start`; failure returns through the
shared page rollback. The small managed-window drag implementation is loaded on
demand into the separate PAGE_DATA module window, preserving the CPC kernel's
guarded 256-byte stack reserve.

Mode 1 stores the canonical two-bit semantic-pen rectangles directly. The CPC
line service translates the common pixel-coordinate mailbox to firmware
coordinates synchronously. Pointer input is normalized through the inherited
poll record.

## Media

`make cpc` produces:

- `QA/CPC/Floppies/GEOBENCH.DSK`, an AMSDOS DATA disk using the Albireo kernel's
  floppy fallback;
- `QA/CPC/CARD`, a shared card tree with `GBM4.BIN`, `GBALB.BIN`, and a tiny
  `M4DETECT.BIN` selected by `GB.BAS`;
- `QA/CPC/GEOBENCH.IMG`, an ignored 32 MiB FAT16 image of that card tree.

Desktop and File Manager are currently native CPC bootstrap shells. ABI Probe,
Clock, and Calculator are copied from `build/universal` with no relinking or
rewriting. The media audit reconstructs files from the CPC CP/M directory and
verifies their SHA-256 identity against both the universal build and MSX2 card.

## Verification

```sh
make cpc-check
make cpc-1984
```

The first command validates the package stage, AMSDOS headers, M4/Albireo
selector, gate/modules, floppy contents, and CPC low-RAM map. The second boots
the actual disk in `../1984/1984`, opens File Manager, launches
`ABIPROBE.APP`, and verifies three live windows plus a changed probe-window X
coordinate after a title drag. Captures are written under
`/tmp/geobench-cpc-1984`.
