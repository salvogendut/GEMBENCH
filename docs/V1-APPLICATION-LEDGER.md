# v1.0 application migration and acceptance ledger

Recorded 2026-09-08 for [issue #82](https://github.com/salvogendut/GEMBENCH/issues/82).
Read with the [roadmap](ROADMAP-V1.0.md) and
[MSX stability baseline](V1-MSX-STABILITY-BASELINE.md). This is an inventory,
not a declaration that all shipped apps are qualified for v1.0.

## Current migration state

As of 2026-09-15, **Clock, Calculator, Notepad and GBRDEMO** are production compile-once applications in both
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
| Notepad / `apps/unotepad`; native reference retained in `apps/notepad` | Universal v4, two segments | Normal-image Screen 6/7 editor, exact-path handoff, live reuse, exact configuration publication and real BASIC CRLF round trip in 1983; independently checked in openMSX | Same APP in normal M4 image; editing/chooser/clipboard, 4096/4097 bounds, dirty decisions, live reuse/configuration publication, dotted paths, BASIC CRLF, read-only/full-disk failures and cleanup qualified | **1 complete.** Albireo and whole-release coverage remain milestone **7/8**, not Notepad gaps; [delivery](UNIFIED-NOTEPAD-DELIVERY.md), [reuse](UNIFIED-NOTEPAD-REUSE.md), [configuration](UNIFIED-NOTEPAD-CONFIG.md), [closure](UNIFIED-NOTEPAD-CLOSURE.md) |
| GBRDEMO / `apps/ugbrdemo`; native reference retained in `apps/gbrdemo` | Universal v4 | Normal-image Screen 7 external-resource association, state, move/focus/close and cleanup in openMSX and 1983; private Screen 6/7 malformed-resource matrix | Same APP and `HELLO.GBR` in normal M4 image; canonical workflow accepted in 1984, private malformed-resource matrix retained | **2 GBRDEMO slice complete.** FormRef and owned secondary-code closure remain; [milestone record](V1-M2-PORTABLE-RESOURCES.md) |
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

## Current delivery identity — 2026-09-15

Direct comparison of the normal MSX and CPC CARD files confirms that all four
production universal applications match byte-for-byte:

| Payload | Bytes | SHA-256 |
| --- | ---: | --- |
| CLOCK.APP | 8198 | `55b45e59f53126a399ba6ab0ac93439235ae09fe8d90bcf8bc90e8155a9cdad0` |
| CALC.APP | 7868 | `4e7fbe8df31f328b1814cbc46bbe04f984a38f6f62466640786574f7385265e0` |
| NOTEPAD.APP | 20521 | `fae9ad2f6da69b906af13836f7230095d2ca8421211a8f80a79e310813f933b7` |
| GBRDEMO.APP | 13069 | `4ec6f034ed396c51fcf5d573c548acfd7df53f077e9f14a718a7cd8cc762b4ff` |
| HELLO.GBR | 111 | `49b42e9268ad4f4208d70f591f9d3f6b6ad7bee2dcf6f008a773ece968febf12` |

Normal CPC acceptance covers the original 35 scenarios (34 passed initially; the corrected
legacy unsupported-file scenario passed separately). All seven delivered editor
cases passed initially. MSX editor, exact-path handoff and Desk/Clock/Calculator
stress pass in both screen modes under 1983, with independent openMSX editor
checks. See [the delivery record](UNIFIED-NOTEPAD-DELIVERY.md) for complete
provenance, image hashes, source-media preservation and exact memory limits.
Prior user manual acceptance covered editing and File > Quit on both targets;
the delivery and subsequent live-reuse/configuration checkpoints add automated
qualification. The [closure record](UNIFIED-NOTEPAD-CLOSURE.md) adds CPC dotted
path acceptance and real BASIC CRLF round trips in CPC/1984 and MSX/1983 Screen
6/7, plus an independent openMSX regression. Milestone 1 is complete. Real
hardware, Albireo and whole-release acceptance remain milestones 7–8; no v1.0
completion is implied.

GBRDEMO's normal CPC M4 workflow additionally passes exact framebuffer,
selection, drag, focus and cleanup checks in 1984. The normal MSX Screen 7
workflow passes in openMSX and in 1983 with 23 state/lifecycle checks and no
source-image write. Its private qualification matrix retains Screen 6/7 and
canonical/checksum/truncated/oversized coverage on both targets. This completes
only GBRDEMO's milestone-2 slice; FormRef remains.

## Historical artifact identity and bring-up findings — 2026-09-08/09

The following records describe earlier native delivery and failed prerequisites,
not the current editor or current distribution state.

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
Preserve its behavior before replacing it; no runnable universal version exists yet.
The 2026-09-09 isolated rebuild at `1367593` has the same hash. Its native
data/BSS ends at `0x7FF9`: seven bytes below the native limit, already 249 bytes
past the universal `0x7F00` limit. The [audit](UNIFIED-NOTEPAD.md) records the
additional caller-owned FS storage and reclaimed-icon scratch that must be
budgeted explicitly. Host-tested document I/O is not a migrated application.

The new diagnostic-only `SCRAPPRB.APP` (4808 bytes) is identical on private
MSX Screen 6/7 and CPC M4 media; three-owner clipboard checks pass under
openMSX, 1983 and 1984. See the audit for hash/evidence. This does not add a
production migrated application or qualify Notepad editor-to-editor exchange.

The diagnostic-only `PICKPRB.APP` (9834 bytes) additionally qualifies the owned
chooser and selected-file readback with identical bytes on those targets. Save As
selects a name without writing. Real editing, dirty-save recovery and the complete
editor link remain; the audit also records the CPC provider's dotted-directory
and filename-character limitations. Normal distribution media are unchanged.

The actual editor candidate in `apps/unotepad` now has mocked-service host policy
tests, but its full link needs 28857 bytes against a 16128-byte primary budget.
The builder rejects it before packaging; it has no APP hash or emulator evidence.
The private data-page prerequisite now passes with identical 5004-byte
PAGEPRB.APP on both receivers; see [portable pages](PORTABLE-PAGES.md).
The shared streamed loader now has instruction-fixture fault/rollback evidence;
receiver integration and sealed secondary calls still must precede editor delivery. This does not
upgrade the Notepad row from native or reuse diagnostic acceptance as editor proof.

## Before marking a row complete

Record separate MSX Screen 6/7 and CPC M4/Albireo results, exact APP hashes in
both distributions, normal launch/document/close behavior, relevant storage and
resource failures, cleanup and manual acceptance. Native historical success
does not qualify its universal replacement. Any scope exception needs explicit
agreement and a visible entry here.

Audit linked code/data/stack headroom before adding bindings. Fresh native
Settings data/BSS ends at `0x7FFA` (6 bytes below `0x8000`), File Manager at
`0x7FFB` (5 bytes), and Desktop at `0x7ECE` (50 bytes below its `0x7F00` task-stack
reserve). Those are historical native audit figures; the current Screen 7
child COM leaves **24 bytes** below its 16128-byte budget. The delivered
Notepad primary code has **62 bytes** before DATA, with its independent
4096-byte document and 4096-byte staging preserved in the secondary segment.
These are tight existing budgets, not proof of overflow or limits that can be
removed without reviewing the memory/ownership contracts.
