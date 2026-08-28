# References

External source material relevant to building GEOBENCH. These are study /
reference resources — not dependencies, and not vendored into this repo.

## GEOS (the design ancestor)

- **mist64/geos** — <https://github.com/mist64/geos>
  Reverse-engineered, modularised source of **GEOS 2.0** (Berkeley Softworks)
  for the Commodore 64/128, reconstructed by Maciej Witkowiak and Michael Steil.
  ~20 KB of 6502 assembly implementing a complete GUI: kernel, menus, dialogs,
  application management.
  **Why it matters:** the canonical worked example of how a real WIMP desktop
  fits on tiny 8-bit hardware — exactly the existence proof GEOBENCH builds on.
  Study its kernel/app split, memory discipline, and menu/dialog model. (6502,
  not Z80, so it's an architectural reference, not code to port.)

## Amstrad CPC firmware (the layer we sit on)

- **Bread80/CPC6128-Firmware-Source** — <https://github.com/Bread80/CPC6128-Firmware-Source>
  Reverse-engineered, reassemblable Z80 source of the **CPC6128 firmware**, split
  into labelled, commented modules (graphics, sound, keyboard, etc.) plus the
  original ROM image for verification.
  **Why it matters:** GEOBENCH calls the firmware for screen, keyboard, and disk.
  This is the authoritative reference for the **TXT/GRA VDU vectors** and the
  CAS/AMSDOS file paths the kernel uses. (Note: GEOBENCH does **not** contain
  legacy machine-code `.BIN` software; `.BAS` files may be opened by the
  separately maintained GB-BASIC application.)

## Locomotive BASIC

- **Bread80/Amstrad-CPC-BASIC-Source** — <https://github.com/Bread80/Amstrad-CPC-BASIC-Source>
  Reverse-engineered "unassembly" of the **Amstrad CPC BASIC 1.1 ROM** (1986) in
  documented, modular Z80 assembly, with the original ROM image for verification.
  **Why it matters:** GEOBENCH boots from a `RUN"GB` BASIC loader and shares the
  machine with the BASIC ROM, so this documents how BASIC enters/exits and manages
  its workspace — and what state the desktop must preserve. GB-BASIC provides
  the managed editor/runtime used when a staged `.BAS` file is opened.
