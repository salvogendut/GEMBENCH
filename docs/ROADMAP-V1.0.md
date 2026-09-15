# GEOBENCH roadmap to v1.0 — MSX2 and CPC

Recorded 2026-09-08, after the CPC Settings integration merged in
[PR #80](https://github.com/salvogendut/GEMBENCH/pull/80), commit `1408e51`.
This is the forward plan for **finishing both the MSX2 and CPC distributions**:
complete the unified-ABI application migration on both, close CPC feature gaps,
and qualify both release images. Scope clarified with the user on 2026-09-08.
It is not a release announcement or a claim that the remaining features are
implemented.

Updated 2026-09-14 after issue #84's final closure sprint: the editor is
delivered on both targets, safe live TXT/CFG reuse and bounded live
configuration publication are qualified, real BASIC CRLF round trips pass on
both targets, and CPC filesystem paths now match the portable chooser's bounded
8.3 grammar. Milestone 1 is complete; milestones 2–8 remain open.

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
a mixed application suite. **Clock, Calculator, Notepad, GBRDEMO and FormRef use the unified
ABI**; ABIProbe is an additional universal diagnostic. Notepad's normal delivery
checkpoint is recorded in [UNIFIED-NOTEPAD-DELIVERY.md](UNIFIED-NOTEPAD-DELIVERY.md).

| Application group | Current MSX2 distribution status |
| --- | --- |
| Clock, Calculator, Notepad, GBRDEMO, FormRef | Universal APPs, also used unchanged on CPC. GBRDEMO reads the same external `HELLO.GBR`; FormRef embeds the same GBR1 and carries the same sealed GBS4 bank. |
| ABIProbe | Universal conformance diagnostic, not a production-app migration. |
| File Manager, Settings, Shell, Disk Utilities | MSX-specific application builds; migration remains. |
| PAINT, Viewer, Icon Editor, BASIC/BASRUN | MSX-specific application builds; portable document/page services and migration remain. |
| XAOS, Mahjong, networking apps, sound test, savers | MSX-specific builds; service binding, migration and per-app acceptance remain. |

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
- unified Clock, Calculator, Notepad, GBRDEMO and FormRef, with identical CPC/MSX executable payloads;
- native, build-matched File Manager and six-row Settings: font, icons, cursor,
  title bar, gadgets and backdrop, including verified configuration persistence.

ABI Probe and other portable probes provide diagnostic coverage; they are not
a substitute for ordinary application workflows. The current normal CPC image
contains Clock, Calculator, Notepad, GBRDEMO and FormRef as universal apps; File Manager and Settings are
still native binaries. Desktop is a target-linked root/system component.

Pre-Notepad integration evidence: **28 delivery scenarios / 323 pixel checkpoints**,
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
Notepad's editor and normal MSX2/CPC delivery are **complete** under
[issue #84](https://github.com/salvogendut/GEMBENCH/issues/84). Its follow-up
sprints add safe reuse, live configuration publication, real BASIC newline
round trips and a portable CPC path grammar; the
[closure record](UNIFIED-NOTEPAD-CLOSURE.md) accounts for every acceptance row.
Milestone 2 is also complete: the byte-identical GBRDEMO/resource and two-bank
FormRef packages are delivered and qualified on both targets. Milestones 3–8
are not delivered. Use one
bounded issue/branch per implementation package and split internally where
dependencies require it; do not expand the scope without recording the change.

| Order | Deliverable | Completion criterion |
| --- | --- | --- |
| 1 | **Complete — unified Notepad and document services** | One identical Notepad APP performs real open/edit/save/copy/paste/close/reuse/configuration and BASIC/config newline workflows on MSX2 and CPC; all #84 acceptance rows pass. |
| 2 | **Complete — portable resources, forms and owned page/code services** | Identical GBRDEMO/FormRef APPs are delivered on MSX2 and CPC, with exact resources, form interaction and sealed owned secondary-code lifecycle qualified on both. |
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

**Resolved prerequisite, 2026-09-14:** the initial full link required 28857
bytes, beyond the 16128-byte primary allocation; see [checkpoint 2c](UNIFIED-NOTEPAD.md#checkpoint-2c--real-editor-integration-and-failed-full-link-gate-2026-09-09).
Minimum owned data/secondary-code services were brought forward from milestone
2 and are now exercised by the delivered two-segment editor. The original
memory limits and 4096-byte editable capacity remain intact. This prerequisite
and the subsequent GBRDEMO/FormRef migrations now complete milestone 2; they
do not complete later application or release milestones.

### 1. Unified Notepad and document services — complete

**Completed 2026-09-14:** the user-approved Escape → acceptance →
normal-delivery sequence is complete on #84 and merged. Issue #84 sprint 1
adds safe existing-instance document reuse on both targets: exact copied
identity, dirty Save/Discard/Cancel, busy fallback and context-full rollback
pass focused and real-emulator gates. Sprint 2 adds a bounded compile-once
configuration-publication service and exact `GEOBENCH.CFG` save integration,
qualified in MSX Screen 6/7, openMSX and CPC/M4. One identical 20521-byte
Notepad APP is now in the normal MSX2 and CPC images, with exact-path TXT/CFG
handoff, direct APP launch, editing/arrows, bounded repaint, chooser/save,
cross-owner clipboard and guarded Quit. CPC read-only/full-volume failure and
occlusion/cleanup checks pass; normal-image workflows pass in 1984/M4 and both
MSX screen modes in openMSX/1983. See the
[delivery record](UNIFIED-NOTEPAD-DELIVERY.md) for the original 35 CPC scenarios,
the [reuse sprint record](UNIFIED-NOTEPAD-REUSE.md), and the
[configuration sprint record](UNIFIED-NOTEPAD-CONFIG.md) for the new service,
bounds and runtime evidence. The original record also contains explicit
corrected-test provenance, MSX checks, hashes and memory limits. The final
[closure sprint](UNIFIED-NOTEPAD-CLOSURE.md) proves a real BASIC CRLF
open/edit/save/reopen sequence on CPC/M4 and MSX Screen 6/7, independently
reruns openMSX, and makes CPC path validation match the portable chooser,
including dotted directories. All issue #84 acceptance rows are satisfied.

File Manager and Settings themselves remain native under milestone 3. The
dated private checkpoints below are historical; their "not staged" status does
not describe the current normal images. Do not mark v1.0 or the remaining
milestones complete.

#### Historical implementation checkpoints (superseded by normal delivery)

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
On 2026-09-13, the opt-in IRQ profile and MSX single-open provider pass a
standalone real-Nextor diagnostic in openMSX and 1983 (checkpoint 2f). This is
progress within remaining package 1, not its completion. Checkpoint 2g now
fits and boots dual admission plus fixed modules in private MSX Screen 6/7
receivers, retaining ordinary app lifecycles in openMSX/1983. The 45 focused
tests pass; no application/stack boundary changed (that checkpoint had 45 bytes
spare in Screen 7). **Checkpoint 2h now connects normal single-open streamed
Desktop launch** on private MSX Screen 6/7: successful two-bank lifetimes and
pointer progress pass in openMSX/1983; bad CRC, truncated and trailing files
reject with exact rollback in openMSX. Ordinary primary-only and Clock/Calculator
regressions also pass. Screen 7 now has 16 bytes spare. **Checkpoint 2i now
qualifies the sealed secondary-call service and restricted SDK** with actual
compiled computation code through Desktop on openMSX and 1983, Screen 6/7.
It retains the same memory bounds. **Checkpoint 2j now brings up the actual
two-bank editor** within the same sprint: its full 4-KiB model and separate
staging fit; real file round trips pass on private MSX Screen 6/7, and 1983
adds full-capacity/oversized-load checks. Space-as-click timing still needs
resolution; existing-instance document/configuration integration and broader runtime
qualification remain. See [the runtime checkpoint](UNIFIED-NOTEPAD-RUNTIME.md)
for precise emulator/input coverage, limitations and testable image paths.
CPC streaming/calls remain deferred. See the secondary-code
record for evidence and the distinction between loading and executing a bank.
**Handoff 2k/2l:** checkpoint 2j was pushed as `e4c8e62`; 2k/2l form the next
document-handoff save on #84's branch. Private File Manager → actual Notepad exact-path document opening now
works, including same names in different directories, save-in-place and failed
launch cleanup. Filesystem API v3 binds adoption to the new owner generation;
the copied identity and staged load publish the title/path only on success.
50 regressions pass; openMSX Screen6/7 edit/save/reopen and 1983 document launches,
failure rollback, full-capacity/oversize and cleanup pass. Normal profiles remain
unchanged. Next: existing-instance delivery/reuse with dirty confirmation,
configuration reload, remaining input and broader UI qualification.
See [the handoff work record](UNIFIED-NOTEPAD-HANDOFF.md).
**Follow-up 2m:** after successful manual MSX tests, plain arrows now navigate
the focused editor and Space types without a pointer click. Ctrl retains
keyboard-pointer access. Ordinary typing damages changed text/caret spans,
not the whole window; the dirty title is updated separately. Both MSX screen
modes pass openMSX navigation/edit/save/reopen; 1983 also covers capacity,
dirty-close and real exact-path handoff. This is the accepted 2m follow-up to
`d950560`, not CPC input support or normal-distribution promotion. Next is the
CPC binding for the same APP, using private M4 media and preserving the accepted
desktop distribution. MSX 2m was committed/pushed as `6e6fe05`.
The [CPC follow-up](UNIFIED-NOTEPAD-CPC.md) qualifies the private single-open
M4 transport (6,058 Z80 calls) and now binds the shared package loader and sealed
calls in the full private Desktop/File Manager/Settings runtime. The existing
two-bank computation APP passes 54 checks / 17 copied calls per launch across
three owner generations in real 1984/M4; invalid loader modules fail boot before
capability publication. All existing memory budgets are retained (18 bytes of
high-kernel headroom at that checkpoint). Receiver checkpoint `3041971` is
committed/pushed. **2026-09-14:** the subsequent private full CPC profile binds
FS identity/owner-bound handoff and focused text input. The unchanged Notepad
APP now passes real File Manager document launch, arrows/Space/backspace,
focus-away/back, in-place save, nested same-name selection and cleanup in
1984/M4. Its high kernel has 229 bytes spare after omitting unused diagnostic
launcher code; no memory limits or editor capacities changed. Next is full
private CPC editor acceptance (capacity, dirty-close, chooser/clipboard,
repaint/occlusion, storage errors). An exploratory manual image is available
under `build/notepad-84/manual-cpc-jB6Idz/` at the user's request. Default receiver
binaries and normal distribution images remain unchanged.
The delivered editor is still native; no normal
image has been replaced. Bounded private runtime evidence is not release acceptance.

#### Consolidated sprint — runnable MSX Notepad, 2026-09-13

The user consolidated the three remaining implementation packages into **one
sprint**, with a manually testable unified Notepad on MSX as its finish line:
normal streamed Desktop loading → validated secondary calls → actual editor
integration and bounded Screen 6/7 testing in openMSX and 1983. These remain
ordered internal tasks, not separate delivery steps or routine approval gates.

The [sprint plan and exit checks](UNIFIED-NOTEPAD.md#consolidated-sprint--runnable-msx-notepad)
preserve the full 4 KiB editor, recovery behavior, shared ABI and memory limits.
Deliver a private image and reproducible manual-test instructions; normal media
stay unchanged. Full MSX/CPC distribution qualification and identical-APP CPC
delivery follow this sprint, with relevant shared-code regressions retained
throughout. This is scope consolidation, not an estimate of one session or a
claim of completed editor delivery. Checkpoints 2h/2i close the internal MSX
loader and validated-call tasks in bounded tests; 2j begins actual editor runtime
qualification. The sprint remains open.

#### Saved checkpoint and remaining delivery path — 2026-09-09

Historical package breakdown; the September 13 sprint above now groups packages
1–3 and their minimum MSX runtime checks into one deliverable. Package 4's full
cross-platform qualification/delivery remains the follow-up.

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

**Checkpoint 2026-09-15:** Sprint 2's compile-once external-resource receiver
is delivered on both normal targets. One 13069-byte `GBRDEMO.APP` passes canonical,
checksum, truncated and oversized resources on CPC/1984/M4 and on MSX Screen
6/7 in both openMSX and 1983, including input/state, drag/overlap, lifecycle,
context/page reclamation and launch-scratch cleanup. Exact CPC framebuffer
comparisons and independent 1983 PPM captures complement the guest-state
checks. The byte-identical APP and canonical 111-byte `HELLO.GBR` are now in
the normal MSX hard-disk/floppy media and CPC M4 image; CPC delivery profile
`cpc-desktop-m4-v5` enforced their identities at that checkpoint. Canonical delivery workflows
also pass on CPC/1984 and MSX/openMSX/1983. See the
[milestone record](V1-M2-PORTABLE-RESOURCES.md#sprint-2-checkpoint-c--normal-msxcpc-delivery).
FormRef was the next ordered consumer and is complete below.

**FormRef checkpoint A, 2026-09-15:** a deterministic 15640-byte primary-only
universal `FORMREF.APP` now embeds the exact 231-byte native resource and links
the address-free portable form/modal profile. Its source/build audit and memory
gate pass without target defines; the native 16026-byte reference and hashes
remain unchanged. Normal media and the secondary-code contract are unchanged.
Private MSX Screen 6/7 and CPC M4 form workflows are next, followed by the
computation-only GBS4 secondary conversion. See the
[Sprint 3 record](V1-M2-PORTABLE-RESOURCES.md#sprint-3-checkpoint-a--compile-once-primary-formref).

**FormRef checkpoint B, 2026-09-15:** the byte-identical candidate now passes
its complete private runtime workflow on MSX Screen 6/7 in 1983 and CPC M4 in
1984, with independent Screen 6/7 confirmation in openMSX. Real target input covers field editing, Shift-Tab and forward traversal,
checkbox/radio state, Save/Cancel and pointer activation; managed movement,
exact CPC framebuffer comparison, source-media preservation and complete
window/page/context reclamation also pass. Normal distributions still deliver
the native FormRef; the universal candidate remains private. Sprint 4's sealed
computation-only secondary conversion and delivery are the remaining
milestone-2 work. See the
[runtime record](V1-M2-PORTABLE-RESOURCES.md#sprint-3-checkpoint-b--private-cross-target-runtime-qualification).

**FormRef checkpoint C, 2026-09-15:** one 16160-byte two-bank
`FORMREF.APP` now embeds the frozen 231-byte GBR1 form and carries a 329-byte
computation-only GBS4 secondary. The exact APP is delivered in normal MSX
hard-disk/floppy and CPC M4 media; CPC profile `cpc-desktop-m4-v6` validates
the embedded-resource identity and actual secondary hash. Final Screen 6/7
openMSX runs, 46-check normal-delivery 1983 runs in both modes, and a 21-step
normal CPC/1984 workflow pass form input, recomputation, mapping/seals,
movement and exact cleanup. The shared real-Z80 rejection suite covers
stale/foreign/nested/worker/teardown/entry/length and restoration policy.
This completes milestone 2. See the
[Sprint 4 record](V1-M2-PORTABLE-RESOURCES.md#sprint-4-checkpoint--sealed-secondary-closure-and-normal-delivery).

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

Latest completed implementation package: **milestone 2's portable resources,
forms and owned page/code consumers**, tracked in
[issue #88](https://github.com/salvogendut/GEMBENCH/issues/88) and the
[milestone plan](V1-M2-PORTABLE-RESOURCES.md). GBRDEMO is the first
compile-once external-resource application in both normal distributions and
FormRef closes the same milestone with its sealed computation bank.

Milestones 1/2 are complete; issue #88 tracks the unmerged milestone-2 branch.
The identical editor and both resource/form applications are delivered and
their normal MSX2/CPC workflows are qualified; do not repeat the completed
transport, input, document, resource/form or secondary-call work.
Native File Manager/Settings conversion and CPC boot splash retain their ordered
milestones; this checkpoint does not silently start or complete them.
