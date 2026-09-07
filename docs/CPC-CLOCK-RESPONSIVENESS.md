# CPC Clock / cursor responsiveness

2026-09-07, issue #77, `feature/77-cpc-production-adapters`.
Follow-up to [3D-S](CPC-RESTART-STEP3D-S.md), before the next asset checkpoint.

## Defect and fix

With seconds enabled, the CPC virtual pointer slowed down and moved in bursts.
It advanced once per root-loop pass, followed by a fresh six-IRQ wait. Clock's
background repair also recalculated every dial endpoint and traversed lines
outside the effective damage clip. IRQ masking made software-tick-only timing
understate the remaining delay.

- Pointer samples now follow a persistent 16-bit, six-tick cadence. Root-side
  `GB_PARAMS` boundaries also service movement between primitives. They do not
  dispatch clicks, change focus, invoke callbacks, or switch application banks.
  Missed periods are not replayed as large cursor jumps.
- Safe points preserve registers, IX, caller IFF and scheduler lock. Workers
  cannot use them to draw. Explicit pointer hiding/suppression is respected;
  a pointer entering pending timer damage stays hidden until the pass completes.
  The compositor's clip and region iterator are never modified by pointer work.
- The CPC root callback, safe-point cursor copy and serialized parameter adapters keep time IRQs live
  through application calculation, validation and clipped-out drawing calls.
  Short bank/telemetry transactions still use DI. The IRQ handler itself remains
  unchanged: no keyboard/PPI access, drawing, callbacks or bank changes.
- The common compile-once Clock caches relative dial/tick/hand endpoints. Moving
  the window only translates them; resizing invalidates the radius cache.
  Integer rounding and MSX pixel-aspect correction are retained. Cache storage is
  936 bytes plus two state bytes; Clock data still fits below its reserved stack.
- CPC rejects fully clipped text/lines before rendering and chooses line ink
  once per line. Small damage therefore avoids unnecessary raster work.
- A covered timer component can be dropped without repainting, leaving its
  narrow clip installed. The CPC root bar now explicitly restores the full clip
  after collection, before its shared delta-refresh code updates the menu cache.
  This fixes a missing menu title exposed by the regression; it adds no repaint.

There is no alternate Clock, window manager or application ABI. MSX and CPC
still use byte-identical `CLOCK.APP` packages.

## Regression and manual test

`make diagnostic-cpc-latency-1984` builds a private M4 image and tests Clock
absent, seconds off, seconds on with focus, seconds on in the background, and
seconds off again. It checks actual emulator video-frame timestamps as well as
IRQ counters, rejects screen-edge saturation, and requires real drawing work
with seconds enabled. It also moves the pointer through timer damage and checks
the entire composed surface before a full repaint could hide save-under damage.

The limits are at least 90% of the no-Clock movement rate (and at least 40
steps/second), no input-sample gap above 12 IRQ ticks and no equal-position sample
span above two video frames. Movement speed is calculated from video frames,
not the software IRQ clock. The IRQ/video ratio is reported separately; the
CPC software clock can still lose ticks in native critical sections. Improving
that clock's accuracy is separate from this input-latency fix.
This is a regression bound for this workload, not a hard-real-time guarantee
for arbitrary applications, blocking storage operations or untested hardware.

For an already built image:

```sh
distrobox enter my-distrobox -- python3 tools/test_cpc_runtime_1984.py \
  --skip-build --latency
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Open Clock with **F2**, enable seconds with **S**, and hold the arrow keys.
Repeat after clicking empty background (**Space** clicks). Move across Clock as
well as beside it. Seconds should continue while the pointer remains responsive.
The ordinary `QA/CPC/` card and `QA/MSX/GBMSX.IMG` are not used or overwritten.

## Recorded result

The final video-timed M4 run passed, including nine pointer crossings and exact
composed-screen checks before any focus/full repaint. Each timed interval spans
132 actual video frames:

| Clock state | Pointer steps / second | Largest sampled input gap (IRQ ticks) |
| --- | ---: | ---: |
| Not open | 50.0 | 6 |
| Seconds off | 50.0 | 6 |
| Seconds on, focused | 48.5 | 9 |
| Seconds on, background | 47.0 | 10 |
| Seconds off again | 50.0 | 6 |

No equal-position span was observed between successive video samples. The
background IRQ/video ratio was 0.957: IRQ-derived time alone would overstate
cursor speed, so the reported rates above use actual video time. The original
long stalls are removed; software-clock drift remains a separate limitation.
Log: `/tmp/geobench-cpc-latency-accepted.log`.

Other validation:

- Full isolated `make check`: 226 Python tests, no skips, plus native C,
  SDK/ABI, deterministic compile-once APP and distribution checks.
  `/tmp/geobench-cpc-latency-check5.log`.
- Final image: ordinary windows/focus/drag/save-restore (11 checkpoints), custom
  font/palette with Calculator/native popup (10), runtime assembly/layout tests
  (3), and actual C geometry/cadence-checker tests (3) pass. Logs:
  `/tmp/geobench-cpc-latency-runtime6.log`, `-assets6.log`, `-runtime-unit6.log`
  and `-unit6.log` under the same `/tmp/geobench-cpc-latency` prefix.
- Clock visibility/parking (22), Desk lifecycle/capacity (26), and native
  dialogs with live Clock (23) pass on the preceding candidate. The final
  refinement only enables IRQs during safe-point cursor copying and masks them
  again before restoring the saved lock/IFF; the final moving-pointer regression
  covers that change. Logs: `/tmp/geobench-cpc-latency-clock5.log`, `-desk5.log`
  and `-native5.log` under the same prefix. Maximum observed stack use across
  these suites is 127/4/6 bytes (main/IRQ/temporary), with intact guards.
- The byte-identical new Clock passes openMSX Screen 6 and Screen 7, with 48
  timer-source fragments and 24 rim repairs in each. The Screen-6 harness now
  holds the real S key until Clock acknowledges it; an earlier short pulse
  missed initialization. No guest memory is injected.
  Logs: `/tmp/geobench-cpc-latency-openmsx6-ack.log` and `-openmsx7.log`.

Final CPC kernel/support usage is 12,721/16,384 and 1,836/3,072 bytes.
Clock is 8,060 bytes; its data ends at `7A33`, below the `7F00` task-stack boundary.
Hardware, scheduler and root module budgets are unchanged.

- `CLOCK.APP`: `9065baf3bc28430d0c1f90b463507027e3b60795930d814c382e0dfdf1329d96`
- CPC `CORE.RAW`: `ab1a33708519d3558b58904b3c650377a71be12b0c8a9a3de17a029a89e9f57c`
- Private `RUNTIME.IMG`: `2114f45405762875b1550832bd8ff6b7d51e79116eca7aa18c31faf91efea660`
