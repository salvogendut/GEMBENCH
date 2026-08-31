# References

External material used to study or validate GEMBENCH. These projects and
documents are references, not source dependencies; the release build uses the
code and assets kept in this repository plus the fetched MSX dependencies
described in [BUILDING.md](BUILDING.md).

## Desktop architecture

- **GEOS 2.0 reconstructed source** — <https://github.com/mist64/geos>
  A compact 8-bit desktop used as an architectural reference for kernel/app
  separation, memory discipline, menus, dialogs, and document workflows.
- **SymbOS facts and architecture** — <https://symbos.org/facts.htm>
  The comparison that informed GEMBENCH's application identities, owned mapper
  pages, multi-window ownership, scheduling, events, and bounded services.
- **GEM documentation archive** — <https://www.deltasoft.com/downloads-gemworld.htm>
  Historical GEM/AES/VDI material used for terminology and interaction ideas.
  GEMBENCH implements its own formats and Z80 APIs; it is not binary-compatible
  with GEM applications.

## MSX2 platform

- **openMSX** — <https://openmsx.org/>
  The reference emulator for MSX2 correctness and timing validation.
- **Nextor** — <https://github.com/Konamiman/Nextor>
  The MSX-DOS2-compatible storage environment used by the card image.
- **MSX Resource Center development wiki** — <https://www.msx.org/wiki/Category:Development>
  Platform notes covering the MSX architecture, BIOS, mapper, VDP, and file
  formats.

## Toolchain

- **RASM** — <https://github.com/EdouardBERGE/rasm>
  Z80 assembler used for the kernel and assembly modules.
- **SDCC** — <https://sdcc.sourceforge.net/>
  C compiler used for applications and app-linked libraries.

The archived CPC and PCW implementation and its platform references are
preserved in `archive/cpc-pcw-targets`; it is the implementation baseline for
the staged ports in the
[universal ABI migration plan](UNIVERSAL-APPLICATION-ABI-MIGRATION.md).
