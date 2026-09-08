# Restart step 2E: shared window damage and repaint dispatch

Issue: [#72](https://github.com/salvogendut/GEMBENCH/issues/72).
Branch: `feature/72-shared-window-repaint`, stacked on `59926b4` (step 2D).
Validation date: 2026-09-05.

This continues [restart step 2](CPC-RESTART-PLAN.md). It extracts the working
MSX2 implementation, without changing the public ABI, enabling a CPC desktop
or redesigning the damage/rendering algorithms.

## Shared implementation

| Unit in `kernel/core/` | Existing policy now shared |
|---|---|
| `window_geometry.asm` | Update focused-window position/size; move damages the complete endpoint envelope, resize damages the maximum old/new extents. Includes the unchanged `damage_axis` helper. |
| `window_focus_damage.asm` | Prepare primary/extra rectangles for focus changes, omitting desktop furniture and leaving overlap subtraction to the shared iterator. |
| `window_damage.asm` | Explicit damage, full-screen clip and window clip with the existing right-side overdraw allowance. |
| `window_repaint.asm` | Bottom-up or top-only dispatch through visible fragments; skip hidden/dead surfaces; map and dispatch managed/legacy painters; restore caller bank/full clip and unlock/show the pointer. |

The existing `k_wm_*`, `wm_*`, `damage_axis`, `clip_set_full` and `wra_*`
entry labels and instruction order are retained. This is one shared policy,
not another CPC implementation. It calls the visible-region core extracted in
2D through the existing scheduler entries. In particular, the historical
`SCHED_VIS_REFRESH_ENTRY` actually captures immutable damage sources **and**
refreshes visibility; its new provider name is `PAINT_PREPARE`.

`msx_window_damage.inc` binds state, native geometry and window-record access,
bank changes, pointer operations, IRQ boundaries and drawing/callback hooks.
Inline macros preserve the original instruction sequences, including stack
effects. Six existing scratch EQU declarations move into `lowram.inc` before
their aliases: `sp_x/sp_y/ss_w/ss_h` at `124B..124E`, and
`wm_rp_back/wm_rp_i` at `12FD..12FE`. Nothing is allocated or moved in RAM.
Assertions after the graphics driver prove its clip cells match the provider.

Window chrome and actual drawing, managed drag/gadget interaction, menu/popup
callers, background timer dispatch, bank hardware and IRQ/context machinery
remain provider-side. Sharing damage setters does not mean all their callers
or drawing implementations have been extracted.

## Contract and limits

`window_damage_contract.inc` documents fixed state, hook register/stack
requirements, callback restrictions and assertions for geometry bounds,
capacities, flag bits, byte-indexed z-order, clip adjacency and fixed spans.
Providers still need a complete non-overlapping memory map.

- Geometry is native byte-coordinate `x,y,w,h`, separate from universal ABI
  pixels. Existing callers must provide non-wrapping rectangles and padded
  extents. This does not introduce a new public validator or saturating math.
- Move damage retains the full endpoint envelope needed to repair the
  destructive rubber-band route, not merely the disjoint old/new rectangles.
  Focus damage retains two exact sources. Existing window-clip padding remains
  an explicit provider choice (eight native columns on MSX2).
- Repaint is serialized root/kernel work under the caller's scheduler lock.
  Nested repaint and geometry/lifetime/z-order mutation during painting are
  unsupported. Callbacks must honor clipping and preserve compositor scratch.
- IRQ hooks preserve the original DI/EI boundary sequence. They do not promise
  interrupts remain disabled inside drawing or save/restore the caller's IFF.
  Cleanup restores the caller bank and full clip, not the incoming clip or
  previous paintlock value.
- Pointer erasure is independent of region policy. MSX2's separate sprite
  plane can remain visible in the normal path; a future CPC software pointer
  must erase/save-under correctly even with visible-region composition enabled.
  The paint lock spans the complete pass and final show is idempotent.
- Region mode is the normal shared policy. The coarse rectangle-cull variant
  preserves the existing MSX2 cooperative build, not a second CPC algorithm.

## Binary comparison and budgets

RASM 3.2.1 in `my-distrobox` assembled pinned source `59926b4` and the extraction
with identical generated inputs, baseline instrumentation off and tiled title
bars enabled. All comparisons pass byte-for-byte:

| Artifact | Bytes | Result |
|---|---:|---|
| Normal Screen 6 kernel / child COM | 13,956 / 14,292 | Identical to baseline and staged release child. |
| Normal Screen 7 kernel / child COM | 15,534 / 15,870 | Identical to baseline and staged release child. |
| Cooperative Screen 6 kernel | 13,929 | Identical to baseline. |
| Cooperative Screen 7 kernel | 15,507 | Identical to baseline. |
| App-carried scheduler | 1,448 / 1,536 reserved | Unchanged; no scheduler instructions edited. |

SHA-256 hashes are unchanged from [step 2B's binary table](CPC-RESTART-STEP2B.md#binary-comparison-and-budgets)
and [step 2D's scheduler table](CPC-RESTART-STEP2D.md#binary-comparison-and-budgets).
Screen 7 retains 258 bytes of child-COM headroom. Code/data capacities,
instructions and stack requirements are unchanged. No cooperative runtime
result is claimed.

The normal 983-byte selector was never overwritten. Fresh normal kernel
symbols are installed for diagnostics, with the Screen 7 raw kernel left in
the normal staging slot. No application or release-image refresh is needed:
the rebuilt child COMs match both `QA/MSX/CARD` children exactly.
`QA/MSX/GBMSX.IMG` remains SHA-256
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.

## Behavioral validation

Paired before/after runs use the unchanged diagnostic scripts, headless openMSX
21.0, Philips NMS 8250, 512-KiB expansion, Nextor/Sunrise IDE, UNAPI off and
private hard-disk diagnostic images. The baseline passed before extraction;
no harness corrections or runtime bug fixes were needed in this package.

| Check | Before and after result |
|---|---|
| Retained native Clock partial/complete occlusion | PASS: hidden worker/draw/damage deltas `0/0/0`; covered and fully hidden framebuffer hashes remain stable. |
| Clock restored after maximize/restore | PASS at a stable kernel poll: File Manager exactly `4 26 56 158`, fresh restore draw delta 1, three live windows, focus 1. |
| PAINT focus/move/exposure/close | PASS: all three panes, preserved/exposed canvas hash `B99399C8`; focus tool/preview/work repaint counts `1/1/0`; free pages 22→22; peak five windows, final two. |
| Release universal Clock/Calculator, Screen 6 and 7 | PASS: Desk activation, menus/borders/text, close/relaunch; ten stacking checkpoints per run; busy pages 4→3→4, final three windows, focus 1, no stack-guard faults. |
| Independent-provider tests | PASS: seven unittest methods, including low/high state (`2000`/`D800`), independent 16-byte window records/flag bits, 80×200 and 128×212 geometry, independent region/pointer options, deterministic assembly and invalid-contract rejection. |
| Affected source and geometry tests | PASS: compositor (4), visibility core (6), focus core (5). Existing assertions follow the extracted includes/hooks rather than requiring the previous inline body. |
| Full `make check` in a clean worktree at `a35c630` | PASS, exit 0: all 108 discovered Python tests, plus existing C/assembly runtime, universal SDK determinism, ABI/layout, asset/media and editor checks. |

The independent providers assemble the actual shared code but are not executed
CPC implementations. No claim of CPC pointer correctness, physical hardware
validation, new fairness policy or improved performance is made here. The
existing runtime scenarios cover normal application workflows, not arbitrary
corrupt window tables or every callback-failure path.

The full suite ran in `/tmp/geobench-72-check.WtInxw` with independent generated
fixtures and no production build/media symlinks, through `my-distrobox` with
`SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc` and
`SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80`. Its log is
`/tmp/geobench-72-make-check.log`. No check was relaxed for untracked CPC QA
artifacts. Existing static MSX2 floppy-format audits do not boot an emulator
and are unaffected by the CPC runtime storage policy.

Reproduction (with matching MSX2 media and retained diagnostics built):

```sh
MSX_HEADLESS=1 bash tools/test_visible_regions_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=6 bash tools/test_desk_accessories_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=7 bash tools/test_desk_accessories_openmsx.sh
python3 tests/test_window_damage_core.py -v
```

Local raw comparisons: `/tmp/geobench-repaint-baseline.AqiwqE/`.
Pinned source: `/tmp/geobench-72-reference.KiCvU8` (shared generated inputs,
isolated assembler outputs). Runtime logs:
`/tmp/geobench-72-visible-{before,after}.log`,
`/tmp/geobench-72-clock-{before,after}.txt` and
`/tmp/geobench-72-desk-{6,7}-{before,after}.log`.
These temporary paths are convenient evidence locations; this document is the
durable result record.

## Next package

Deferred-message/background-timer dispatch is next. Low-level context/IRQ
adapters and filesystem/service work also remain before CPC desktop integration.
Restart step 2 is not complete. The [M4/Albireo-only CPC runtime rule](CPC-EMULATOR-TEST-STRATEGY.md)
remains in force; no CPC emulator or floppy-backed runtime test was run here.
Preserved untracked `QA/CPC/` artifacts are untouched. Review/merge are separate.
