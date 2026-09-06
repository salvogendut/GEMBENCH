# CPC restart plan

Started: 2026-09-05. Tracking issue: [#63](https://github.com/salvogendut/GEMBENCH/issues/63).
Step-1 branch: `feature/cpc-restart-reference`.

Progress: step 1 is complete. Step 2 has begun with
[owner/page extraction 2A](CPC-RESTART-STEP2A.md) under issue #64: byte-identical
MSX2 kernels, passing host checks and before/after openMSX lifecycle validation.
Step 3 has begun independently: [memory/interrupt package 3A](CPC-RESTART-STEP3A.md)
is complete under issue #65. The [3B graphics/parameter proof](CPC-RESTART-STEP3B.md)
is implemented under #66; [public ABI/SDK/runtime adoption](CPC-RESTART-STEP3B-ABI.md)
is complete on MSX2 under #67, with Screen 6/7 regressions.
[Runtime M4 I/O 3C](CPC-RESTART-STEP3C.md) is implemented and validated in
1984 under #68: bounded staging, exact file bytes and failure/restoration checks.
[Window/application lifetime 2B](CPC-RESTART-STEP2B.md) is extracted on MSX2
under #69: unchanged kernel bytes, independent provider assembly checks, and
before/after application lifecycle regressions. [Focus/z-order 2C](CPC-RESTART-STEP2C.md)
is extracted under #70, with unchanged normal/cooperative kernels and explicit
before/after stacking assertions. [Visible regions/worker priority 2D](CPC-RESTART-STEP2D.md)
is extracted under #71 with byte-identical scheduler code. The Clock poll-sampling
correction and accessory pre-click snapshot guard were validated separately.
[WM damage/repaint 2E](CPC-RESTART-STEP2E.md) is extracted under #72, including
move/resize and focus damage, explicit/window clips and bottom-up repaint
dispatch, with unchanged normal/cooperative MSX2 kernels.
[Deferred messages/timer collector 2F](CPC-RESTART-STEP2F.md) is extracted under
#73, retaining byte-identical kernels, timer object and Desktop payload.
[Filesystem contexts/service bookkeeping 2G](CPC-RESTART-STEP2G.md) is extracted
under #74: paged context policy, resident owner cleanup and app-linked service
state have explicit providers, with unchanged kernels/module/application bytes.
[Client/timer/parameter boundaries 2H](CPC-RESTART-STEP2H.md) are extracted
under #75: filesystem client storage (including the public batch accessor),
native timer publication and receiving-side `GB_PARAMS` policy have explicit
providers. Universal SDK records/bridge and APP hashes remain unchanged.
[Context/IRQ boundary 2I](CPC-RESTART-STEP2I.md) is extracted under #76:
shared Z80 snapshots, register frames, task startup and IRQ dispatch use explicit
MSX2 state/bank/interrupt providers. All eight scheduler variants are unchanged
byte-for-byte. [Production-address integration 3D-A](CPC-RESTART-STEP3D.md)
is implemented under #77: checked fixed allocations, firmware-safe M4 takeover,
512-KiB admission, the same shared context/visibility scheduler, raw keyboard
input and software ticks execute together in 1984. The production adapter gate
is **not complete**. [Drawing/parameter integration 3D-B](CPC-RESTART-STEP3D-B.md)
now runs the same parameter, owner/page and window-identity code with CPC
line/text/pointer primitives: 58 cases and 26 exact framebuffer checkpoints
pass alongside M4/IRQ work. [Focus/stacking/damage integration 3D-C](CPC-RESTART-STEP3D-C.md)
adds the unchanged shared compositor with CPC physical clipping and pointer
locking: 16 exact pixel/write/dispatch checkpoints pass on M4/1984. Its native
records, chrome and menu sinks are fixtures, not a loaded application.
[Lifetime/owner cleanup 3D-D](CPC-RESTART-STEP3D-D.md) now runs the shared close,
owner reclaim, message purge and logical FS cleanup paths with 16 M4 checkpoints.
It also fixes the shared stale-close caller's missing status-to-flags check.
[Native registration/chrome 3D-E](CPC-RESTART-STEP3D-E.md) now uses the same
registration, managed-kind and plain furniture code on both targets. Sixteen
M4 checkpoints cover publication, mixed-kind background painting, exhaustion,
cross-owner slot reuse and cleanup. The shared kind lookup and title bounds
are corrected on MSX2 too. Themed tiles and input routing are not yet linked.
[Deferred/timer composition 3D-F](CPC-RESTART-STEP3D-F.md) connects the shared
deferred API/FIFO, owner service lookup, bounded post-input dispatch phase and
unmodified app-linked timer collector. Sixteen M4 checkpoints cover replies,
activation, real worker publication, partial/hidden damage and receiver drops.
The root driver is still a diagnostic fixture, not an interactive event loop.
[Input/root-loop integration 3D-G](CPC-RESTART-STEP3D-G.md) replaces that scripted
driver with the actual shared MSX root loop and native frame/gesture/menu router.
Fourteen real-keyboard M4 checkpoints cover focus, menu/deferred delivery,
move/resize, maximise/restore, hidden worker suspension and close notifications.
Content, menu definitions and the bar remain fixtures; no public APP loader yet.
[M4 launch/admission integration 3D-H](CPC-RESTART-STEP3D-H.md) now shares the
MSX loader transaction and package validator with a bounded CPC M4 reader.
Seventeen transactions cover rejection, allocator exhaustion/recovery, exact
load bounds and native registration/close. This is a separate diagnostic link,
not public SDK execution.
[Read-only filesystem contexts 3D-I](CPC-RESTART-STEP3D-I.md) now loads the
unchanged shared context policy as a paged M4 module behind the shared resident
implicit-owner/worker gate. Forty-five checkpoints cover independent paths and
reads, stale handles, launch handoff, unsupported operations and owner cleanup.
[Directory checkpoint 3D-J](CPC-RESTART-STEP3D-J.md) now passes the 15-command
protocol probe and 44 shared-context directory checkpoints after the separately
authorized [1984 M4 fix #289](https://github.com/salvogendut/1984/issues/289).
The private adapter supports bounded independent cursors, first/next/batches,
actual short aliases, 32-bit sizes and error reporting distinct from EOF.
The existing 45 read-context checks still pass; MSX module bytes are unchanged.
[Write/free checkpoint 3D-K](CPC-RESTART-STEP3D-K.md) now passes 45 M4-backed
checkpoints: shared offset-zero replacement/nonzero append semantics, zero-length
writes, multi-chunk readback, owner validation and free-space accounting. The
existing fixed storage gate supplies the hardware transactions. Full owner
filesystem-context services and public SDK execution are still open.
Directory namespace/replay limits are recorded
in 3D-J; passing this fixture is not a claim of complete filesystem parity.
[Unified runtime checkpoint 3D-L](CPC-RESTART-STEP3D-L.md) now composes the
shared root loop, loader, compositor, owner/page state and paged FS module in
one budgeted M4 image. The unchanged universal ABI Probe opens, draws, gains
focus, moves and closes; two overlapping instances pass exact-pixel exposure
checks. This is an early first-window integration proof, not completion of all
production adapters. Public menu/service bindings and qualification
of real application workers/timers still precede Desktop integration.
[Portable filesystem checkpoint 3D-M](CPC-RESTART-STEP3D-M.md) now binds the
same caller-owned request on CPC and MSX2, retaining the shared context/client
policy. One byte-identical `FSPROBE.APP` passes 46 checks on CPC/M4 and MSX2
Screen 6/7. Native MSX calls remain unchanged; CPC applications no longer need
MSX framebuffer-aliasing buffers to use filesystem contexts.
[Shared Desktop bar checkpoint 3D-N](CPC-RESTART-STEP3D-N.md) now compiles the
actual Desktop bar/refresh policy into the CPC root and uses the same native
menu publication code as MSX. Ten M4 exact-pixel checkpoints cover real APP
menus, popup selection/cancel and focus/close restoration. MSX kernel/Desktop
extraction builds are byte-identical. Desk/accessory service and the complete
Desktop/File Manager remain pending; this is not a replacement CPC shell.
[Accessory checkpoint 3D-O](CPC-RESTART-STEP3D-O.md) now binds the existing
shell service and Desktop exact-activation policy. The unchanged MSX Calculator
passes CPC/M4 arithmetic, menus, dragging, full-window activation and lifecycle
checks. Normal C-stack deferred records are admitted with explicit bounds;
MSX kernel/Desktop extraction bytes remain unchanged. Clock's real worker/timer
integration is next; the complete Desktop and Desk menu still follow.
The experimental launcher does not enable a CPC desktop.
Shared policy/context extraction does not establish CPC adapter correctness;
the complete memory/adapter gate still precedes desktop integration.

## Execution order agreed on 2026-09-06

| Order | Work package | Exit before advancing |
|---|---|---|
| 1 | Context/IRQ boundary — [2I](CPC-RESTART-STEP2I.md), #76 | Shared mechanism on working MSX2, fixed-state/snapshot contracts, unchanged binaries and real IRQ-switch regressions. |
| 2 | Production CPC memory layout and adapters — [3D](CPC-RESTART-STEP3D.md), #77; 3D-A through 3D-O checkpoints implemented, final public-service integration pending | One budgeted map for the actual shared core, all state, modules, stacks, app aperture and framebuffer; bank/IRQ, input, time, graphics/text/line/pointer and storage adapters validated together on M4. Reuse 3A/3B/3C hardware proofs, not their provisional addresses. |
| 3 | First shared-core window — step 4, initial gate; early runtime proof in [3D-L](CPC-RESTART-STEP3D-L.md), broader adapter gate still open | M4 boot invokes the same lifetime/focus/visibility/damage code; one window opens, draws, gains focus, moves and closes with intact state/stack/bank guards. No alternate CPC WM. |
| 4 | Desktop integration — remaining step 4 and Desktop/File Manager from step 5 | Overlap/focus/exposure, partial damage, worker priority/occlusion, timers, messages/services and teardown pass equivalent MSX2/CPC scenarios. Desk/menu, input and M4 directory operations work in that shared shell. |
| 5 | Application parity — remaining step 5 | ABI Probe, Clock/Calculator, forms/Settings/Notepad, three-window PAINT, resources/secondary code, BASIC and the remaining migration ledger; universal APP bytes are identical across targets. |

These are dependency gates, not five independent rewrites. Keep packages on
separate issues/branches, measure each before moving on, and preserve the MSX2
reference. CPC runtime media remain M4/Albireo only. Albireo requires its own
backend proof; passing M4 is not an Albireo compatibility claim.

The goal is to bring the CPC back with the software features and application
behavior of the working MSX2 distribution, using a shared implementation of
desktop policy. The first deliverable is the
[MSX2 reference and acceptance matrix](CPC-RESTART-MSX2-REFERENCE.md).

## Baselines and scope

- Start from MSX2 `main` at `5ed8a157656848cad1db1e21c68490ef06b015cb`
  (Clock/Calculator universal migration, PR #61).
- Preserve the earlier CPC experiment on `feature/54-reintegrate-cpc`, pushed
  at `56478578ad7a785a6520f4b06b06fe735b7744c6`. Issue #54 remains its historical
  tracker. It supplies source and failure evidence for selective reuse.
- `archive/cpc-pcw-targets` preserves the earlier multi-platform code. The
  sibling `../geobench` is a driver/reference source, not the behavioral
  baseline for the features added in this repository.
- MSX2 remains the release target during the restart. CPC assumes at least
  512 KiB RAM and Mode 1, four colors. CPC runtime tests must use M4- or
  Albireo-backed media, never floppy-backed tests (user decision, 2026-09-05).
  Keep `../1984` as the proved M4 foundation runner; qualify `../konCePCja`,
  `../arnold` and `../caprice32` through the
  [CPC emulator test strategy](CPC-EMULATOR-TEST-STRATEGY.md) before relying on
  them. Unsupported storage is a recorded gap, not permission to use floppies.
  PCW implementation remains later work under #62.
- Keep the current GEOBENCH name, blue/white/black/red identity, and BSD-3-Clause
  licensing. This effort does not change the product identity.
- Preserve the frozen GEMBENCH-1 contracts. Review necessary changes to the
  experimental universal ABI explicitly, update its authority and both SDK and
  MSX2 implementation together, and rebuild universal artifacts together.

Software parity means the same ownership, lifecycle, UI, damage, messaging,
storage-context, and service semantics. Native geometry, hardware colors,
rendering implementation, storage transport, and elapsed rendering time can
differ. Public capacity and unsupported-operation behavior must be explicit.
The MSX2 allocator's exact free-page count is not a portable constant.

Shared kernel source is compiled for each machine. A migrated universal
application has one executable artifact copied unchanged into each target's
media. These are separate acceptance requirements. Remaining native MSX2
applications require migration; their existence does not establish CPC parity.

## Step 1 — Define the MSX2 behavioral reference

Work: inventory the implemented GEM-like and SymbOS-inspired features, their
current limits, consumers, source locations, and existing validation. Give each
behavior an acceptance ID with observable success and failure criteria. Mark
source checks, host models, compilation, emulator checks, and manual evidence
separately. Record untested behavior instead of treating a script's existence
as a passing result.

Deliverables:

- [Reference and acceptance matrix](CPC-RESTART-MSX2-REFERENCE.md), including
  application migration coverage and platform-boundary findings.
- [Baseline validation record](CPC-RESTART-BASELINE.md), with exact revision,
  commands, toolchain, results, and known test limitations.
- An ordered handoff to the first shared-core extraction.

Exit: every inventoried feature has an implementation pointer, acceptance
scenario, and coverage/gap designation; relevant existing host checks have a
recorded result. Emulator scenarios may remain explicitly unrun in this
documentation step. Before changing a subsystem in step 2, capture its runtime
baseline or resolve its missing test as a prerequisite.

## Step 2 — Extract and validate the shared core on MSX2

Work: extract the existing MSX2 implementation in small dependency-ordered
changes: owner/page bookkeeping and application lifetime; window ownership and
focus; visible damage and scheduling policy; deferred messages, timers,
filesystem-context state, and service bookkeeping. Shared policy may remain
app-linked or banked where measured memory budgets require it.

First work package: inventory the fixed-address dependencies of owner/page
bookkeeping; specify the bank and state-storage interface; capture allocator
and teardown baselines; extract that policy without changing public behavior.
Keep this package separate from compositor and UI migration.

Deliverables:

- A narrow platform interface for bank mapping, interrupt/critical-section
  handling, drawing, pointer/input, time, and serialized storage operations.
- Explicit state placement and build-time bounds for resident code, scratch,
  stacks, application snapshots, and module/transfer windows.
- The same shared source wired into MSX2, with regression results after each
  extraction and measured code/data/stack headroom.

Exit: affected host contracts and real MSX2 workflows pass in Screen 6 and 7;
capabilities, cleanup, and visible behavior remain consistent with the pinned
reference. Resolve a pre-existing failing baseline separately before evaluating
an extraction against it. No duplicated CPC policy implementation is required.

## Step 3 — Prove the CPC hardware and memory foundation

Work: establish a CPC memory map for all execution contexts before enabling
desktop services. Prove resident-stack and bank restoration, interrupt entry
and return, safe firmware/M4 boundaries, canonical drawing and clipping,
software-pointer save/restore, and bounded storage transfers.

The parked port's universal SDK used MSX page-3 command mailboxes that collided
with the CPC framebuffer. [3B-ABI](CPC-RESTART-STEP3B-ABI.md) has since adopted
caller-owned ABI 2.1 parameter records and validated the MSX2 SDK/runtime.
The production CPC receiver must now implement that same convention. Preserve
pixels as pixels; a framebuffer save/write-command/restore workaround is not
an accepted ABI boundary.

Deliverables: isolated hardware probes, memory-map assertions, stack canaries
and high-water measurements, and a reproducible M4 CARD/image built under QA.
Reuse audited drivers from the parked branch or upstream where they meet the
interface. Keep temporary probes out of the release application path.

Work packages under #65: 3A is M4 boot, fixed memory/stack layout, bank and
interrupt restoration; 3B is clipped graphics, pointer handling, and validation
of a framebuffer-safe portable command boundary; 3C is bounded runtime M4
read/write and failure handling. Passing 3A alone does not close this step.

Exit: repeated bank switches, interrupts, clipped primitives, pointer
movement over changing backgrounds, M4 load/save, and failure returns preserve
their documented state and memory guards in 1984. Drawing parameters never
alias display pixels. Record measurements before setting responsiveness limits.
Albireo is a later storage-backend gate; M4 success alone does not claim its
support. Floppy runtime testing is excluded by the current testing policy.

## Step 4 — Integrate the shared core on CPC

Work in order: one window; overlapping windows and focus; move/resize/close and
exposure; worker scheduling and timer damage; message/service lifecycle and
owner teardown. Each stage runs through the shared code from step 2.

Deliverables: the same logical interaction scenarios on MSX2 and CPC, with
target adapters for input and observation. Capture screenshots plus the actual
changed regions, callback/worker counts, focus/ownership state, page counts,
and stack/bank integrity. Generate addresses from symbols instead of embedding
MSX or old CPC table addresses in shared tests.

Exit: acceptance scenarios R04-R06 and R09-R14 below pass on both platforms;
overlapping foreground content remains intact at every observed update, focus
changes expose correct content without a subsequent drag, hidden visual
workers are parked, and repeated close/reuse restores the starting allocation
state. The pointer and top bar remain functional during the same sequences.

## Step 5 — Integrate applications and close the parity matrix

Work in dependency order: ABI Probe, universal Clock and Calculator;
Desktop/File Manager and their storage/shell workflows; resource-driven forms,
Settings and Notepad; PAINT's three-window document lifecycle; paged/resource
applications and the remaining shipped applications, including in-tree BASIC.
Provide platform services for hardware-dependent features and track any
remaining unsupported provider explicitly.

Deliverables: an application-by-application migration ledger, identical hashes
for every universal executable across media, equivalent behavior tests, and
measured input/repaint responsiveness under multi-window load. Validate actual
release artifacts as well as retained regression fixtures.

Exit: every required reference row is green or has a specifically agreed
hardware substitution. No unimplemented software feature is hidden behind a
successful ABI Probe result. PAINT, file operations, resources, services, and
cleanup must pass before full CPC feature parity is claimed. Hardware-specific
MSX extensions remain documented separately from the four-pen common profile.

## Working rules and progress

Use one bounded follow-up issue/branch per extraction or integration gate.
Keep a short record of the failing scenario, expected invariant, change, and
result. Reuse existing checks; add assertions where they detect a real gap.
When a gate fails, isolate that failure before layering more features onto it.
Run affected checks after each change and a wider suite at integration gates.
Do not repeatedly rebuild or replay unrelated workflows without a reason.

For reproducibility, use clean worktrees for baselines; ignored artifacts from
another branch can survive a checkout. Keep production QA media separate from
temporary diagnostic images, and record hashes of the image actually booted.

Step 1 is tracked in #63. Steps 2-5 require their own implementation and
validation; this plan is not a report that those stages have passed. Its
five-step order supersedes resuming the old #54 branch wholesale. The universal
ABI migration document still describes the executable-format contract, but its
proof-file gate alone does not establish full desktop parity.
