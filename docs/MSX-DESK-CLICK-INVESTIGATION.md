# MSX Desk-click investigation — 2026-09-08

Follow-up to [the MSX stability baseline](V1-MSX-STABILITY-BASELINE.md) and
[issue #82](https://github.com/salvogendut/GEMBENCH/issues/82).
The original investigation below records the unfixed behavior. The
2026-09-09 implementation and verification are recorded at the end.
The separate firmware report is now
[RainBIOS #169](https://github.com/salvogendut/rainbios/issues/169). No RainBIOS
branch, firmware change or 1983 ROM import was made during that investigation.

## Finding

**The click is lost before menu dispatch.** A Clock timer repaint can keep the
root away from input sampling for about 135–136 ms. An entire 80 ms button
press/release can fall within this interval. When polling resumes, the BIOS
trigger read returns released, `in_fire` stays zero, and the edge detector has
no press to deliver. The menu is never requested.

This is a guest input-sampling limitation, not a misplaced Desk hit box, a menu
being painted behind another window, or merely the old popup-readiness race.
Clock exposes it, but the poll-only input design can lose a short press during
other sufficiently long synchronous operations too. That broader risk follows
from the code; this investigation only reproduces the Clock workload.

## Timing evidence

Private production images and matching symbols are unchanged from the baseline
source pin `9ff0825`. openMSX 21.0 uses Philips firmware, 512 KiB expansion and
Sunrise/Nextor disk images. The actor still uses the original 80 ms Space-button
presses. New hooks only observe input sampling, BIOS trigger returns, repaint
fragments and menu dispatch; they do not alter guest RAM, registers or policy.

All times below are **emulated seconds**, not host wall-clock time:

| Event | Screen 6 | Screen 7 |
| --- | ---: | ---: |
| Last Space trigger read before repaint, released | 252.826382 | 184.822607 |
| Button pressed over Desk | 252.869422 | 184.854559 |
| Button released over Desk | 252.949424 | 184.934560 |
| Next Space trigger read, already released | 252.962140 | 184.957675 |
| Interval between trigger reads | **135.758 ms** | **135.068 ms** |

The pointer stayed at byte column 12 / line 6, inside Desk, with Desktop focused
and no modal open. At press and release the paint source is `0x82`: the timer
repaint for window slot 1, Clock. There is no input sample during either pulse.
The next menu-dispatch observation has D=0, so its fresh-click test rejects it
before calling any application handler. The Screen 6 paint fragment began at
252.859783 and input resumed at 252.961668, approximately 102 ms later.
This measures the enclosing repaint path, not one individual VDP command.

Source chain:

- `lib/msx/input.asm`: `input_poll` clears `in_fire`; `read_trig` calls BIOS
  GTTRIG for Space and the joystick button, preserving only their current level.
- `kernel/input_api_msx.asm`: `k_poll` calls that sampler once per root poll,
  then moves/paces the pointer and publishes input.
- `kernel/core/poll_publish.asm`: the click edge is `in_fire & !poll_lastfire`.
  No sampled press means no edge, irrespective of the actual elapsed pulse.
- `kernel/core/menu_dispatch.asm`: only a fresh edge within rows 0–7 reaches
  the registered menu handler. In the failure, the fresh-edge bit is zero.
- `kernel/core/window_repaint.asm`: the root processes the visible paint
  fragment synchronously before returning to ordinary polling.

## Reproduction and controls

Evidence is under `build/msx-stability-82/evidence/`:

- Five ordinary traced Screen 6 Clock/Calculator lifecycle runs passed:
  `desk-click-run-6-{1..5}.log`. A handful of passes was not sufficient to
  qualify this intermittent interaction.
- Repeated Desk open/cancel with Clock seconds enabled failed in openMSX:
  Screen 6 after 37 successful openings (38th attempt), Screen 7 after 15
  successful openings (16th attempt). Logs are `desk-stress-{6,7}.log` and
  `desk-stress-trace-{6,7}.txt`; failing trace click IDs are 41 and 19 because
  the actor also counts Clock launch and focus clicks.
- The unmodified 1983 core at `5fce06f`, with Philips firmware and the same
  images, also missed an 80 ms Desk click in Screen 6: the 12th stress attempt
  timed out. `1983-desk-short-6-native-ui/result.json`.
- 1983 Screen 7 passed three short-click accessory lifecycle cycles plus 50
  Desk open/cancel cycles, 270 checks / 14213 frames:
  `1983-desk-short-7-native-ui/result.json`. This passing timing sample does not
  invalidate the openMSX Screen 7 failure. The precise sampling-gap proof is
  from openMSX; the 1983 check independently confirms the Screen 6 symptom.
- An initial 1983 diagnostic used the stale assembly `UI_TEXT=0x1708` alias
  for its menu-content assertion. The actual native C binding in
  `lib/gb/gbui_stub.c` uses `0x1708` for UI_NAME and `0x1718` for UI_TEXT.
  Only results after correcting that observer are counted above.

The new Tcl diagnostics are `debug/desk_click_trace_openmsx.tcl` and
`debug/desk_click_stress_openmsx.tcl`. The latter intentionally replaces the
post-Clock Calculator phase with 50 Desk open/cancel attempts: do not describe
its result as the complete accessory lifecycle suite. It leaves Clock open.
The additional 1983 diagnostic is retained locally as
`build/msx-stability-82/desk_short_1983.py`; it subclasses behavior through the
existing host driver without changing the emulator or guest image.

To reproduce from the matching isolated build, select the mode-specific kernel
symbols, a **new** trace filename, and the stress script before invoking the
existing disposable-card runner. Example for Screen 6 (inside my-distrobox):

```sh
cd /var/home/salvogendut/Dev/GEMBENCH/build/msx-stability-82
GEMBENCH_CLOCK_KERNEL_SYMBOLS="$PWD/build/msx/gbkernm.sym" \
GEMBENCH_CLOCK_REFERENCE_OUTPUT="$PWD/evidence/desk-next-clock.txt" \
GEOBENCH_DESK_CLICK_TRACE="$PWD/evidence/desk-next-trace.txt" \
GEOBENCH_DESK_TRACE_SCRIPT=/var/home/salvogendut/Dev/GEMBENCH/debug/desk_click_trace_openmsx.tcl \
GEOBENCH_ACCESSORY_SCRIPT=/var/home/salvogendut/Dev/GEMBENCH/debug/desk_click_stress_openmsx.tcl \
MSX_HEADLESS=1 MSX_TEST_MODE=6 MSX_UNAPI=0 \
bash tools/test_desk_accessories_openmsx.sh
```

For Screen 7 use `gbkernm7.sym`, `MSX_TEST_MODE=7` and fresh output names. Exact
failure attempt/timestamps depend on the Clock phase; the test is a reproducer,
not yet a deterministic acceptance test. Trace ring context is repeated before
each press, so deduplicate timestamps before computing event counts. Earlier
trace files label a primary-slot comparison `mapped`; that alone does not prove
the expected mapper segment is visible. The diagnostic now labels it explicitly
and also logs readiness and mapper state. Do not interpret arbitrary low-RAM
bytes observed during UI module loading as corruption.

## Original implementation proposal (subsequently authorized)

Preserve short button edges independently of slow drawing, then let the normal
root input path consume them exactly once. A small bounded capture/latch path
is preferable to calling the full poll/menu dispatcher from inside rendering:
that would make drawing reentrant and can change banks/focus mid-callback.

Before implementing, review the actual interrupt-disabled intervals, fixed-RAM
budget and raw Space/joystick/mouse sampling constraints. An interrupt-side
capture must not invoke BIOS, change application banks, dispatch menus or paint.
Keep edge capture distinct from the current held level used for dragging, and
define coordinates/order/overflow behavior so delayed input does not become a
click on the wrong window. Faster or more finely divided Clock painting may
help latency, but by itself does not protect all applications from lost edges.

Acceptance should keep 80 ms pulses, cover different phases in both modes and
both emulators, and check exactly-once clicks, hold/release/drag, modal changes,
focus changes and overflow/cleanup. Keep shared policy authoritative and run
relevant CPC regressions if shared input semantics change. This is an MSX
input-boundary fix proposal, not a new window-stack redesign or a longer-click
workaround.

## Implementation and verification — 2026-09-09

Implemented on `feature/82-msx-stability`, built separately in
`build/msx-buttons-82` from `f0c149c` plus the working changes. Normal MSX/CPC
images are unchanged. Shared core policy, CPC code and universal APP bytes are
unchanged; this is an MSX input adapter change.

- A fixed-page interrupt leaf captures aggregate Space/port-1 trigger edges
  during synchronous repaint without BIOS calls, bank switching or dispatch.
- Four FIFO records retain the last published/displayed pointer coordinates,
  focused window, generation and modal state. Overflow drops the newest edge;
  overflow/stale counters saturate. Stale context records are discarded.
- Normal root polling consumes at most one valid edge per call. Current held
  level remains separate, so a completed short press is not a stuck drag.
- Private `CF30..D0FF` storage replaces a reserved area; no public ABI, app
  bank or stack limit changes. Scheduler: 1451/1536 bytes; GBAPV4: 2549 bytes.
  Child COMs: 14300 (Screen 6), 15878/16128 (Screen 7). Dispatch lives after
  aligned screen tables to avoid consuming another 256-byte alignment page.

Evidence under `build/msx-buttons-82/evidence/`:

| Check | Result |
| --- | --- |
| openMSX Philips, 80-ms Desk clicks while Clock seconds repaint | PASS, 50 open/cancel cycles in each mode; `desk-fixed-{6,7}.log` and matching traces |
| openMSX ordinary Clock + Calculator | PASS both modes, `clock-fixed-*` and `accessories-fixed-*` |
| openMSX Paint Screen 7 | PASS, `paint-fixed.log`, including held dragging and focus/exposure |
| openMSX Settings Screen 6 | PASS save/readback/cold-reload, `settings-fixed-6/result.json` |
| 1983 core `5fce06f`, Philips | PASS 3 accessory lifecycle cycles + 50 short Desk cycles per mode; 243/273 checks, final one window, stack maximum 53; `1983-short-{6,7}/result.json` |
| 1983 core, candidate RainBIOS #169 Omega | PASS the same workload in both modes; `1983-rain-bitmap-{6,7}/result.json` |
| Host suite | PASS 294 tests, no skips; `all-host-tests.log`; low-RAM map also passes |

The assembled-code test `tests/msx_button_capture_test.c` covers Space and
port-1 input, exactly-once/held behavior, FIFO ordering/overflow, stale focus,
generation and modal records, register/port restoration and caller IFF state.
The retained 1983 regression is now `tools/test_msx_stability_1983.py` with
`--short-desk-stress`; it keeps 80-ms pulses and cleans up the final Clock.

Limits: capture requires interrupts to run (the normal preemptive MSX build).
Interrupt-disabled spans and sub-tick pulses remain outside the guarantee.
Queued positions follow the displayed pointer, not unpolled mouse movement.
The leaf restores PPI C and PSG R15 but, like BIOS interrupt handling, changes
the PSG register selector. Physical/SDL mouse smoothness is not qualified.
Observed keyboard-pointer gaps still reach 4–6 frames; this fix retains edges,
it does not remove synchronous repaint latency. No claim of whole-distribution
stability follows from these bounded checks alone. The subsequent
[baseline close-out](V1-MSX-STABILITY-BASELINE.md#close-out--2026-09-09) records
resolution of the remaining blockers and the start of the Notepad audit.

Test the fixed private image, **not the normal image or the initial candidate
build's stale aggregate image**:

```sh
MSX_UNAPI=0 tools/run_msx.sh build/msx-buttons-82/evidence/mode7/GEOBENCH.IMG
```

Use `mode6` for Screen 6. The RainBIOS candidate/evidence worktree
`build/rainbios-169` is retained; its fix is now merged in RainBIOS PR #171.
The first-VRAM-read discrepancy in
[RainBIOS #170](https://github.com/salvogendut/rainbios/issues/170) was subsequently
resolved by 1983 PR #172 (immediate IN timing), without another production
firmware change. Both issues are closed. No ROM was imported into `../1983`.
See the baseline close-out for merged revisions and final verification evidence.
