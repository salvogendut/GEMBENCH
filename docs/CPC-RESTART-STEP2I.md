# Restart step 2I: Z80 context and IRQ boundary

Issue: [#76](https://github.com/salvogendut/GEMBENCH/issues/76).
Branch: `feature/76-shared-context-irq-boundary`, stacked on `32e043c` (2H).
Validation date: 2026-09-06.

This implements the first package in the newly agreed execution order in
[CPC-RESTART-PLAN.md](CPC-RESTART-PLAN.md): context/IRQ boundary, production CPC
memory/adapters, first shared-core window, desktop integration, application
parity. It does not select CPC addresses or enable a CPC desktop.

## Implementation

`kernel/scheduler.asm` is now an ordered MSX2 composition of the existing
shared visibility/priority engine and these shared Z80 units:

| Unit | Responsibility |
|---|---|
| `core/context_init.asm` | Initialize the eight scheduler bytes and optional timer hook. |
| `core/context_save.asm` | Bound/sample live stack use and copy the current context into its app bank. |
| `core/context_restore.asm` | Resume the old stack or map/restore the selected context; retain both fault paths. |
| `core/context_tasks.asm` | Save/restore main and alternate registers, yield, native worker opt-in and first-run/worker loop. |
| `core/context_irq.asm` | Root fast path, quantum/lock checks, preemptible-PC and mapped-owner checks, IRQ switch/defer. |

The single existing `core/worker_select.asm` stays between save and restore.
Focused/fully visible/partly visible priority, hidden-worker parking and a root
turn between worker slices are unchanged. Dead CPC/PCW branches in the old
standalone scheduler composition are no longer alternatives to this policy;
the historical implementations remain in the archival/parked branches.

`kernel/msx_context.inc` supplies fixed cells, scratch/snapshot/code bounds,
native window/descriptor interpretation, diagnostic telemetry, critical-section
and IRQ hooks. `msx_context_irq.asm` alone hooks/restores the DOS IM1 vector and
retains its original handler. `msx_context_helpers.asm` alone interprets native
WM records and switches the mapper through DOS `PUT_P1`, updating `BANK_CUR`.

`core/context_contract.inc` specifies register, stack, bank and IRQ ownership.
Assembly rejects noncontiguous scheduler cells, visibility-provider mismatches,
invalid modes/quantum/flag bits, changed app/snapshot ABI, nonfixed or locally
overlapping spans, undersized temporary stacks and overflowing code allocation.
These are local contracts, not proof of a complete CPC memory map.

## Preserved assumptions and limits

- Runtime stack: one fixed stack; `BOOT_SP` is a runtime word. Each switch
  saves 1..255 live bytes into the owning app's `7F00..7FFF` reserve. The full
  runtime stack span must remain fixed, writable and separate from allocations.
- MSX2 scheduler code remains `C900..CEFF`; temporary scratch remains
  `1450..1480` (49 bytes), usable only when other scratch consumers are dead.
  Mapper and interrupt-chain stack requirements remain provider obligations.
- AF/BC/DE/HL/IX/IY and all alternate pairs are saved. I/IM are kernel-owned;
  arbitrary per-task interrupt-enable state is not part of the snapshot ABI.
  Native yield/task-enable return interrupt-enabled, as before.
- A pending IRQ belongs to the current interrupt, not the selected snapshot.
  The restored context completes it through the provider's IRQ return path.
  The initial two-byte worker snapshot still enters the worker loop directly.
- Root/compositor kernel work is not timer-preempted. Workers may execute only
  compute-only app code with their own bank mapped. Higher visibility tiers
  may starve lower tiers; this extraction does not introduce new fairness.
- Empty-target and oversize/zero-live-stack fault recovery, and native
  task-enable's snapshot-before-flags behavior, are unchanged. This package
  does not harden arbitrary malformed internal scheduler state or make repeat
  task-enable a safe snapshot-preserving operation.

Public native gates, universal ABI 2.1, low-RAM allocations and the SDK are
unchanged. CPC graphics/input/time/storage implementations still need the
production adapter gate; independent assembly is not hardware validation.

## Binary comparison and budgets

Toolchain: RASM 3.2.1; SDCC/SDAS 4.6.2 #16671 in `my-distrobox`.
All eight timer/switch/baseline combinations were assembled into isolated
directories before extraction at `32e043c` and again afterwards, then compared
with `cmp`. Every pair is byte-identical, including jump and internal labels.

| Timer | IRQ switching | Bytes, baseline off / on |
|---:|---:|---:|
| 0 | 0 | 1,448 / 1,457 |
| 0 | 1 | 1,445 / 1,454 |
| 1 | 0 | 1,451 / 1,460 |
| 1 | 1 | 1,448 / 1,457 |

Release scheduler: 1,448/1,536 bytes, 88 bytes headroom, SHA-256
`70c0e6f9402eae994a6e509a91381d70a85d3217597b7859ffc6be09048f62f9`.
No added code bytes, state cells or stack frames. Desktop rebuilt with this
payload remains 15,147 bytes, identical to the staged `DESKTOP.APP`, SHA-256
`552199b90097c7a6c5ee398152c0f1c0b15ea952f986a7e86d747ddc10e1abe5`.

The normal resident kernels and universal applications were not changed by
this package. No release-media refresh is needed; `QA/MSX/GBMSX.IMG` SHA-256
remains `a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.

## Validation

Six new tests in `tests/test_context_core.py` check boundary/source composition,
assemble the actual shared mechanism with two independent fixed-state placements
(`2000`, `D800`), alternate 16-byte window records and a different IRQ return
leaf, inspect the emitted complete register save/restore sequence, and reject
invalid contracts. Fixture bank/IRQ leaves are assembly-only. Existing
visibility tests now recognize the separate context composition.

Real runtime checks used openMSX 21, Philips NMS 8250, 512-KiB expansion,
Nextor/Sunrise IDE and private hard-disk images with UNAPI disabled:

| Scenario | Before / after |
|---|---|
| Native Clock partial visibility, full occlusion and exposure, Screen 7 | PASS / PASS; after extraction hidden worker/draw/damage deltas are `0/0/0`, covering pixels unchanged, one exposure draw. |
| Universal Desk/Clock/Calculator, Screen 6 | PASS / PASS; ten stacking checks, zero scheduler faults; sampled scheduler high-water 64 / 68 bytes. |
| Universal Desk/Clock/Calculator, Screen 7 | PASS / PASS; ten stacking checks, zero scheduler faults; sampled scheduler high-water 35 / 53 bytes. |
| Non-yielding TASKDEMO, Screen 6 | PASS / PASS; eight IRQ switches, eight resumed IRQ continuations and eight worker-to-root selections; DOS tick progresses, sampled fixed-stack depth 45 bytes, zero faults. |
| Non-yielding TASKDEMO, Screen 7 | PASS / PASS; same switch/return/root counts; DOS tick progresses, sampled fixed-stack depth 43 bytes, zero faults. |

Sampling values are observations, not worst-case stack/latency guarantees.
The new `tools/test_context_irq_openmsx.sh` builds a separate diagnostic Desktop
and stages its non-yielding workers only into a temporary CARD/image. It does
not overwrite the normal Desktop payload, symbols or release image. Scheduler
addresses come from the corresponding assembler symbols. The optional
`CONTEXT_SCHEDULER_REFERENCE` uses captured before bytes only after verifying
an exact match with the current symbol-producing assembly.

The IRQ observer checks the five implemented mapper bits on the fixed 512-KiB
runner (unused readback bits are not segment identity), fixed-stack bounds and
fault state. It deliberately does not demand round-robin service across priority
tiers, unlike the historical pre-M9 diagnostic. No live scheduler fault injection,
exhaustive register-value stress or worst-case interrupt latency is claimed.

Reproduction after building the normal MSX distribution, in `my-distrobox`:

```sh
python3 -m unittest discover -s tests -p test_context_core.py -v
MSX_TEST_MODE=6 bash tools/test_context_irq_openmsx.sh
MSX_TEST_MODE=7 bash tools/test_context_irq_openmsx.sh
MSX_HEADLESS=1 bash tools/test_multi_event_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=6 bash tools/test_desk_accessories_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=7 bash tools/test_desk_accessories_openmsx.sh
```

Evidence: `/tmp/geobench-2i-baseline.oowWRk/{t*,after-t*}` contains the eight
before/after payloads, symbols and assembler logs. Runtime logs are
`/tmp/geobench-2i-{clock,desk6,desk7,irq6,irq7}-{before,after}.log`;
the complete post-change Clock report is `/tmp/geobench-2i-clock-after.txt`.
Full clean-checkout `make check` passed at implementation commit `5a348a4`:
141 discovered Python tests with no skips, all host/C/Z80 checks, public ABI,
layout and distribution audits exit zero. The clean build also regenerated
ABI Probe, Calculator and Clock with their unchanged universal APP hashes.
Checkout: `/tmp/geobench-76-check.6BpIuS`; log:
`/tmp/geobench-76-make-check.log`. Its independent build leaves local `QA/CPC/`
untouched. The static MSX floppy-distribution audit does not boot any floppy.

## Next package

Follow-up: [3D-A production-address integration](CPC-RESTART-STEP3D.md) is now
validated under #77; that document tracks drawing checkpoint 3D-B and the
still-open production-adapter completion gate.

Production CPC memory layout and adapters. Budget the actual shared policy and
context image, resident kernel, low-memory support, all fixed state, normal/IRQ/
temporary stacks, app snapshots and M4 transfer space together. Keep the complete
framebuffer, including raster gaps, out of command/state storage. Connect the
existing proven CPC bank/IRQ/graphics/M4 leaves to these contracts; complete the
missing input/time/text/line/pointer pieces. Validate their combined stack,
bank/IRQ restoration and responsiveness before the first shared-core window.

Do not reuse the old 512-byte scheduler reservation or the isolated foundation
probe's addresses as production assumptions. The shared scheduler/visibility
image alone is now 1,448 bytes on MSX2. No PCW implementation or Albireo support
is claimed. All CPC runtime testing stays M4/Albireo-backed; untracked `QA/CPC/`
is preserved. Review and merge remain separate.
