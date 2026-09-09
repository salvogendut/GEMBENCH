# GEOBENCH roadmap to v1.0 — MSX2 and CPC

Recorded 2026-09-08, after the CPC Settings integration merged in
[PR #80](https://github.com/salvogendut/GEMBENCH/pull/80), commit `1408e51`.
This is the forward plan for **finishing both the MSX2 and CPC distributions**:
complete the unified-ABI application migration on both, close CPC feature gaps,
and qualify both release images. Scope clarified with the user on 2026-09-08.
It is not a release announcement or a claim that the remaining features are
implemented.

## What v1.0 means

The planning target is a usable, qualified **MSX2 and CPC release with common
software-feature parity**, built around shared kernel policy and compile-once
applications. A working desktop is the baseline, not the finish line.
MSX2 is the existing behavior reference, **not an already-finished universal
distribution**. Preserving its native applications is a migration safeguard,
not a substitute for delivering and qualifying their unified replacements.
The user reports that the current CPC desktop feels very stable: that accepted
experience is the stability benchmark to preserve on CPC and aim for on MSX2.

- MSX2 and CPC retain their own kernels, graphics, banking, input and storage
  adapters. Shared ownership, windowing, scheduling, damage and service policy
  remains authoritative on both machines.
- Ordinary migrated applications produce **one identical `.APP`**, copied
  unchanged into both distributions. Sharing C source while compiling separate
  target executables is not unified-ABI migration.
- Finish the ordinary application suite on both targets. A CPC-only success,
  or a universal CPC app paired with its old native MSX executable, does not
  complete a migration. Close MSX portable-service and application gaps as
  part of the same work, not as an unspecified follow-up after CPC restoration.
- Native boot/root components and system modules may remain target builds.
  This does not exempt File Manager or Settings from application migration.
- Common functionality must survive the CPC's four-colour display. MSX video,
  sprite and other hardware extensions may differ through documented runtime
  capabilities and explicitly agreed hardware substitutions.
- Both targets assume at least 512 KiB RAM. Existing memory, ownership and
  compatibility constraints remain unless changed through a separate review.
- PCW remains a later implementation, as in the existing migration plan. Keep
  the ABI suitable for its monochrome renderer; v1.0 does not claim PCW support.
- Product **v1.0**, the current experimental **ABI 2.1**, **GBAP v4**, and the
  frozen **GEMBENCH-1** resource/window contracts are different version axes.
  This roadmap does not renumber or freeze an ABI by itself.

Keep the GEOBENCH name, blue/white/black/red identity and BSD-3-Clause licence.
No silently reduced application or successful unsupported-operation stub counts
as parity. Any proposed release-scope exception needs explicit agreement and
must remain visible in the acceptance ledger.

## Accepted baseline

### MSX2: functional reference, partial ABI migration

The [MSX distribution builder](../tools/build_kernel_msx.sh) currently stages
a mixed application suite. Only **Clock and Calculator are production apps
using the unified ABI**; ABIProbe is an additional universal diagnostic.

| Application group | Current MSX2 distribution status |
| --- | --- |
| Clock, Calculator | Universal APPs, also used unchanged on CPC. |
| ABIProbe | Universal conformance diagnostic, not a production-app migration. |
| Notepad, File Manager, Settings, Shell, Disk Utilities | MSX-specific application builds; migration remains. |
| PAINT, Viewer, Icon Editor, BASIC/BASRUN | MSX-specific application builds; portable document/page services and migration remain. |
| FormRef, GBRDEMO, XAOS, Mahjong, networking apps, sound test, savers | MSX-specific builds; service binding, migration and per-app acceptance remain. |

An `.APP` suffix, shared source, or use of the newer GEM/SymbOS-inspired kernel
services does not establish unified-ABI compliance. Desktop, kernels and
hardware/system providers are classified separately from ordinary applications.
Existing MSX functionality must survive migration; this inventory does not
claim that every existing app has already passed a v1.0 release-level audit.

### CPC: accepted M4 desktop, partial feature coverage

The four desktop-first sprints and appearance-only Settings integration are
merged and manually accepted. CPC currently delivers:

- the shared Desktop and window-management foundation, focus/stacking,
  visible-region damage, background Clock updates and visibility-ranked workers;
- M4/Disk C browsing with independent File Manager contexts, list/icon views,
  persistent View preference and qualified application launch/return;
- unified Clock and Calculator, with identical CPC/MSX executable payloads;
- native, build-matched File Manager and six-row Settings: font, icons, cursor,
  title bar, gadgets and backdrop, including verified configuration persistence.

ABI Probe and other portable probes provide diagnostic coverage; they are not
a substitute for ordinary application workflows. The current normal CPC image
contains Clock and Calculator as universal apps; File Manager and Settings are
still native binaries. Desktop is a target-linked root/system component.

Latest integration evidence: **28 delivery scenarios / 323 pixel checkpoints**,
an independent 32-checkpoint stacking repeat, **285 host tests**, remaining
SDK/native/distribution checks and openMSX Screen 6/7 accessory checks passed.
The preceding private Settings gate passed 20 scenarios / 316 checkpoints,
including storage faults and selector/lifecycle stress. See the
[Settings integration record](CPC-SETTINGS-INTEGRATION.md) for exact artifacts,
hashes, guarantees and limits. These results qualify that baseline only.

## Completion rule for each migration

Each application milestone must provide separate evidence for all three:

1. **MSX2 completion:** migrate the real application and its required services,
   preserve supported behavior, and validate the applicable Screen 6/7 paths.
2. **CPC completion:** run that same built application against the shared policy
   and CPC adapters, qualifying the equivalent workflows on M4/Albireo media.
3. **Unified delivery:** compare APP hashes in both staged distributions, run
   normal Desktop launch/document/close workflows, and record any remaining
   capability gaps explicitly. Test privately before replacing accepted media.

Start the application acceptance ledger in milestone 1 and maintain it through
the release gate. Record current native/universal status, service dependencies,
MSX2 results, CPC results and exact artifact hashes. A behavior already present
in native MSX code still needs validation in its universal replacement.
Intermediate checkpoints may pass on one target while the milestone remains
open; a target-specific stub or a diagnostic alone cannot close it.

### Stability is a requirement throughout, not just at release

Use the accepted CPC desktop's interaction and stress scenarios as a starting
point for equivalent MSX checks, with target-specific rendering oracles and
timing budgets. The user's positive CPC experience is not evidence that every
unported application or hardware configuration is already stable.

- Establish an MSX Screen 6/7 stability baseline at the start of milestone 1,
  using the currently delivered apps before migration. Record reproducible
  failures and fix relevant shared-core or MSX-adapter defects; do not preserve
  a known bug merely because MSX supplies the older behavior reference.
- In every milestone, check pointer responsiveness with Clock seconds enabled,
  focus/drag/overlap and partial repaint, repeated launch/close, modal recovery,
  storage failures and owner/page/context cleanup as applicable. No hangs,
  reboots, visual corruption or resource leaks in the qualification workloads.
- Preserve the accepted CPC behavior as the suite grows. Shared changes require
  relevant regressions on both targets; neither app count nor ABI conversion
  alone takes precedence over stability. Define measured per-target latency
  budgets rather than requiring equal elapsed times from different graphics
  hardware, and include manual checks of smoothness on both.

## Ordered milestones

These are outcome-based work packages, not time estimates or new historical
milestone numbers. Milestone 1's initial stability/inventory checkpoint
[issue #82](https://github.com/salvogendut/GEMBENCH/issues/82) is closed;
Notepad's portable service bindings are **in progress** in
[issue #84](https://github.com/salvogendut/GEMBENCH/issues/84).
The actual unified editor and milestones 2–8 are not delivered. Use one
bounded issue/branch per implementation package and split internally where
dependencies require it; do not expand the scope without recording the change.

| Order | Deliverable | Completion criterion |
| --- | --- | --- |
| 1 | Unified Notepad and document services | One Notepad APP performs real open/edit/save/copy/paste/close workflows on MSX2 and CPC, preserving dirty-document and error handling. |
| 2 | Portable resources, forms and owned page/code services | Identical GBRDEMO/FormRef APPs run on MSX2 and CPC, with resource validation, form interaction and owned secondary-code lifecycle qualified on both. |
| 3 | Unified Settings and File Manager | Replace their separate target application builds with identical APPs; preserve MSX behavior and the accepted CPC profile through explicit runtime capabilities. |
| 4 | Complete boot, desktop and file workflows | Restore the CPC boot splash; both distributions support file operations, document associations, Trash, qualified-app launching, palette/wallpaper/defaults, media refresh and firmware return; Shell/Disk Utilities use the unified ABI. |
| 5 | Paged and multi-window applications | PAINT, Viewer, Icon Editor and bundled BASIC application components use portable services and identical APPs, with full lifecycle and file workflows qualified on both targets. |
| 6 | Remaining applications and platform services | Complete the remaining unified apps and qualify networking, sound, games, savers and Settings' saver controls on MSX2 and CPC through real providers. |
| 7 | Storage/input coverage and independent confirmation | Qualify each target's advertised storage/input and hardware profile, including CPC Albireo and a second permitted CPC emulator, plus MSX Screen 6/7 regression coverage. |
| 8 | Release candidate, SDK contract and distributions | Close both target acceptance records and the migration/parity ledger; qualify exact MSX2 and CPC release artifacts and obtain manual acceptance for both. |

The application path is 1 -> 2 -> 3 -> 4 -> 5 -> 6. Qualify shared services
before their consumers, including services first required by a later milestone.
Milestone 7 can progress alongside application migration once separately
authorized; start independent confirmation early enough to inform the work.
Milestone 8 depends on the completed application and hardware/backend gates.

**2026-09-09 dependency finding:** the actual Notepad integration's full link
requires 28857 bytes, beyond the 16128-byte primary allocation; even its loaded
code/startup exceeds that limit. See [checkpoint 2c](UNIFIED-NOTEPAD.md#checkpoint-2c--real-editor-integration-and-failed-full-link-gate-2026-09-09).
The next design/implementation package must bring forward the minimum owned
data/secondary-code services from milestone 2, then resume Notepad acceptance.
This does not start all forms/resources work or change the completion criteria.

### 1. Unified Notepad and document services — portable bindings in progress

The [MSX baseline](V1-MSX-STABILITY-BASELINE.md) and
[application migration ledger](V1-APPLICATION-LEDGER.md) are now recorded.
The observed short Desk-click, Omega/RainBIOS bitmap-mode and 1983 first-read
blockers are resolved in GEMBENCH PR #83, RainBIOS PR #171 and 1983 PR #172.
The baseline's dated close-out distinguishes these passing bounded checks from
remaining whole-distribution release coverage. The
[Notepad audit](UNIFIED-NOTEPAD.md) records the real native memory limit and the
first tested portable I/O helper. Typed clipboard now has a shared kernel/SDK
binding, qualified by the same diagnostic APP on CPC/M4 and MSX Screen 6/7
using openMSX and 1983. The owned portable chooser/content panel also passes
navigation, naming, cancellation and selected-file readback with identical APP
bytes on those targets. Its Save As diagnostic does not write; real editor and
dirty-document recovery remain, as does a CPC provider gap for dotted directory
names and wider filename punctuation. The actual editor/controller is now
integrated in candidate source with host tests, but its complete link is rejected
for memory overflow. The first [owned data-page slice](PORTABLE-PAGES.md) now
passes private MSX Screen 6/7 and CPC/M4 qualification with identical APP bytes.
The shared [secondary streaming core](PORTABLE-SECONDARY-CODE.md) now passes
instruction-level fault/rollback tests, but receiver stream adapters, full
launch qualification and the sealed call gate remain before editor runtime testing.
The delivered editor is still native; no normal
image has been replaced and no unified Notepad runtime acceptance is claimed.

#### Saved checkpoint and remaining delivery path — 2026-09-09

The user requested saving, committing and pushing the current #84 checkpoint
before further implementation because the remaining weekly token allowance is
limited. Resume on `feature/84-unified-notepad`; this is not a merge or release.
See [the session handoff](SESSION-HANDOFF.md) for durable working memory and
evidence. Approximately **four substantial work packages** remain, not four
guaranteed sessions:

1. **Production package loading:** measured fixed code/state placement,
   single-open storage adapters, normal-launch rollback and interrupt-safe
   progress. The shared streaming fixture is complete; receiver integration is
   not. Bring up MSX first without forking the shared policy or weakening bounds.
2. **Validated secondary calls:** sealed owner/page/entry identity, copied
   arguments/results, safe bank/stack/interrupt restoration, teardown and the
   restricted SDK/packaging support. No executable call gate exists yet.
3. **Actual editor integration:** partition the existing editor/model and state,
   pass the full linked-memory gate, and finish document/desktop handoff and
   configuration behavior. Preserve 4 KiB documents, dirty recovery and the
   existing editing features. This is the first expected manually testable MSX
   Notepad checkpoint, not yet distribution acceptance.
4. **Qualification and delivery:** open/edit/save/reopen, clipboard, failures,
   responsiveness, repaint and lifecycle on MSX Screen 6/7 with openMSX/1983;
   qualify identical APP bytes on CPC/M4 and close its known name/path gap.
   Replace normal delivery only after both acceptance records pass.

A first MSX build is the near-term priority; full CPC editor acceptance follows,
not a removal of CPC from scope. Shared receiver changes still require relevant
cross-target regressions. The first two packages carry the greatest uncertainty:
a runnable MSX editor within the remaining allowance is a stretch goal, not a
promise. Defer unrelated resource/forms work and preserve a resumable checkpoint
if another architectural obstacle appears. Normal media and native Notepad stay
intact until their replacements are qualified.

Use the existing Notepad implementation and preserve its supported behavior.
Audit dependencies and linked code/data/stack headroom first; bind its required
portable filesystem, chooser, clipboard and document-open services on both
targets. Reuse the existing owned filesystem and shell policy.
Establish the application ledger and MSX native behavior checks first, migrate
Notepad through the universal MSX path, then qualify the identical APP on CPC.
Missing portable services on either target belong to this milestone.
The initial MSX stability checks above are the first checkpoint; carry the same
checks forward to the migrated Notepad/Clock/Calculator workload.

Acceptance includes:

- opening a real file, editing it, saving, reopening and checking exact bytes;
- clipboard exchange between two editors, including wrong-type rejection;
- unsaved changes, cancel, failed open/write and full-resource recovery;
- minimal File Manager document handoff and suitable live-editor reuse without
  losing dirty content; broader file associations belong to milestone 4;
- focus, overlap, background Clock activity and clean owner/context teardown.

Copy the same built APP into MSX2 and CPC test media and compare its hash.
Do not substitute a reduced CPC editor or call a compile-only audit completion.

### 2. Resources, forms and portable memory/code services

Bring the required shared GBR/form/menu/semantic drawing interfaces through
the unified boundary. The owned data/secondary-code prerequisite now needs to
precede Notepad delivery (the checkpoint 2c link provides the evidence). Keep
that prerequisite bounded; subsequent resources/forms work starts with GBRDEMO
and form interaction, then qualifies FormRef's complete resource/code behavior.

The underlying allocator or native secondary mechanism is not proof that its
public portable service exists. Provide checked ownership/entry/bank-restoration
interfaces before enabling the corresponding app or capability. Specify and
review any required package extension against the ABI authority; do not assume
v4 external resource/code segments are already implemented.

Exit includes corrupt-resource rejection, fields, checkbox/radio/default/cancel
behavior, keyboard focus, clipped raster rendering, page exhaustion/recovery,
and stale/foreign/nested/worker secondary-call rejection. Preserve the frozen
GBR1 and managed-window contracts and test the actual target readers/renderers.

### 3. Unified Settings and File Manager

Remove target defines, private memory addresses and target-specific application
bindings from the migrated build. Expose required configuration, appearance,
filesystem, UI and launch functions as reviewed portable services.

The same executable must preserve the full supported MSX path and the accepted
CPC path. Remaining CPC capabilities stay explicitly unavailable until their
providers are qualified in subsequent milestones; their absence still blocks
final parity. In particular, this milestone must not silently shrink MSX
Settings to the current six-row CPC profile.

Retain the existing persistence, modal recovery, independent directories,
resource menus, context-exhaustion and mixed-window regression scenarios.
Retire build-specific File Manager/Settings admission exceptions only after
the universal replacements pass and are staged into both distributions.

### 4. Boot, everyday file, desktop and settings completeness

Preserve existing MSX workflows through the unified applications while closing
the corresponding CPC gaps. Validate both normal distributions, not just the
CPC implementation of an operation that used to work in native MSX code.

- **Reintegrate the CPC boot splash** into the normal boot/distribution path,
  reusing the existing GEOBENCH artwork and four-colour identity. Qualify cold
  boot, correct palette/geometry and a clean transition to the configured
  Desktop, with no leftover graphics, memory/IRQ damage or unnecessary delay.
  If splash asset loading is required, a missing/corrupt optional asset must
  not prevent desktop startup. Test on M4; include Albireo at its qualification
  gate. Preserve and recheck the existing MSX Screen 6/7 splash as well.
- Restore copy/move/delete, drag-and-drop, Trash and embedded application-icon
  handling, including cancellation, collisions, I/O errors and resource cleanup.
- Replace the current CPC filename/location launch allowlist with validated
  loading of supported packages from supported paths. Do not re-enable arbitrary
  old target binaries or bypass the loader transaction.
- Complete data-file associations and document-open/activation conventions.
  Migrate Shell/Disk Utilities to identical APPs using the shared application
  implementations, with capability-checked target storage operations.
- Complete palette editing, wallpaper/PIC-backed appearance and reset defaults.
  Saver selection/configuration joins the real saver runtime in milestone 6.
- Qualify media refresh and return to firmware, including device/bank/interrupt
  restoration. Wider backend and hotplug behavior is closed in milestone 7.

Verified writes currently do not promise atomic replacement or power-loss
rollback. Keep failure semantics explicit and test them; any stronger guarantee
requires a real storage implementation and its own validation.

### 5. Paged and multi-window applications

Migrate Viewer, Icon Editor, PAINT and the in-tree BASIC components using
canonical document surfaces and owned page/resource operations. Hardware-aware
system modules may differ; common application behavior must not depend on
private mapper tables, framebuffer addresses or target-specific line mailboxes.

PAINT is the decisive multi-window test: Toolchest, Preview and Canvas share
one application owner; tool selection, drawing, selection movement, undo,
load/save, pane close/reopen and final quit preserve content and ownership.
Recheck focus/exposure and component-only damage without unnecessary whole-screen
repainting. Qualify larger documents and safe exhaustion as well as small demos.

For BASIC, cover editor -> runtime/engine -> program execution -> return to
Desktop, example programs, memory reservations, errors and cancellation.
Keep all source in this repository and distinguish portable applications from
any explicitly justified target engine/provider components.

### 6. Networking, sound and the remaining suite

Complete the migration ledger for XAOS, Mahjong, sound tests, networking
applications and all shipped savers/configuration modules. Networking includes
NETSVC, Telnet, Browser and BRSAVE, with a CPC transport behind the appropriate
portable services and the existing shared manager/lifecycle policy.
Replace the ordinary MSX target builds as well as delivering their CPC peers;
retain target-specific code only in explicitly classified system/providers.
Qualify existing MSX networking, audio and saver behavior through the migrated
clients alongside the new CPC providers.

Check both supported-hardware success and typed unavailability. Cover request
failure/cancel, multiple clients, lease cleanup and last-client unload; do not
claim shared sockets merely because the service manager works.

Supply the required CPC sound and saver graphics/time/input services. Saver
acceptance includes idle entry, Settings selection/configuration/timeout,
wake-up and exact restoration of live desktop/application state. Retain the
individual saver list in the reference ledger rather than counting one saver
as completion of the suite.

### 7. Storage, input and independent confirmation

Cover both advertised release configurations; CPC backend qualification does
not replace MSX release validation.

- Requalify MSX Screen 6/7, supported MSX-DOS2/Nextor storage configurations,
  input and advertised hardware capabilities with the migrated suite. Use
  openMSX for independent confirmation alongside 1983, and record real-hardware
  evidence and any coverage gaps for the supported MSX configuration.
- Qualify Albireo separately from M4. Deliver reproducible CARD/backend packaging
  and test the actual transport, not an equivalent-looking floppy filesystem.
- Complete supported drive selection, refresh/media-change behavior and defined
  failure/recovery on absent or changed media. Record supported hardware limits.
- Qualify actual mouse protocols and keyboard repeat/modifier/text behavior,
  alongside the existing keyboard/joystick pointer and responsiveness checks.
- Qualify a second emulator through the same memory, IRQ, graphics and storage
  scenarios before using it for application acceptance. Follow the existing
  [emulator strategy](CPC-EMULATOR-TEST-STRATEGY.md); 1984 is the current proved
  M4 runner, not evidence that the other emulators or Albireo already work.
- Obtain real-hardware confirmation on both targets for the advertised memory,
  input and storage configurations. Independent emulator agreement is supporting
  evidence, not a replacement for board testing; unsupported configurations
  must not be implied by the release claims.

CPC runtime testing remains **M4- or Albireo-backed only**, never floppy-backed.
Sibling emulator changes require their own authorization, issues and branches;
this document does not authorize starting them.

### 8. Release candidate and v1.0 acceptance

- Close the application ledger maintained since milestone 1, with columns for
  shared source, unified binary, MSX2 acceptance, CPC acceptance, backend coverage
  and remaining exceptions. Reconcile it against the shipped app/module/saver list.
- Close the required R01-R18 rows in the
  [MSX2 behavioral reference](CPC-RESTART-MSX2-REFERENCE.md), or record an
  explicitly agreed hardware substitution. Host checks and probes do not replace
  application-level runtime evidence.
- Run the combined regression and repeated open/edit/save/close, low-memory,
  storage-failure, stale-handle and mixed-window workloads on exact release
  artifacts. Record hashes, toolchain/ROM/backend versions and stack/memory
  high-water marks. Set measured timing budgets without requiring CPC software
  rendering to match VDP elapsed times.
- Verify every migrated APP hash across both media, review capability/version
  negotiation and ABI compatibility, and document the supported SDK with build,
  resource, storage and lifecycle examples. Freeze only the reviewed contract.
- Package reproducible MSX2 and CPC distributions, installation/upgrade and
  manual-test instructions, release notes, hardware coverage and known limits.
  Preserve user configuration/data; do not overwrite accepted cards during tests.
- Obtain final manual acceptance of **both MSX2 and CPC distributions** before
  proposing the v1.0 release/tag. A completed CPC restart or unchanged legacy
  MSX image alone cannot satisfy this release gate. Include the restored CPC
  boot splash and the stability/responsiveness workloads, not just app launches.

## Work discipline and scope control

Keep issues/branches bounded and reviewable; implementation, regressions,
documented evidence and user-facing testing belong to each milestone.
Qualify on private media before replacing the normal manual image. Preserve the
working MSX reference, parked CPC code/media, and user recordings.

Track **MSX2 completion**, **CPC completion/feature parity** and **unified-ABI
migration** separately. A native application can satisfy some behavior tests
without being portable; a universal probe can validate the ABI without providing
the application's functionality. None substitutes for the others at the v1.0
exit. Preserve MSX as the behavior reference while actively finishing its own
universal distribution; it is not merely a regression target for the CPC port.

The earlier four-sprint desktop milestone is complete and is not reopened by
this roadmap. PCW restoration, speculative architecture improvements beyond
the supported MSX reference, and unreviewed ABI/package features are not silently
added to v1.0. This document sets the plan; it does not open issues, start code
changes, promise a date, or authorize a release.

## Reference documents

- [CPC restart and accepted desktop sprints](CPC-RESTART-PLAN.md)
- [MSX2 feature reference and application ledger](CPC-RESTART-MSX2-REFERENCE.md)
- [Accepted CPC Settings integration](CPC-SETTINGS-INTEGRATION.md)
- [Unified ABI design](UNIVERSAL-APPLICATION-ABI.md) and
  [migration gates](UNIVERSAL-APPLICATION-ABI-MIGRATION.md)
- [M4/Albireo emulator qualification strategy](CPC-EMULATOR-TEST-STRATEGY.md)

Next implementation package: **milestone 1 — unified Notepad and the document
services it needs** ([issue #84](https://github.com/salvogendut/GEMBENCH/issues/84)),
next binding/qualifying the fixture-tested secondary stream loader on both
receivers and implementing its sealed call gate, then finishing the editor's portable bindings
and qualifying identical MSX2/CPC application artifacts.
