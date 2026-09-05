# CPC restart plan

Started: 2026-09-05. Tracking issue: [#63](https://github.com/salvogendut/GEMBENCH/issues/63).
Step-1 branch: `feature/cpc-restart-reference`.

Progress: step 1 is complete. Step 2 has begun with
[owner/page extraction 2A](CPC-RESTART-STEP2A.md) under issue #64: byte-identical
MSX2 kernels, passing host checks and before/after openMSX lifecycle validation.
The remaining shared-core packages and steps 3-5 are planned.

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
  512 KiB RAM and Mode 1, four colors. Use generated M4 card media with `../1984`
  for CPC integration tests. PCW implementation remains later work under #62.
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

The universal SDK currently uses MSX page-3 command mailboxes that collide with
the CPC framebuffer in the parked port. Choose and validate an explicit
portable calling/state convention. Preserve pixels as pixels; a framebuffer
save/write-command/restore workaround is not an accepted ABI boundary.

Deliverables: isolated hardware probes, memory-map assertions, stack canaries
and high-water measurements, and a reproducible M4 CARD/image built under QA.
Reuse audited drivers from the parked branch or upstream where they meet the
interface. Keep temporary probes out of the release application path.

Exit: repeated bank switches, interrupts, clipped primitives, pointer
movement over changing backgrounds, M4 load/save, and failure returns preserve
their documented state and memory guards in 1984. Drawing parameters never
alias display pixels. Record measurements before setting responsiveness limits.
Floppy and Albireo are later storage-backend gates; M4 success alone does not
claim their support.

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
