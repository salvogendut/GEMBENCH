# v1.0 application migration and acceptance ledger

Recorded 2026-09-08 for [issue #82](https://github.com/salvogendut/GEMBENCH/issues/82).
Read with the [roadmap](ROADMAP-V1.0.md) and
[MSX stability baseline](V1-MSX-STABILITY-BASELINE.md). This is an inventory,
not a declaration that all shipped apps are qualified for v1.0.

## Current migration state

Only **Clock and Calculator** are production compile-once applications in both
distributions. ABIProbe is an additional universal diagnostic. Native GBAP v1,
v2 or v3 packages, headerless legacy applications, and the `.APP` suffix do not
establish unified-ABI compliance. Desktop and system providers are separate
from ordinary application migration; File Manager and Settings are not exempt.

Fresh MSX inventory: 23 `.APP` files, including Desktop, ABIProbe, NETSVC and
helper executables. Do not use this mixed denominator as a migration percentage.
Sources and dependencies below identify the next audit, not an already-complete
portable-service contract. Milestone numbers refer to the v1.0 roadmap.

| Application / source | Current binary | MSX checkpoint coverage | CPC delivery / required work | Migration dependencies / milestone |
| --- | --- | --- | --- | --- |
| Clock / `apps/uclock` | Universal v4 | Screen 6/7 lifecycle, border, background and input checks; see baseline limits | Same payload; accepted desktop workload | Keep regression coverage throughout |
| Calculator / `apps/ucalculator` | Universal v4 | Screen 6/7 Desk identity, activation, border, text and cleanup | Same payload; accepted desktop workload | Keep regression coverage throughout |
| ABIProbe / `apps/abiprobe` | Universal v4 diagnostic | Built and inventoried; not independently rerun here | Existing diagnostic qualification, not a production migration | ABI conformance |
| Notepad / `apps/notepad` | Native v1 | Built; document workflows not yet requalified | Not delivered | Document, chooser, filesystem, typed clipboard, editor reuse; **1** |
| GBRDEMO / `apps/gbrdemo` | Native legacy | Built only | Not delivered | Portable resources, forms and semantic drawing; **2** |
| FormRef / `apps/formref` | Native v3 | Built only | Not delivered | Resources/forms plus owned page/secondary-code lifecycle; **2** |
| File Manager / `apps/filemgr` | Native legacy | Normal window/menu workflow: maximize, restore, move and resize | Accepted native M4 browsing, view persistence and qualified-app launching | Portable FS contexts, menus, launch/association services; **3**, full file operations **4** |
| Settings / `apps/settings` | Native legacy | System launch, titlebar selection/save, close and cold reload in both modes | Accepted native six-row appearance profile | Portable config/appearance/chooser services, explicit capabilities; **3**, remaining controls **4/6** |
| Shell / `apps/shell` | Native v1 | Built only | Not delivered | Portable FS, execution and return policy; **4** |
| Disk Utilities / `apps/diskutil` | Native legacy | Built only | Not delivered | Capability-checked storage operations; **4** |
| PAINT / `apps/paint` | Native v2 | Screen 7 three-window focus, move/exposure and cleanup | Not delivered | Portable paged documents, raster, multi-window and owned memory; **5** |
| Viewer / `apps/viewer` | Native v1 | Built only | Not delivered | Portable document, image and page services; **5** |
| Icon Editor / `apps/iconed` | Native v1 | Built only | Not delivered | Portable image/document/chooser services; **5** |
| BASIC / `components/gb-basic/apps/basic` | Native v1 | Built only | Not delivered | Portable editor/document and interpreter bindings; **5** |
| BASRUN / `components/gb-basic/apps/basrun` | Native legacy | Built only | Not delivered | Interpreter and owned secondary-code/page services; **5** |
| Browser / `apps/browser` | Native v1 | Built only; networking disabled in baseline | Not delivered | Portable network, parser/image/document services; **6** |
| BRSAVE / `apps/brsave` | Native legacy helper | Built only | Not delivered | Browser save/FS contract; **6** |
| Telnet / `apps/telnet` | Native v1 | Built only; networking disabled | Not delivered | Portable network/terminal/input services; **6** |
| Mahjong / `apps/mahjong` | Native v1 | Built only | Not delivered | Portable raster, input and any sound dependencies; **6** |
| XAOS / `apps/xaos` | Native v1 | Built only | Not delivered | Portable rendering/input and runtime video capabilities; **6** |
| Sound Test / `apps/sndtest` | Native legacy | Built only | Not delivered | Real portable sound provider; **6** |

### System components and savers

- `DESKTOP.APP` is a native target-linked root on both machines. Shared policy
  and equivalent behavior are required; identical root binaries are not.
- `NETSVC.APP` is a native v3 service, not an ordinary app migration. Its real
  network provider and lifecycle still require both-target qualification.
- `GBAPV4`, `GBFSCTX`, `GBCFG`, `GBUI`, `GBAPICK`, `GBWEB`, `GBIMG`, `GBTITLE`,
  splash modules and `BASRUN2.BIN` are provider/engine components. Classify each
  boundary explicitly during migration; do not relabel a native service portable.
- The 16 staged native savers remain pending: SQUARES, ANT, DECO, XMATRIX,
  MOUNTAIN, FOREST, STARFLD, FRACTALI, MUNCH, RORSCH, TRUCHET, LIGHTN, PYRO,
  HELIX, XROACH and CATCLK. XMATRIX/MOUNTAIN/STARFLD configuration modules also
  need review. Milestone 6 includes their real Settings/saver integration.
- Source-only probes/utilities and retired native Clock/Calculator sources are
  not additional delivered migrations. Reconcile any new delivery with this list.

## Artifact identity at this checkpoint

Production source pin: `9ff0825d77004f9a0380e74b3dc45f3d6d9e772c`.
Full per-file SHA-256 inventory, including modules and savers, is generated by
`tools/prepare_msx_stability.py`; local evidence is
`build/msx-stability-82/evidence/mode6/manifest.json`.

The three universal payloads are:

| Payload | Bytes | SHA-256 |
| --- | ---: | --- |
| CLOCK.APP | 8163 | `efb1b136c57969f91eeef186118cfc8296af1a41410ab8ce13a2a63256050102` |
| CALC.APP | 7833 | `0f4c3c7625ba4c904ca28663e392d80210fb933ae09a34f80795291d5086df65` |
| ABIPROBE.APP | 2575 | `5cb6cf1c857e9ea5b87b4b5ed132b472c4380465b614c4915351a8d5830d4ef0` |

Clock and Calculator match the accepted CPC payload hashes recorded in
[CPC Settings integration](CPC-SETTINGS-INTEGRATION.md). This checkpoint does
not rebuild or replace that accepted image.

Next migration's native reference, NOTEPAD.APP: 12070 bytes,
`402bff07cb4fa73e8b395a6e2707c46860708c7eac0b44e9bcd7dfed3bee7458`.
Preserve its behavior before replacing it; the universal version does not exist yet.

## Before marking a row complete

Record separate MSX Screen 6/7 and CPC M4/Albireo results, exact APP hashes in
both distributions, normal launch/document/close behavior, relevant storage and
resource failures, cleanup and manual acceptance. Native historical success
does not qualify its universal replacement. Any scope exception needs explicit
agreement and a visible entry here.

Audit linked code/data/stack headroom before adding bindings. Fresh native
Settings data/BSS ends at `0x7FFA` (6 bytes below `0x8000`), File Manager at
`0x7FFB` (5 bytes), and Desktop at `0x7ECE` (50 bytes below its `0x7F00` task-stack
reserve). Screen 7's child COM leaves 258 bytes below its 16128-byte budget.
These are tight existing budgets, not proof of overflow or limits that can be
removed without reviewing the memory/ownership contracts.
