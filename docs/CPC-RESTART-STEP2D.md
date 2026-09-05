# Restart step 2D: shared visible regions and worker priority

Issue: [#71](https://github.com/salvogendut/GEMBENCH/issues/71).
Branch: `feature/71-shared-visible-regions`, stacked on `6a65c28` (step 2C).
Validation date: 2026-09-05.

This continues [restart step 2](CPC-RESTART-PLAN.md), extracting the working
MSX2 policy without enabling a CPC desktop or changing the public ABI.

## Shared implementation

| Unit in `kernel/core/` | Existing policy now shared |
|---|---|
| `visibility_prepare.asm` | Preserve the immutable primary damage rectangle and latch the optional second source before classifying visibility. |
| `visible_regions.asm` | Stream visible horizontal bands after subtracting higher opaque windows; continue through the second source without double-painting primary overlap. |
| `window_visibility.asm` | Rank each surface as hidden, partially visible, fully visible or focused, then aggregate an owner's highest rank into its designated worker slot. |
| `worker_select.asm` | Return workers to runnable root; from root, select focused/full/partial workers in priority order, round-robin within each tier, parking hidden visual workers. |

`scheduler.asm` includes these units at their original instruction positions.
Existing entry labels and control flow are retained. `msx_visibility.inc`
binds fixed state, native geometry, window-record access and context-restore
continuations. Its inline macros preserve the original instructions without
additional calls. Four clip EQU declarations moved into that provider so they
precede their aliases; their addresses remain `1338` through `133B`.

WM damage construction, focus/move damage requests and repaint dispatch remain
in the current WM provider. Drawing, bank I/O, IRQ handling, stack/context
save/restore and worker startup also remain provider-side. This package shares
the selection policy, not the entire scheduler or compositor.

## Contract and limits

`visibility_contract.inc` documents hook registers, state lifetime, serialization
and continuation-stack requirements, with assembly assertions for fixed-address
spans, byte-indexed arrays, adjacency, capacities and native screen dimensions.
The provider must still prove the complete memory map and exclude overlap with
framebuffers, overlays and stacks.

- Rectangles are opaque, half-open, native byte-coordinate tuples. Right/bottom
  sums must not wrap; dimensions are 1..255. This is not a new canonical-pixel
  ABI or a claim that 256-row PCW geometry already works.
- Primary and extra damage sources remain immutable for the whole composition
  pass. The iterator streams fragments; its wrapping diagnostic counter is
  not a fragment-pool limit.
- Region work is serialized root/compositor work. Worker selection uses shared
  scratch only after complete context save with interrupts excluded; the
  provider must honor the compositor's scheduler lock.
- Owner aggregation retains the existing owner-ID lookup. Lifetime publication
  and cleanup must prevent stale links; no new generation check is claimed.
- Focus/full/partial priority is unchanged. Sustained higher-priority demand
  can starve lower tiers. Windowless service dispatch is separate; this does
  not introduce a new fairness guarantee or service scheduling policy.

## Diagnostic corrections before extraction

Two separate test-only commits precede the kernel extraction:

1. `c4f0933` samples the retained native Clock probe at stable kernel polls.
   Previously a timed final callback could read DOS/ROM-mapped page 0 and
   accept aliased low-RAM values. All state-sensitive callbacks now use the
   poll dispatcher. Restoration requires the exact original File Manager
   rectangle, visible Clock, expected focus/window count, no paint lock, and
   a new draw after the restore click. The pointer driver reuses the existing
   bounded pulse pattern; it does not hold an accelerating key indefinitely.
2. `2fbcb1f` guards the accessory workflow's pre-click z-order snapshot with
   its existing low-RAM readiness predicate. The unchanged Screen 7 baseline
   exposed a timed snapshot reading a bogus live-window count of 112.

Both corrections passed on the unchanged kernel before extraction. These
were harness faults, not evidence of a new application or kernel defect.
Three host Tcl tests exercise the actual Clock predicate/dispatcher, including
the observed aliased state, missing new draw and outside-poll rejection.

## Binary comparison and budgets

Toolchain: RASM 3.2.1 and SDCC 4.6.2 #16671 in `my-distrobox`. Reference source
is `2fbcb1f`, with the same generated inputs and build flags on both sides.

Every scheduler timer/context-switch build combination compares byte-for-byte:

| Timer / context switch | Bytes | SHA-256, before and after |
|---|---:|---|
| 0 / 0 | 1,448 | `1f9a30efd4003852c0ccf3d58034f28c50c7466ab5cf66b9f0b3470ca16804f9` |
| 0 / 1 | 1,445 | `a246ea93a62003d47350e777e75268cc706653729d8399b87591e32792cece43` |
| 1 / 0 | 1,451 | `5b1d988e9376e58d38e957e5d224b1ddf14389f90ccba10987020042015016c2` |
| 1 / 1 (normal) | 1,448 | `70c0e6f9402eae994a6e509a91381d70a85d3217597b7859ffc6be09048f62f9` |

The normal Screen 6/7 kernels and child COMs also compare identically, retaining
the sizes and hashes in [step 2B](CPC-RESTART-STEP2B.md#binary-comparison-and-budgets):
13,956/15,534-byte kernels and 14,292/15,870-byte children. No new cooperative
kernel or non-normal scheduler runtime test is claimed here.

The normal scheduler remains 1,448/1,536 bytes; Screen 7 retains 258 bytes of
child-COM headroom. No state, instructions or stack requirements were added.
The normal 983-byte selector was restored after the child comparisons.
Application-carried scheduler bytes are unchanged, so no release-media refresh
is required. `QA/MSX/GBMSX.IMG` remains SHA-256
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.

## Behavioral validation

Paired before/after runs use headless openMSX 21.0, Philips NMS 8250, 512-KiB
expansion, Nextor/Sunrise IDE, private hard-disk diagnostic images and UNAPI off.

| Check | Before and after result |
|---|---|
| Retained native Clock background and complete occlusion | PASS: covered-area hash `3671906385` unchanged; hidden worker/draw/damage deltas `0/0/0`; hidden-area hash `367858421` unchanged. |
| Clock restoration at stable poll | PASS: 380 poll samples; final sample at poll; File Manager exactly `4 26 56 158`; restore draw delta 1; three windows, focus 1, final PC `8252`, SP `D8FC`. |
| PAINT focus/move/exposure/close | PASS: all three panes; preserved/exposed canvas hash `B99399C8`; free pages 22→22; peak five windows, final two. |
| Release universal Clock/Calculator accessories, Screen 6 and 7 | PASS: ten stacking checkpoints per run; Desk activation, menus/borders/text and close/relaunch; busy pages 4→3→4; final three windows, focus 1, stack-guard faults 0. |
| Independent shared-policy assembly | PASS: six unittest methods, including subcases for low/high state (`2000`/`D800`), independent 16-byte records, 80×200 and 128×212 native geometry, deterministic output and invalid contract rejection. |
| Existing geometry/source tests and corrected Clock harness | PASS: four compositor tests plus three Tcl predicate/dispatcher tests. |

Independent providers are assembly fixtures, not executed CPC implementations.
These regressions do not establish new multi-worker fairness or performance
guarantees. No CPC emulator was run for this package.

Reproduction (with matching MSX2 media and retained diagnostics built):

```sh
MSX_HEADLESS=1 bash tools/test_visible_regions_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=6 bash tools/test_desk_accessories_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=7 bash tools/test_desk_accessories_openmsx.sh
python3 tests/test_visibility_core.py -v
python3 tests/test_visibility_compositor.py -v
python3 tests/test_clock_visibility_probe.py -v
```

Local evidence: `/tmp/geobench-71-baseline.t1R31V/` holds raw comparisons;
`/tmp/geobench-71-reference.uEWKCF` is the pinned pre-extraction source.
Runtime logs are `/tmp/geobench-71-visible-{before,after}.log`,
`/tmp/geobench-71-clock-{before,after}.txt` and
`/tmp/geobench-71-desk-{6,7}-{before,after}.log`. Temporary paths are convenient
evidence locations; this document records the durable results.

## Next package and CPC testing

Extract WM damage construction and repaint dispatch next. Low-level context/IRQ
adapters and deferred/timer/filesystem/service work still remain before CPC
desktop integration. Restart step 2 is not complete.

The [CPC emulator assessment](CPC-EMULATOR-TEST-STRATEGY.md) records the separate
read-only Arnold investigation and the user's M4/Albireo-only runtime policy.
Existing untracked CPC QA artifacts are preserved. No floppy fallback or
sibling-emulator modifications are part of this work.
