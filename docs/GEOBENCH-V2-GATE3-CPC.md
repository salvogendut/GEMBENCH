# GEOBENCH-2 Gate 3: CPC reference runtime

Issue 54-A restores a 512 KiB Amstrad CPC target against the compile-once
GEOBENCH-2 ABI. It is an experimental reference port; MSX2 remains the default
and production distribution, and PCW remains a later gate.

## Runtime boundary

The CPC kernel retains the fixed jump table at `0x8000` and publishes the
48-byte sysinfo v6 record from fixed low RAM. It reports CPC Mode 1,
320x200 pixels, 80x200 logical columns/lines, four semantic pens, and the common
`0x4000..0x7EFF` application range. A 512 KiB machine exposes 27 usable 16 KiB
pages; public page and window handles carry nonzero reuse generations.

The kernel loads `GBSCHED.MOD` into the fixed `0x3000..0x3DFF` runtime slot
before its first scheduler-backed service. That runtime exposes the same owner,
shell, deferred-message, focus, damage, z-order, and window-kind contracts used
by MSX2. Owners are generation-tagged application pages, independent of the
focused window, so every window belonging to one application has one stable
identity. The strict GBAP v4 gate is loaded through the runtime into the
temporary `0x2200..0x2FFF` transfer workspace before every application
admission. It checks package identity, capabilities, bounds, and CRC before
`_start`; failure returns through the shared page rollback. The managed-window
drag implementation remains a demand-loaded PAGE_DATA module, preserving the
CPC kernel's guarded 256-byte stack reserve.

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

Both CPC media forms stage the canonical `assets/iconsets/REFINED.IST` and select
it in `GEOBENCH.CFG`, matching the production MSX2 desktop artwork.

Desktop and File Manager are currently native CPC bootstrap shells. ABI Probe,
Clock, and Calculator are copied from `build/universal` with no relinking or
rewriting. The media audit reconstructs files from the CPC CP/M directory and
verifies their SHA-256 identity against both the universal build and MSX2 card.

Both media forms include the same `GBUI.MOD` used by MSX2, so the shared Desktop
menu and dialog code is not replaced by a CPC implementation. The first Desk
selection launches the byte-identical Clock or Calculator package. Application
startup registers its owner/accessory endpoint; later selections enqueue the
same exact activation message used on MSX2, raise the existing window, and never
create a duplicate page or instance. Repaint callbacks are damage-clipped and
storage-free: drive presence is cached by explicit media polls, so moving or
exposing a window never spins or recalibrates a floppy. Timer workers publish
damage to the shared root collector, keeping Clock alive while unfocused without
nested Desktop C frames.

## Verification

```sh
make cpc-check
make cpc-1984
CPC_SMOKE_APP=CALC python3 debug/cpc_universal_1984.py
CPC_SMOKE_APP=CLOCK python3 debug/cpc_universal_1984.py
CPC_SMOKE_ROUTE=DESK CPC_SMOKE_APP=CALC python3 debug/cpc_universal_1984.py
CPC_SMOKE_ROUTE=DESK CPC_SMOKE_APP=CLOCK python3 debug/cpc_universal_1984.py
```

The first command validates the package stage, AMSDOS headers, M4/Albireo
selector, gate/modules, floppy contents, and CPC low-RAM map. The emulator checks
boot the generated `QA/CPC/GEOBENCH.IMG` through the M4 interface—no floppy is
mounted—then launch ABI Probe, Calculator, or Clock from its `GBENCH` directory.
They verify application chrome, three live windows, managed dragging, Clock
background updates, shared Desk-menu rendering, owner registration, exact
deferred reactivation, focus restoration, and duplicate suppression. Captures
are written under the matching `/tmp/geobench-cpc-1984-*` directory.
