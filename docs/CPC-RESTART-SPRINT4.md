# CPC restart — Sprint 4: stabilization and delivery

Started 2026-09-08 on issue #77, `feature/77-cpc-production-adapters`, after the
accepted Sprint 2/3 checkpoint `fa1b417` was committed and pushed to origin.
This is the final desktop-first sprint in [the restart plan](CPC-RESTART-PLAN.md).

## Work packages

1. **Combined window and input acceptance.** Exercise the delivered Desktop,
   File Manager and portable Clock/Calculator together: focus, drag, resize,
   overlap/exposure, exact partial damage, fully hidden Clock suspension and
   pointer cadence. Reuse the existing shared core and independent pixel models.
   Fix demonstrated defects, not hypothetical ones.
2. **Consolidated regression and repeatability.** Combine mixed lifecycle and
   capacity checks with native/boot rejection tests, repeatable media payload
   checks and proportionate MSX regressions. Keep tests on disposable M4 images.
   Investigate a second M4/Albireo-capable emulator only within its actual
   supported capabilities; no floppy workaround or unverified cross-check claim.
3. **Delivery handoff.** Finalize build/test commands and known limitations,
   record evidence, rebuild a matching manual image if runtime payloads change,
   and obtain confirmation before proposing PR/merge.

## Boundaries

No new CPC-specific window manager, app implementation or portable ABI.
Do not add Settings, PAINT, BASIC, PCW, file copy/delete or full application
parity to this sprint. Albireo and hardware mouse support remain separately
qualified capabilities. Existing user cards, parked `QA/CPC`, recordings,
normal diagnostic media and MSX media are preserved.

## Progress

**Complete and manually accepted — 2026-09-08.** The user confirmed the rebuilt
image and authorized committing, pushing and merging this checkpoint before
starting Settings integration. New disposable M4 acceptance paths run on
`cpc-desktop-m4-v2`, not a substituted diagnostic launch surface. Guest input
is ordinary keyboard/joystick input; observations do not inject RAM, force a
repaint or patch the emulator. The regular manual M4 image has been rebuilt
and verified against the passing isolated candidate. The accepted Sprint 3
card was backed up before replacement.

Published as commit `80800be`, pushed to `feature/77-cpc-production-adapters`,
then merged into `main` by [PR #78](https://github.com/salvogendut/GEMBENCH/pull/78)
on 2026-09-08 (merge commit `68b1607`; issue #77 closed). Only after that merge,
[Settings integration](CPC-SETTINGS-INTEGRATION.md) began on a separate branch.

### Final automated acceptance and delivery — 2026-09-08

- **20/20 combined M4 scenarios pass**, including all native/root rejection
  cases, capacity/modal recovery, persisted View after cold restart and
  **32 stacking checkpoints**. Maximum observed stacks across the suite are
  **160/256 main, 4/256 IRQ, 6/128 temporary**; guards remain intact.
- Cursor cadence passes on the delivered Desktop/File Manager with Clock,
  including an independent repeat, seconds-off restoration and cursor
  crossings through timer damage. All samples stay within the unchanged
  gap/throughput/stationary-span limits; seconds-on cases actually draw.

  | Workload | Pointer steps/s | Maximum IRQ-tick gap |
  | --- | ---: | ---: |
  | Baseline / seconds off | 50 | 6 |
  | Focused Clock seconds, both runs | 49.62–50 | 10 |
  | Background Clock seconds, both runs | 48.86 | 9 |
  | Desktop minute rollover without Clock | 50 | 9 |

- Full `make check`: **269 Python discovery tests, no skips**, plus all
  native/SDK/ABI checks. Drawing coverage is **62 vectors / 26 pixel captures**,
  with the broken-clip negative fixture detected; custom-font/palette and
  invalid-font fallback checks also pass.
- Fresh MSX build and **four openMSX Clock/Desk runs in Screen 6/7 pass**.
  The optional timer-rank shortcut is enabled only by the CPC runtime provider;
  MSX retains its prior behavior. Portable Clock/Calculator binaries remain
  identical across the two targets.
- No memory budgets were increased. CPC kernel: **15,776/16,384 bytes**;
  scheduler: **1,452/1,536**; native File Manager code/data:
  **13,367/14,336** and **1,538/1,792**.
- `make cpc` rebuilt `QA/CPC-Desktop/GEOBENCH.IMG`. All **33 staged and actual
  FAT payload hashes match the isolated passing candidate**; native admission
  binding and pristine-image validation pass. Disk image hashes may differ
  because FAT metadata differs between builds, not because payloads differ.
- Manual image SHA-256:
  `802bfca53dbf15010ddbd056ca8a443d7902bf8ac9ddbe40c0f83acf8c4d7e05`.
  Previous accepted card backup:
  `/tmp/geobench-sprint4-manual-backup-YOl57Q/CPC-Desktop/`.
  This is a local temporary backup, not an archival Git branch.
  Normal diagnostic/MSX images, parked `QA/CPC`, recordings and the emulator
  executable remain unchanged.

Evidence: `/tmp/geobench-sprint4-delivery5b.log`,
`/tmp/geobench-sprint4-check-GgteKA/final-delivery-result.json`,
`/tmp/geobench-sprint4-cadence-repeat.log`,
`/tmp/geobench-sprint4-finalcheck5.log`,
`/tmp/geobench-sprint4-msx-final.log`, and
`/tmp/geobench-sprint4-manual-{build,verify}.log`.
The diagnostic drawing/font evidence predates the final timer shortcut; that
shortcut does not change the drawing leaves or diagnostic drawing fixture.

For the manual check, run the rebuilt M4 image:

```sh
distrobox enter my-distrobox -- bash tools/run_cpc.sh
```

Open Disk C, launch Clock and Calculator, enable Clock seconds with **S**,
then focus, overlap, move and resize windows while moving the pointer. Check
that a fully covered Clock does not flash through its covering window and
that exposure/closing restores clean pixels. Also check minute rollover and
the smallest File Manager size. The runner uses the generated 512K M4 setup,
not floppies. See [Sprint 3](CPC-RESTART-SPRINT3.md) for the browsing controls.

The desktop-first sprint is accepted. Broader application parity and a second qualified M4/Albireo runner
remain explicitly deferred; this does not claim a complete CPC port.

### First results — 2026-09-08

- The delivered-window `stacking` scenario passes **26 checkpoints**, including
  the actual resize grip and hidden Clock worker/snapshot invariance. Stack
  maxima are **146/256 main**, **4/256 IRQ**, **6/128 temporary**.
- Full `make check` passes: **265 Python discovery tests**, no skips, plus the
  native/SDK/ABI checks. Two sampler tests cover video-time measurement despite
  lost IRQ ticks and releasing held input if an observation fails.
- Cursor cadence is **not yet accepted**. Baseline and seconds-off measure
  50 steps/s with 6-tick maximum gaps. The foreground-seconds sample measures
  47.73 steps/s but a **35-IRQ-tick gap** and a **3-video-frame stationary
  sample span**. This gap coincides with software minute rollover: at IRQ
  18,060 the PC is `br_byteloop`, the parameter timer owner is zero, and the
  cursor does not move. `bar_clock()` explicitly hides the pointer around the
  native text call; the existing pointer safe point respects that hide.
- The partially exposed background-seconds sample also falls below the
  unchanged cadence limits: **44.32 steps/s** (less than 90% of baseline),
  **17-tick gap**. This needs profiling separately; do not assume the minute
  refresh explains every slowdown.
- A separate `minute-cadence` test aligns ordinary held input with minute
  rollover **without opening the Clock app**, to isolate the top-bar case.
  Its samples also record software seconds and pointer visibility. The test
  preserves the existing limits rather than avoiding the minute boundary.
  It reproduces a **16-tick gap** at rollover, **49.24 steps/s** and one sample
  with the cursor hidden, despite having no Clock application/worker. Thus
  the native top bar contributes a stall independently of Clock timer damage.

These were the pre-fix results. The cadence limits remain unchanged throughout
stabilization; passing the other scenarios cannot compensate for a failed
cadence or pixel check.

Local evidence: isolated worktree `/tmp/geobench-sprint4-check-GgteKA` and
`/tmp/geobench-sprint4-{stacking,cadence,minute,check}.log`. Only the About dialog
build ID in `GBUI.MOD` differs from the accepted Sprint 3 payloads after commit
`fa1b417`; kernel, Desktop, File Manager and portable app payloads are unchanged.
Normal/manual M4, diagnostic and MSX images and `../1984/1984` are untouched.
At that initial checkpoint Sprint 4 work was local and uncommitted; the
accepted Sprint 2/3 checkpoint was already on origin.

### Implementation and regression work — 2026-09-08

- CPC text now rejects wholly invisible glyphs before raster work and uses a
  two-byte fast path for fully visible 6x8 glyphs at phases 0/2. Partial clips
  and other geometries retain the generic emitter. No new glyph cache, bank
  allocation or ABI is introduced. Skipping invisible titles also removes the
  long interrupt blackout in background Clock chrome.
- The existing root-only pointer service is reused before explicit native
  hides, at compositor fill/text boundaries, and before timer collection.
  A private call-site trace located the remaining 14-tick gap from `k_poll`
  to the first compositor fill. A subsequent stage trace measured **eight
  ticks inside full visibility refresh**, entered five ticks after the prior
  sample. An extra input check before refresh was not due yet and did not fix
  this. That unsuccessful extra binding has been removed.
  It still respects explicit hides and pending compositor damage; no input
  dispatch, keyboard scan or drawing was moved into the IRQ handler.
- The actual shared File Manager minimum width changes from 24 to **29 byte
  columns**: five columns for chrome/scrollbar plus three eight-column icons.
  The prior limit made icon centering negative at minimum size. The host test
  checks every admitted grid width; real resize-grip tests cover minimum,
  maximum, top-left/bottom-right and repeated shrink/grow. The test steers only
  to physically reachable pointer positions when requesting an edge clamp.
- `make cpc-delivery-1984` builds once and runs **20 independent scenarios**
  on disposable M4 copies: Desktop, File Manager lifecycle/workflow/services
  (including persisted View after cold restart)/context capacity, stacking,
  minute/cursor cadence, six native File Manager rejection cases and six
  root/parser boot rejection cases. A failed child fails the suite. Per-case
  logs and a JSON summary retain the emulator, image and payload hashes; source
  staging/image integrity is rechecked after all runs. `CPC_TEST_JOBS=4` allows
  separate emulator processes, never concurrent builds.
- The expanded real drawing fixture has **62 vectors / 26 pixel captures**,
  including both six-pixel phases, every pen and nonzero/equal paper. A broken
  clipping build must still be detected. Four extra vectors fit the existing
  fixed diagnostic map; no kernel allocation limit was increased.
- Full host/build checks pass **267 Python tests with no skips**, plus the
  native/SDK/ABI checks, on the second candidate. Custom-font/palette rendering
  passes ten M4 checkpoints; invalid font-width fallback passes three.
- The first combined candidates pass the ordinary delivery/failure cases but
  are **not accepted**: background cadence still reaches 14 IRQ ticks, and one
  earlier candidate produced a blank seconds field caught by the pixel oracle.
  These failures are retained in the logs, not dismissed as emulator bugs.
  The pre-collector input boundary and corrected edge test are undergoing a
  fresh combined run. The accepted manual image has not been replaced.
- Expanded stacking passes **32 checkpoints**, including all six added edge
  geometry checks, on the third candidate. A separate context-popup failure
  was a premature observation, not damaged final pixels: the captured native
  UI status was **1 (module loading)** even though `UI_MODAL` was already set
  and the M4 bus was momentarily idle. The checker now requires renderer-entry
  status zero, unchanged labels and stable pixels; a host regression rejects
  loading/error statuses. Clock cache values are also part of frame stability.
- A fresh isolated **MSX build** succeeds with the shared minimum-width fix.
  Clock/Desk checks pass under openMSX in **Screen 6 and Screen 7**, using Xvfb
  for its OpenGL renderer (SDL's dummy video driver cannot render this build).
  Both Clock runs verify background worker execution, source-only timer
  fragments and clipped rim repair. CPC/MSX `CLOCK.APP` and `CALC.APP` payloads
  remain byte-identical; no universal application or ABI code changed.

The fourth combined run passed **19/20 scenarios**, including modal capacity
and all 32 stacking checkpoints, but still failed background cadence at 14
ticks. Full host checks passed **268 tests, no skips**, plus native/SDK/ABI.

The fifth candidate removes that redundant work in the **shared visibility
core**, with the CPC runtime provider opting in: an active, validated
content-only timer consume captures its damage but retains established window
and worker rankings. Queued/ordinary damage still reclassifies the stack;
every source fragment still goes through exact occlusion subtraction. The
callback contract already forbids geometry/ownership/z-order mutation during
painting. No new cache, dirty flag, input event dispatch or IRQ work is added.
The optional binding has fixed-address assertions and an assembly regression.
The MSX provider retains its existing conservative refresh: enabling the same
optimization there made the timed Clock/Desk harness miss Calculator launch
(no registration/request was observed). That unqualified MSX change has been
removed; a separate timing investigation is outside CPC delivery scope. The
generic assembly regression checks either fixed-memory placement, without
claiming the opt-in path is qualified on MSX. Fresh full host checks pass
**269 Python tests, no skips**, plus native/SDK/ABI checks. The rebuilt MSX
passes all four Clock/Desk checks in Screen 6/7 with its existing behavior.
Combined CPC acceptance subsequently passed; see the final results above.

Latest combined run: `/tmp/geobench-sprint4-delivery5b.log`, with trace-free
production sources. Earlier candidate logs and the private timing traces remain
available under `/tmp/geobench-sprint4-*`; the trace instrumentation exists
only in retained test artifacts, not the repository sources. Fresh host checks
are in `/tmp/geobench-sprint4-finalcheck5.log`; the fresh MSX build/execution log
is `/tmp/geobench-sprint4-msx-final.log`. Earlier MSX execution evidence is in
`/tmp/geobench-sprint4-openmsx.log` and `/tmp/geobench-sprint4-msx-juoATi/`.

Additional emulator source checks are recorded in the
[M4/Albireo-only strategy](CPC-EMULATOR-TEST-STRATEGY.md#2026-09-08-sprint-4-recheck).
There is still no qualified independent CPC emulator or real-board result.

## First acceptance commands

With the project toolchain available in `my-distrobox`:

```sh
make cpc-stability-1984
```

This builds the regular M4 Desktop profile, then tests separate disposable
copies with `stacking`, `minute-cadence` and `cadence` scenarios. Against an
already freshly built image, the scenarios can also run independently:

```sh
python3 tools/test_cpc_runtime_1984.py --desktop-delivery --filemgr-scenario stacking --skip-build
python3 tools/test_cpc_runtime_1984.py --desktop-delivery --filemgr-scenario minute-cadence --skip-build
python3 tools/test_cpc_runtime_1984.py --desktop-delivery --filemgr-scenario cadence --skip-build
```

For all combined delivery checks, use `make cpc-delivery-1984` (optionally
`CPC_TEST_JOBS=4`). These gates must all pass before release acceptance.

The stacking scenario checks title-only Clock work without paint, physical
File Manager resize-grip shrink/grow, partial exposure, stationary cursor
preservation on the covering window, save-under repair, fully covered worker
suspension, exact Desk reactivation, and Calculator input/drag/close among the
other windows, plus minimum/maximum and screen-edge resize combinations.
Fullscreen behavior is also covered by the Sprint 3 workflow scenario.

The cadence scenario reuses the diagnostic sampler/checker on the real
Desktop/File Manager. It measures no Clock, seconds off, foreground seconds,
partially exposed background seconds, and seconds off again. Limits remain
at least 40 pointer steps/second and 90% of the baseline, no stationary run
over two video frames and no movement gap over 12 IRQ ticks. Seconds-on cases
must actually draw. Cursor crossing checks independently reconstruct the
composed screen before a focus change could conceal a trail. These are
emulated keyboard/joystick cadence limits, not a hardware mouse/blocked-I/O SLA.
