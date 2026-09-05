# CPC emulator test strategy: M4/Albireo only

Recorded 2026-09-05 following the user's request to investigate `../arnold`
alongside `../1984`, `../caprice32` and `../konCePCja`.

## Storage rule

All future CPC runtime tests must boot and operate through **M4 or Albireo**
backing. Do not use floppy images, an AMSDOS floppy shortcut, or snapshot-only
boot to bypass a missing storage provider. An emulator without a supported
provider is pending, not a reason to fall back to slow floppy tests.

Keep one canonical generated CARD payload and package private copies into the
backend format required by each emulator: for example a raw FAT image for
1984's current M4 probe, or a host-directory virtual M4 card where that is the
emulator's implementation. The CPC must still access it through the real
emulated board/ROM command path. Record the backend explicitly; mounting the
same files through floppy emulation is not equivalent.

This policy concerns CPC runtime execution. It does not delete preserved media
or change the existing MSX2 distribution's static floppy-format audits.

## Current local checkouts

These are findings about the checked-out revisions below, not claims about
other branches or newer upstream versions. This investigation was read-only;
no emulator was built, installed, modified or run for this assessment.

| Emulator / revision | M4 or Albireo evidence | Automation and current role |
|---|---|---|
| `../1984`, `39303d9` | Both boards are documented in `M4.md` / `ALBIREO.md`; this repository already exercised real M4 commands in restart 3A–3C. | Primary proved foundation runner: private M4 image, PTY command interface, memory/result capture. Albireo remains an unqualified GEOBENCH backend, not already passing. |
| `../konCePCja`, `d35c263` | `src/m4board*` and `docs/hardware/m4-board.md` describe a host-directory-backed M4 device. | Promising next independent runner: documented headless mode, IPC stepping/waits, memory and screen hashes, screenshots. Still needs the same GEOBENCH M4 foundation qualification; documentation is not a passing runtime result. |
| `../arnold`, `acd93ac` | No M4, Albireo or CH376 provider was found in this source tree, I/O implementation or linked object list. | Useful independent CPC/Z80/CRTC reference candidate, but **not currently eligible** for M4/Albireo-only GEOBENCH runs. Storage and automation work are prerequisites. |
| `../caprice32`, `f9ab174` | No M4/Albireo/CH376 provider found in the local `src/` tree. Its `net4cpc.*` implements W5100S Ethernet, not M4 storage. | Keep as a future reference candidate; first establish a supported storage provider, then qualify its automation. No floppy fallback. |

## Arnold assessment

The local tree is the older C/Unix Arnold codebase. Relevant sources are:

- `../arnold/src/unix/main.c`: `help_exit`, `long_options` and `init_main`
  expose machine/CRTC choice, cartridge/tape/disk/snapshot loading and sound
  options. The inspected CLI has no M4/Albireo mount option, scripted command
  channel, headless test mode, bounded-run/result-export switch or automation
  equivalent to the existing 1984 runner.
- `../arnold/src/cpc/cpc.c`: `CPC_OR_CPCPLUS_Out` and the input dispatch,
  plus `../arnold/src/objects.mak`, show the device integration points. Searches
  for M4/Albireo/CH376 found no provider in this checkout. Loading an M4 ROM
  alone would not supply the missing board I/O or storage implementation.
- `cpc.c` also has 32 extra 16-KiB page pointers, RAM allocation and
  `CPC_SetRamConfig`; `CPC_Initialise` selects the combined expansion flags.
  The core can represent 512 KiB of expansion plus base RAM. That is promising
  for our >=512-KiB requirement, but the actual reachable bank map/ROM overlays
  still need the existing memory probe; the CLI's CPC6128 label is not proof.
- `../arnold/src/configure.ac`, `Makefile`, `autogen.sh` and `readme.linux`
  describe the legacy X11/SDL 1.2/optional GTK2 build. No compiled Unix binary
  or configured build was used. Dependency availability and modern-build
  compatibility have not been tested.
- `../arnold/src/unix/configfile.c` searches `~/.arnold` and `/etc/arnold`;
  `main.c` loads and saves configuration. A future test launcher must provide
  isolated configuration explicitly rather than reading/writing the user's
  normal emulator settings. An explicit config-path option would be preferable.
- The Z80, CRTC, snapshot and debugger source offers potential observation
  hooks, but their presence is not a supported unattended testing interface.

Conclusion: Arnold is worth retaining as a candidate for independent hardware
confirmation, but it is not a drop-in test runner under the storage constraint.
Do not spend time wiring GEOBENCH UI tests to it before deciding whether to
implement M4/Albireo plus a small automation interface in its own repository.
No such implementation is authorized or started by this investigation.

## Qualification before adding a runner

1. Verify an existing M4/Albireo provider or separately agree the emulator work
   needed to add one. Keep emulator changes in that emulator's issue/branch.
   Disable unrelated networking/HTTP services during local storage tests.
2. Provide isolated configuration and private writable media, deterministic
   reset/input, bounded waits, memory/PC inspection, screenshot or framebuffer
   capture, machine-readable results and reliable process termination. Headless
   execution is useful but alone does not provide these capabilities.
3. Run the existing 3A memory/interrupt, 3B clipped graphics/pointer, and 3C
   storage/failure scenarios through the actual board at >=512 KiB. Compare
   semantic results and guards; qualify Albireo separately from M4. Record
   executable/ROM/media hashes and the exact memory/CRTC/backend configuration.
4. Only after qualification, add an input/observation adapter for the same
   shared-core and desktop scenarios. Do not create a different CPC policy per
   emulator. Use identical universal APP hashes in all media.

Practical order: continue with the already proved 1984 M4 runner, qualify
konCePCja's M4 implementation next, then revisit Arnold/Caprice32 when a permitted
storage path exists. For conflicting results, preserve both traces and isolate
the minimal bank/IRQ/graphics/storage sequence before attributing a failure to
GEOBENCH or an emulator. Emulator agreement is supporting evidence, not a
substitute for eventual real-hardware confirmation.

The restart still has no enabled CPC desktop. These notes prepare its later
testing; they do not claim the application parity matrix has passed.
