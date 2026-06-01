# tools/

Host-side (PC) tooling for building GEOBENCH and preparing assets. None of this
runs on the CPC — it produces the binaries and data files that do.

## Planned tooling

- **Build scripts** — drive the Z80 assembler (RASM is used in sibling
  projects) to assemble the kernel, libraries, desktop, and apps.
- **Asset converters** — turn host-side images into CPC bitmaps/icons in the
  native Mode 1 pixel layout.
- **Font tooling** — convert/pack proportional bitmap fonts into the runtime
  font format.
- **Disk image builder** — assemble the output binaries and data files into a
  bootable CPC disk image (`.dsk`).

## Conventions

- Output binaries (`*.bin`, `*.BIN`, `bin/`, `*.dsk`) are build artifacts and
  should be gitignored — only source and tooling live in the repo.
- Any text/data file destined for the CPC must use **CR+LF** line endings.

## Status

Not started. A minimal assemble-and-pack script comes online with the first
bootable kernel.
