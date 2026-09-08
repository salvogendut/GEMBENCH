# MSX2 reference for the CPC restart

Reference revision: `5ed8a157656848cad1db1e21c68490ef06b015cb`.
Inventory date: 2026-09-05. Issue: [#63](https://github.com/salvogendut/GEMBENCH/issues/63).
Parent: [five-step restart plan](CPC-RESTART-PLAN.md).
Fresh results: [baseline validation record](CPC-RESTART-BASELINE.md).

## How to read the inventory

Each R-number is a stable acceptance ID. A source location identifies the
implementation to share or adapt; it does not prove runtime correctness.
Listed tests already exist at the reference revision unless described as gaps.
Their fresh execution status is recorded separately in the baseline document.

`Host` means native C contracts/models, source/layout audits, or package tests;
some also compile Z80 code. `Emulator` means a script exercises a guest runtime,
sometimes with injected diagnostic calls. Neither a host model nor a screenshot
alone proves the complete interaction. Preserve that distinction in reports.

Older milestone documents describe their historical layout and application
versions. The release now stages **universal** `CLOCK.APP`, `CALC.APP`, and
`ABIPROBE.APP`; other production applications are still native MSX2 builds.
The current public sysinfo is **48-byte v6**, with its 32-byte v5 prefix
preserved. Historical checks of the private v5 shadow are not v6 conformance.

## Feature inventory and acceptance matrix

Paths below are relative to the repository root. Scenario IDs are shared
between targets; runtime geometry, native bank IDs, and timings are normalized.

| ID / implemented feature | Implementation and existing evidence | Required acceptance scenario / coverage gap |
|---|---|---|
| R01 — GBR1 format, reader and compatibility | `abi/gembench-v1.json`, `tools/gbrc.py`, `lib/gembench/gbr_reader.c`; Host: `tests/test_gbrc.py`, `tests/run_gbr_reader_tests.sh`, `tools/check_gembench_abi.py` | Open the same valid tree; reject corrupt lengths, links, flags and checksums before partial drawing. Preserve the frozen resource/managed-window ABI. Run the actual target reader as well as host corruption cases. |
| R02 — Object trees and resource forms | `lib/gembench/gbr_object.c`, `gbr_form.c`, `apps/formref/`; Host: GBR reader/object suite; Emulator: `tools/test_formref_openmsx.sh` | Exercise fields, checkbox/radio exclusivity, disabled objects, deepest hit, forward/reverse Tab, Enter/default and Escape. Actions and state transitions must match for equivalent layouts. Small-screen layouts need explicit coverage. |
| R03 — Resource menus, semantic graphics and raster bindings | `lib/gembench/gbr_menu.c`, `gbvdi*.c`, `apps/filemgr/view_menu.json`, `apps/settings/`; Host: GBR and VDI suites; Emulator: `tools/test_settings_vdi_openmsx.sh` | File Manager View shortcuts and checked state agree with pointer selection; Settings draws and edits through its compact semantic profile; bound ICON/IMAGE rasters clip and reject invalid inputs. Universal Calculator uses portable primitives, not its former GBR panel: test FormRef/Settings for resource parity. |
| R04 — Managed furniture and desktop top bar | `kernel/gbkern.asm`, `kernel/modules/gbtitle.asm`, `lib/gb/gbwin.c`, `lib/gb/gbuniversal_menu.c`; Emulator: `tools/test_window_kinds_openmsx.sh`, `tools/test_desk_accessories_openmsx.sh` | Launch with visible borders, labels and correct focus; focus installs the app menu; close/move/resize/maximize messages update app geometry; disabled gadgets do not act. Verify the old menu is restored after close. |
| R05 — Global visibility, focus and exact damage | `kernel/scheduler.asm`, `kernel/gbkern.asm`, `lib/screen_clip.asm`; Host: `tests/test_visibility_compositor.py`; Emulator: `tools/test_visible_regions_openmsx.sh` | Raise a covered window by focus alone; check newly exposed content and both active/inactive frames. Drag through several positions then verify the vacated route; close/resize at screen edges. Compare actual writes and unaffected regions, not only final coordinates. |
| R06 — Visibility-ranked worker scheduling | `kernel/scheduler.asm`, `lib/gb/gbtask.s`; Emulator: Clock/PAINT workflows; Host: visibility integration assertions | Use owners with focused, full, partial and hidden surfaces. Verify focused/full/partial priority, round-robin within a tier, a root turn between workers, no execution by fully hidden visual workers, and owner-wide visibility aggregation for multiple windows. Expand dedicated mixed-owner stress coverage. |
| R07 — Nonblocking event subscriptions | `lib/gembench/gbevent.c`, `include/gembench/gbevent.h`, retained `apps/clock/`; Host: `tests/run_gbevent_tests.sh`; Emulator: `tools/test_multi_event_openmsx.sh` | Combine pending key, pointer, timer and WM activity without losing simultaneous bits or blocking unrelated input. Historical Clock coverage is a native fixture; do not label it proof of the universal event path. |
| R08 — Typed clipboard and document shell conventions | `lib/gembench/gbscrap.c`, `gbshell.c`, `apps/notepad/`, `apps/filemgr/`; Host: scrap/shell suites; Emulator: `tools/test_typed_scrap_openmsx.sh`, `tools/test_shell_service_openmsx.sh` | Copy/paste text between two Notepads, preserve legacy raw/text compatibility and 510-byte raw capacity; reject a wrong type atomically. Opening a document reuses a suitable live editor or follows the existing fallback without losing dirty content. |
| R09 — Sysinfo and owned general page pool | `kernel/msx_page_pool.asm`, `lib/gb/gb.h`; Host: ABI/low-RAM checks; Emulator: `tools/test_m1_architecture_openmsx.sh` and `apps/sysinfo/` | Query v6 through the public service; allocate pages beyond the window count, exhaust safely, reject foreign/stale/double frees, then restore free counts. Use runtime pool totals rather than hard-coding MSX2's reference 25 pages for CPC. |
| R10 — Independent application/window ownership | `kernel/msx_page_pool.asm`, `kernel/gbkern.asm`, `apps/paint/`; Emulator: architecture and `tools/test_m2_paint_openmsx.sh` | PAINT Toolchest, Preview and Canvas share one owner/code page. Close Canvas independently, then document panes, then quit; surviving panes remain usable and final teardown releases every owned page. Reject foreign/stale window handles; test published windowless owners and root-quit rejection. |
| R11 — Deferred messages and exact Desk activation | `kernel/msx_page_pool.asm`, `lib/gembench/gbdefer.s`, `apps/desktop/accessories.json`; Host: `tests/run_gbdefer_tests.sh`, `tests/test_desk_accessories.py`; Emulator: architecture and Desk scripts | Sending never invokes the receiver synchronously. Fill the eight-record FIFO, verify deterministic overflow, close/reuse a recipient before dispatch, and discard stale delivery. Desk launches once, reactivates the exact Clock/Calculator owner, closes cleanly and relaunches with fresh identity. |
| R12 — Explicit filesystem contexts | `kernel/kc/gbfsctx_mod.c`, `kernel/kc/gbfsctx_msx.s`, `lib/gembench/gbfsctx.c`, `apps/filemgr/`; Host: `tests/run_gbfsctx_tests.sh`; Emulator: architecture diagnostic | Interleave two directory enumerations and a file transfer without redirecting either; enforce four contexts and 512-byte transfer bounds; verify sequential offsets, cancel, launch handoff, stale/foreign rejection, exhaustion and owner cleanup. Current File Manager scan is migrated; other legacy I/O paths are not all converted. |
| R13 — Shared-service lifecycle | `lib/gembench/gbservice_client.c`, `gbservice_provider.c`, `gbservice_collect.c`, `apps/netsvc/`, `apps/telnet/`; Host: `tests/test_service_manager.py`; Emulator: `tools/test_m7_service_openmsx.sh` | Two provider slots/three leases obey owner and generation rules. Verify failed first start rolls back; A/B/C acquire, D gets full; client death reclaims its lease; deferred replies and final release unload the provider. Network absence must be a typed result. This is a control-plane service, not shared sockets. |
| R14 — Background visual timers and pointer stability | `lib/gembench/gbtimer_damage.s`, `gbtimer_collect.s`, `lib/gb/gbuniversal.c`, `apps/uclock/`; Host: `tests/test_background_timer.py`; Emulator: detailed legacy Clock test plus universal Desk presentation test | Enable seconds; overlap Clock partially, fully, and over only its changing component; uncover it again. Measure hand/changed-digit damage, untouched rim/HH:MM/frame, zero hidden-worker/draw deltas, unchanged occluder, stable focus/pointer and current-time reconstruction. Repeat after close/reuse with pending damage. Full equivalent coverage on the shipped universal Clock is a gap. |
| R15 — Transactional packages and compile-once ABI | `abi/geobench-v2.json`, `tools/build_uapp.sh`, `tools/embed_app_icon.py`, `kernel/msx_gbap4.asm`; Host: `tools/test_gbap4.py`, `test_universal_app.py`, `test_geobench_v2_msx_gate.py`; Emulator: `tools/test_geobench_v2_msx_openmsx.sh`, `test_m5_gbap3_openmsx.sh` | Accept supported packages and reject bad identity/capabilities/bounds/CRC before entry; restore bank/pages/owners/windows on failure. Keep legacy loading. Hash actual universal executables in both media against one build. v4 currently admits only the uncompressed common primary segment; portable filesystem/resource capabilities remain unadvertised. |
| R16 — Owned secondary code and resource placement | `lib/gembench/gbsecondary.c`, `gbsecondary.s`, `gbr_bank.c`, `apps/formref/secondary.s`; Host: package tests; Emulator: `tools/test_m6_secondary_openmsx.sh` | FormRef calls its owned v3 secondary and restores the exact bank/stack. Reject bad entry, stale/foreign owner, nested/worker/teardown calls; reclaim both pages on quit. This existing v3 feature still needs a migration route before full parity; it does not imply v4 external segments exist. The older banked-GBR/resident-renderer trial remains a prototype. |
| R17 — Desktop, files, assets and settings | `apps/desktop/`, `apps/filemgr/`, `apps/settings/`, `tools/build_kernel_msx.sh`; Host: identity/media audits; Emulator: window/Settings/shell workflows | Preserve Disk/Desk menus, icons and REFINED artwork, associations, navigation, list/icon views, sorting, scrolling, copy/move/delete and settings persistence. Change focus while enumerating and repaint while loading icons; no storage calls inside repaint. Add release-wide workflow coverage; existing probes do not cover every operation. |
| R18 — Complete shipped applications and providers | `apps/`, `components/gb-basic/`, `tools/build_kernel_msx.sh`; Host: Calculator, kernel/libgb and distribution suites; Emulator: `tools/test_gb_basic_openmsx.sh` plus individual app probes | Complete the migration ledger below; test load/edit/save/close and error/cancel paths where applicable. Hardware-dependent rendering, networking, sound and savers need services or explicit hardware substitutions, never silent removal to claim full software parity. |

## Acceptance rules shared by all scenarios

Record the source revision, tool versions, application/image hashes, machine,
memory, video mode and storage backend. Compare normalized behavior between
MSX2 Screen 6/7 and CPC Mode 1; raw screenshots across those geometries are not
expected to match. Use one scenario with target input/observation adapters.

For each launch/failure/close cycle, compare the baseline and final live owners,
windows, pages, contexts, workers, queued messages and service leases as
applicable. Relative changes are more portable than private table addresses.
Include bank restoration, stack guards and rejected stale handles. Propose 50
repeat cycles for integration stress; this is a new acceptance workload, not a
claim that the current tests already execute it.

For drawing tests, collect intermediate writes/callbacks as well as settled
frames. Mask independently changing time/pointer regions only with explicit
bounds, and test those masked regions separately. A final identical image can
hide a transient overwrite; any framebuffer change can come from the top bar
or pointer instead of the intended application.

Use the actual source-damage contract when judging repaint:

- Component updates affect only their declared rectangle intersected with the
  surface and minus higher opaque windows.
- The current focus contract redraws the complete old/new focus rectangles as
  two disjoint sources, clipped to the new stack. It is not a promise of
  title-only updates; unrelated space between the windows remains untouched.
- Drag feedback is a destructive outline. Its endpoint bounding envelope
  includes the route that needs repair, not just the two final footprints.
- First paint, resize/fullscreen, document replacement and global theme changes
  can legitimately invalidate a whole surface or screen.

Fully hidden **visual workers** are parked. Root-owned input, time, storage,
network and service dispatch remain runnable, including windowless providers.
A multi-window owner's visibility is the highest rank among its live windows.
Preserve the current worker restriction against calling drawing, filesystem,
firmware or paged services from preemptible worker code.

Measure input-to-visible-response latency, callback count, changed area,
resident size and stack high-water under the same interaction load. Establish
per-platform budgets from measurements before optimizing. A CPC software
renderer need not match VDP wall-clock timings to implement the same behavior.

## Application migration ledger at the reference revision

Every row remains a CPC acceptance obligation. Bundled source does not mean
that its current executable is universal. `tools/build_kernel_msx.sh` is the
authority for the staged application/module/saver list.

| Consumers | Current release path | Port dependency / required workflow |
|---|---|---|
| ABIPROBE, CLOCK, CALC | Universal GBAP v4 artifacts from `build/universal` | Preserve exact bytes per SDK version; launch/chrome/menu/input/close; Clock occlusion and Calculator keyboard/pointer arithmetic including error cases. |
| DESKTOP, FILEMGR | Native MSX2, shared source with platform assumptions | Root scheduling/collectors, capability/geometry access, explicit storage contexts, assets and menu policy; migrate both without reviving reduced CPC shell behavior. |
| FORMREF, GBRDEMO, SETTINGS | Native MSX2 | GBR/forms/menus/VDI, external resource loading and FormRef secondary code; profile-aware layout and settings persistence. |
| NOTEPAD, SHELL, DISKUTIL | Native MSX2 | Text, clipboard, shell reuse and existing storage/command workflows; exercise dirty-document, error and cancellation behavior. |
| PAINT | In-tree native MSX2, three managed panes | R10 and document/canvas storage, portable drawing, undo and save; separate feature-parity and universal-binary checks. |
| VIEWER, ICONED, XAOS | Native MSX2 | Canonical pictures/icons, owned pages and bounded rendering; retain common functionality and explicitly identify native MSX sprite/video extensions. |
| BASIC, BASRUN, BASRUN2 | In-tree `components/gb-basic`, native MSX2 app/runtime/engine | Editor-to-runtime execution, engine memory reservation, examples and return to Desktop; no sibling source dependency. |
| NETSVC, TELNET, BROWSER, BRSAVE | Native MSX2, UNAPI and client-local network data | Shared manager semantics plus CPC transport provider; network absence, successful requests, cancellation and final cleanup. Browser is not yet a shared-service client. |
| MAHJONG, SNDTEST | Native MSX2 | Input/graphics assets and platform sound backend; game workflow and supported sound operations. |
| SQUARES, ANT, DECO, XMATRIX, MOUNTAIN, FOREST, STARFLD, FRACTALI, MUNCH, RORSCH, TRUCHET, LIGHTN, PYRO, HELIX, XROACH, CATCLK | Native `.SAV` files and configuration modules | Idle activation, graphics/time/settings, input wake and exact desktop restoration; inventory direct hardware access before migration. |
| GBCFG, GBUI, GBAPICK, GBWEB, GBIMG, GBFSCTX, GBAPV4, GBTITLE and associated assets | System modules staged by the build | Module placement/lifetime, shared dialogs, chooser, config, resources, loaders and bounded I/O; modules may have platform implementations even when applications are universal. |

## First extraction boundaries and known gaps

| Area | Current coupling to isolate | Handoff |
|---|---|---|
| Owner/page/application records | `kernel/msx_page_pool.asm` combines lifecycle policy, mapper metadata and fixed page-3 storage | First step-2 package: retain policy, introduce explicit bank/state seams, prove allocation/teardown and rollback on MSX2. |
| Compositor and scheduler | `kernel/scheduler.asm` and `kernel/gbkern.asm` mix geometry/owner ranking with MSX storage and IRQ/bank hooks | Share region and owner policy; adapt native drawing, interrupt and mapping leaves. Keep bounded root/worker context rules. |
| Universal command and timer cells | `lib/gb/gbuniversal.c` uses `0xC030`, `0xC039`, `0xC1EC`, `0xC3CA`; `abi/geobench-v2.json` is the ABI authority | Review the experimental contract before the CPC foundation gate. The parked port's screen-memory save/restore is not a portable address design. |
| Filesystem and service state | `kernel/kc/gbfsctx_mod.c`, `gbfsctx_msx.s`, `lib/gembench/gbservice_*.c` use fixed transfer/context/provider tables and MSX backend calls | Share handles/offset/lifetime/queue policy; keep M4/Nextor operations behind bounded adapters. Unsupported FSCTX cannot count as parity. |
| Shell/application integration | Desktop/File Manager carry compile-time geometry and private-memory accesses; native PAINT uses mapper/picture details | Migrate the actual consumers after services exist. Flag native builds and hardware branches in the ledger until removed from universal apps. |
| Test observation | Many emulator scripts use historical private addresses and native fixture symbols | Generate symbol-based target adapters; observe the public v6 record; port scenarios, not hard-coded memory maps. |

The historical M8/M9 Clock driver explicitly installs `build/msx/CLOCK.RAW`.
The Desk driver checks the release universal packages, menu identities,
Calculator text-call count and border preservation, but does not supply all
the legacy test's occlusion and worker assertions. Extend those assertions to
the shipped universal Clock before changing its runtime path.

The old mode-boot script checks the private 32-byte v5 shadow. Keep its loader
smoke role and add public v6 observation for restart conformance. Tests that
assert source strings or fixed addresses need classification as wiring checks;
passing them does not prove target instruction, rendering or timing behavior.

## Deliberate limits and future work

Full parity reproduces the supported slices, not every idea in the original
roadmaps. Do not claim arbitrary timers, multiple workers per owner, unbounded
queues, bulk deferred payloads/acknowledgements, general filesystem seek/query
or asynchronous workers, shared network sockets, compression, relocation, or
v4 external resource/data/code segments as implemented.

The existing v3 secondary-code feature and File Manager contexts remain parity
requirements even though their universal application bindings are incomplete.
Plan their migration explicitly. Screen 7's extra colors, native sprite
editing, MSX video selection and UNAPI implementation are hardware extensions;
document CPC equivalents where applicable without weakening shared UI and
lifecycle rules. See the [future-work list](gembench/FUTURE-IMPROVEMENTS.md)
and [universal application migration plan](UNIVERSAL-APPLICATION-ABI-MIGRATION.md).
