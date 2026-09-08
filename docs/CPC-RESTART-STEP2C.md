# Restart step 2C: shared focus and window stacking

Issue: [#70](https://github.com/salvogendut/GEMBENCH/issues/70).
Branch: `feature/70-shared-window-focus`, stacked on `d607dee` (step 2B).
Validation date: 2026-09-05.

This continues [restart step 2](CPC-RESTART-PLAN.md). It extracts the existing
MSX2 behavior without enabling a CPC desktop, changing the public ABI or
altering damage/rendering algorithms.

## Shared implementation

| Unit in `kernel/core/` | Existing policy now shared |
|---|---|
| `window_zorder.asm` | Append a new live slot, remove/compact a slot, select the live z-top as focus. |
| `window_raise.asm` | Move a live application window to the top while retaining the relative order of all others. |
| `window_hit_test.asm` | Scan top-to-bottom using half-open rectangle bounds in native WM coordinates. |
| `window_focus_click.asm` | Ignore non-fresh/missing/same-focus clicks; consume sibling-pane activation, focus/raise the target, leave desktop pinned, request the existing focus damage/repaint path. |
| `window_focus_map.asm` | Map the focused window, publish its event handler, and install/clear its menu only when the focus edge changes. |

The existing `wm_*` entry labels and ordering are retained, so callers,
breakpoints and fixed ABI entries stay intact. There is no parallel CPC copy.
The shared units use `CORE_*` state and narrow `FOCUS_*` provider hooks/macros,
not MSX addresses, window-record offsets or hardware calls.

`msx_window_focus.inc` supplies the current native window-table access, mapping,
menu and compositor bindings. Inline macros preserve the original instructions
without extra calls. Three existing scratch EQU declarations (`wm_slot`,
`wm_open_back`, `wm_hz`) moved to `lowram.inc` so they precede their aliases;
their addresses remain `12F9`, `12FB`, `12FC`. No state is allocated or moved.

Actual focus-damage source construction, clipping/composition, pointer drawing,
scheduling and menu rendering remain in their providers. Loader/registration,
drag/drop and deferred/service dispatch still own their surrounding control
flows and temporary focus changes. Extracting shared `wm_raise` does not mean
those callers have themselves been extracted.

## Invariants and compatibility

`window_focus_contract.inc` records register clobbers, state lifetime and
provider obligations, with fixed-RAM spans, z-array index-page bounds, capacity
and boolean-option assertions. The provider must separately prove non-overlap
with framebuffer, overlays, stacks and other allocations.

- The live prefix of z-order contains unique, alive slots; desktop is slot/index
  zero and normal callers never remove or raise it. Desktop can have focus
  while an application remains z-top.
- Append/remove/raise/top-focus are trusted internal helpers with explicit
  preconditions, not new public validators. Tail bytes beyond the live count
  remain unspecified.
- Sibling activation retains the working **native code-page equality** rule;
  it clears only the fresh-click bit. It is not silently changed to owner-handle
  comparison, and the provider must maintain the native-tag convention.
- Pointer and rectangle bytes use the same native WM units. This does not
  change the universal ABI's pixel coordinates or introduce MSX geometry into
  universal applications.
- Focus assignment precedes damage-source preparation and any raise; actual
  composition sees the final z-order. Damage calculations remain unchanged.
- Normal shared integration uses the existing preserve-slot append and visible
  compositor paths. The historical cooperative instruction paths are retained
  through explicit options, not a new target-specific focus policy.

## Validation

RASM 3.2.1 and SDCC 4.6.2 #16671 are supplied by `my-distrobox`. Runtime checks
use headless openMSX 21.0, Philips NMS 8250, 512 KiB expansion, Nextor/Sunrise
IDE and disabled optional UNAPI, with private diagnostic media copies.

All four normal Screen 6/7 kernel and DOS-child artifacts compare byte-for-byte
against the pre-extraction baseline. Sizes and SHA-256 hashes are exactly those
recorded in [step 2B's binary table](CPC-RESTART-STEP2B.md#binary-comparison-and-budgets):
13,956/15,534-byte kernels and 14,292/15,870-byte child COMs. Cooperative kernels
also compare identically at 13,929/15,507 bytes with the same hashes as step 2B.
The comparison uses identical generated inputs and flags; no cooperative
runtime result is claimed.

The scheduler remains 1,448/1,536 bytes and Screen 7 retains 258 bytes of
child-COM headroom. Instructions, stack use, capacities and state are unchanged.
The normal 983-byte selector launcher was restored after child comparisons.
No release-media refresh is required: the rebuilt executables are identical
to the staged ones. `QA/MSX/GBMSX.IMG` remains SHA-256
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.

| Check | Result |
|---|---|
| PAINT focus/move/exposure/close, before and after | PASS: all three panes, full focus-endpoint clips, preserved/exposed canvas hash `B99399C8`; peak five windows, final two; free pages 22→22. |
| Release universal Clock/Calculator accessories, Screen 6 and 7, before and after | PASS: Desk launch/activation, menus/borders/text, close/relaunch; busy pages 4→3→4, three final windows, focus 1, no stack-guard fault or deferred/shell busy state. |
| Added stacking assertions in the accessory workflow, both modes before and after | PASS: ten checkpoints per run, checking exact relative order, desktop pinning, no duplicate/dead/missing live slots, focused target, close fallback and slot reuse. Target addresses/stride come from `lowram.inc`. |
| Existing visibility wrapper, before and after | Reports PASS for retained native Clock background/hidden updates and PAINT. The captured covered-area hashes remain stable and hidden worker/draw/damage deltas are zero. See the legacy diagnostic limitation below. |
| Independent provider tests | PASS: five unittest methods including subcases; actual shared assembly with low/high state (`2000`/`D800`) and a different 16-byte window-record layout; normal/cooperative variants, deterministic output and negative state/capacity/index/option checks. |
| Full `make check` in a clean worktree at `a4e20b5` | PASS, exit 0: 92 discovered Python tests, plus the existing C/assembly runtime, universal SDK determinism, ABI/layout, asset/media and editor checks. |

The independent providers are assembly fixtures, not executed CPC kernels.
No physical-machine, new CPC desktop or new portability/performance result is
claimed. The tests preserve the existing ABI/layout checks; the compositor
source check follows the moved focus include rather than requiring its old
inline location.

The full suite ran in `/tmp/geobench-70-check.TXowFR`, with independent build
fixtures (no production media/build symlink), through `my-distrobox` using
`SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc` and
`SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80`. The log is
`/tmp/geobench-70-make-check.log`. No check was relaxed for the preserved,
untracked workspace CPC QA artifacts.

Two harness details matter when interpreting results:

1. New asynchronous accessory assertions initially overreached by requiring the
   steady-state handler/menu edge during deferred dispatch. The unchanged
   baseline demonstrates that dispatch can temporarily redirect `APP_HANDLER`
   or leave the menu edge pending while the target page is mapped. Those are
   not stacking invariants. The final assertions check z-order/focus; existing
   menu interactions continue to exercise actual dispatch. Both baseline modes
   passed the corrected assertions before evaluating the extraction.
2. The retained native Clock probe's final low-RAM dump/restoration predicate
   is not guarded against a temporary DOS page-0 mapping. Its final window,
   focus and pointer numbers are therefore not accepted as state evidence here,
   even though the script reports PASS. Tighten that sampling before using the
   final exposure check as a future damage-extraction gate. PAINT and the
   guarded accessory workflow supply this package's focus/exposure evidence.

Reproduction (after building the matching MSX2 media and retained diagnostics):

```sh
MSX_HEADLESS=1 bash tools/test_visible_regions_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=6 bash tools/test_desk_accessories_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=7 bash tools/test_desk_accessories_openmsx.sh
python3 tests/test_window_focus_core.py -v
```

Use source `d607dee` for the pre-extraction kernel, with the enhanced diagnostic
on both sides. The initial unenhanced runs also passed. Raw baselines and
cooperative comparisons are retained locally under
`/tmp/geobench-focus-baseline.KbDXBI/`; the pinned source worktree is
`/tmp/geobench-70-reference.O0UYm3` (shared generated inputs, isolated assembler
outputs). Logs are `/tmp/geobench-70-visible-{before,after}.log`,
`/tmp/geobench-70-desk-{6,7}-before.log`, and
`/tmp/geobench-70-stack-{6,7}-{before,after}.log`. Temporary paths are convenient
evidence locations; this report is the durable result record.

## Next package

Visible damage/region iteration and scheduling are next, including tightening
the legacy Clock diagnostic noted above before its acceptance runs. Then
deferred/timer and filesystem/service policy still need extraction. Restart
step 2 is not complete, and CPC desktop integration remains disabled. Existing
workspace CPC QA files are preserved.
