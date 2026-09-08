# Restart step 3D-P: Clock worker and source-only background repaint

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`. Follows
[3D-O shared accessories/Calculator](CPC-RESTART-STEP3D-O.md).

Status: **Clock's real worker and timer collector are connected in the composed
CPC/M4 runtime**. Clock and Calculator use the existing Desktop's exact-owner
activation policy. This is still a private test launcher, not the full Desktop
or its Desk menu. The production-adapter gate remains open.

## Implementation

The existing shared 116-byte timer collector is linked into the resident
runtime, using the same native bindings as the earlier service fixture. The
root bar collects timer requests before refreshing the existing Desktop bar,
matching the native Desktop order. The shared scheduler still selects workers
using its existing focus/visibility policy; no CPC worker scheduler is added.

The high capability word changes `009F -> 00DF`, enabling the existing
`background-timers` bit `0040`. The low word remains `0F8B`. ABI version,
jump-table positions and APP snapshot reservation do not change. Other gated
services are not advertised prematurely.

F2 opens/activates Clock through the same generated accessory catalog and
identity-first Desktop code as F7/Calculator. An existing owner is found before
checking free window slots, so activation still works with a full table.
These are temporary launcher controls, not a replacement menu policy. F2 is
used because 1984 reserves host F8 for its monitor; the main keyboard number
row remains available for application input.

Background validation exposed two common-code problems:

- A timer's damage rectangle repainted other windows intersecting it, even
  though only the requesting window's surface changed. The shared repaint loop
  now accepts the collector's validated active source byte and paints only that
  source's effective visible fragments. Both CPC runtime and MSX2 visible
  compositor bind this option. Ordinary move/focus/exposure passes still walk
  every affected layer using the unchanged shared region iterator.
- Clock's rectangular hand damage can intersect dial rim/tick pixels. Clearing
  that region and drawing only hands left gaps in the rim. The common Clock
  now restores the face through the existing damage clip before drawing hands.
  It does not clear/repaint the complete window, its frame or the desktop.

The CPC software-pointer leaf walks that same visible-region iterator before
painting. It saves/restores the pointer only when an effective timer fragment
touches it, then restores the original damage bounds for the real pass. A
pointer over the covering window stays untouched. This is a hardware exclusion
binding, not a second overlap policy. MSX retains its hardware sprite handling.

Fully covered Clock windows receive neither worker calls nor repaint work.
When only the title remains exposed, the worker still runs under the existing
partial-visibility policy, but fully covered component damage is acknowledged
without backend drawing or pointer work. No new all-application CPU policy is
claimed beyond the existing shared scheduler/visibility behavior.

Two fixed launcher counters observe worker entry and backend drawing, including
transient work that final screenshots alone could miss. They make no scheduling
decisions and allocate no APP state.

## Binary identity and budgets

The builder compiles `apps/uclock` with the same universal profile as MSX2:
`UNIVERSAL_TASK=1 UNIVERSAL_WINDOW_KIND=1 UNIVERSAL_ACCESSORY=1 UNIVERSAL_MENU=1
DATA_LOC=0x7300`. There is no CPC-specific Clock source or platform define.

The common rim fix changes Clock from 7,571 to **7,580 bytes**. Its SHA256 is:

`73a3786bb08f75162018cfeeaaad2add5eb4f240bd72725441d8a6681b22a90c`

That same resulting APP is loaded on CPC and tested on MSX2 Screen 6 and 7.
This is not a claim that the old release Clock bytes are unchanged. Calculator
remains 7,825 bytes with the identity recorded in 3D-O.

| Allocation | Used | Budget |
|---|---:|---:|
| Resident kernel, including root helper reservation and timer collector | 13,107 | 16,384 |
| Bar/accessory root helper within that total | 941 | 1,536 |
| Root C0 helper state | 13 | 32 |
| Low support | 1,832 | 3,072 |
| Hardware leaves | 1,130 | 1,536 |
| Scheduler, including observation counter hook | 1,446 | 1,536 |
| F7 filesystem module | 4,502 | 7,168 |

The Clock run observes 99 bytes of the unchanged 256-byte main stack, IRQ 4,
temporary 6. The filesystem regression still observes 127 main-stack bytes.
All stack guards, immutable code/font bytes and bank/mode invariants are checked.
MSX kernel sizes remain 13,956 (Screen 6) and 15,534 (Screen 7): the shared
13-byte source filter fits existing alignment padding, but kernel contents
are intentionally changed.

## Validation

- The M4 Clock scenario checks exact full-frame composition at 22 checkpoints:
  launch, seconds, focused/background ticks, focus changes, covered components,
  partial exposure, pointer over a covering window and over changing Clock
  pixels, save-under restoration, complete occlusion, hidden reactivation,
  repeated/full-capacity activation, close cleanup and fresh-generation relaunch.
  A read-only M4 service transaction also runs while Clock is live.
- The oracle independently constructs integer dial/hand geometry, digital
  labels, furniture and the final z-ordered screen. It uses completed APP time
  values, never observed framebuffer pixels as expected output. Sampling requires
  identical completed pixels across a root-loop boundary; no guest RAM is
  injected. Worker/draw/pointer counters separately reject hidden or unnecessary
  work even if a transient redraw would end with the same pixels.
- Existing CPC M4 regressions pass: eleven ordinary-window checkpoints,
  ten menu checkpoints, nineteen Calculator/accessory checkpoints, and
  46 portable-filesystem checks.
- Instrumented native MSX Desk lifecycle tests pass in openMSX Screen 6 and 7
  using private media. Each observes 46 timer-source fragments and 23 clipped
  rim repairs; any active timer fragment for another window fails the test.
  Both also execute the actual Clock worker and preserve the existing Desk
  registration/activation/teardown and stack checks.
- Full `make check` passes in an isolated worktree: **212 Python tests without
  skips**, plus native C, SDK/ABI and distribution checks. Added tests cover
  timer-source layout contracts, resident collector binding, common Clock
  wiring and pixel-oracle sensitivity to the reproduced rim gap.

Logs: `/tmp/geobench-77p-clock-final.log`,
`/tmp/geobench-77p-accessories-final.log`,
`/tmp/geobench-77p-{runtime,menus,fs}.log`,
`/tmp/geobench-77p-clock-msx{6,7}.log`, `/tmp/geobench-77p-check-final.log`.
1984 executable SHA256:
`00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`.

No emulator changes, floppy tests or working MSX release-media updates were
made. The MSX private card stages the current 2,238-byte `GBAPV4.MOD` with its
matching kernels; mixing them with the older 2,079-byte gate rejects boot.
The user's `QA/CPC/` tree and recording are preserved. M4 validation does not
qualify Albireo or enable PCW.

## Manual test

The private M4 runtime is rebuilt under `QA/Diagnostics/CPC-runtime`:

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Press **F2** for Clock, then **S** to toggle seconds. **F7** opens Calculator.
Use arrows and Space to point/click; hold Space on a title while moving the
pointer to drag. Cover Clock partially, then completely with Calculator; it
should update only where exposed. F2 brings back the same Clock with its
seconds setting retained. Escape closes it; F2 then opens a fresh instance.
The pointer adapter is still the keyboard/joystick test binding, not a claim
of completed CPC mouse hardware support.

Rebuild and run the automated Clock test with the installed toolchain:

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-clock-1984
```

`make diagnostic-cpc-runtime` builds without running the test. On a separately
built, matching MSX reference card, run
`MSX_HEADLESS=1 MSX_TEST_MODE=6 bash tools/test_clock_runtime_openmsx.sh`
(repeat with mode 7). Its underlying Desk harness copies the card before use.

## Next

Follow-up [3D-Q](CPC-RESTART-STEP3D-Q.md) now provides the real shared Desk menu
and relocates the native root component into its owned C0 page. Its measured
allocations supersede the root-helper/fixed-kernel budgets above; System and
the complete Desktop/File Manager still need their native providers.

Integrate the real Desktop root/UI and Desk menu, then its assets and File
Manager/M4 navigation, resolving their remaining native service bindings in the
same budgeted runtime. Do not grow the private F-key launcher into another
Desktop. Full application parity and Albireo qualification remain subsequent
gates in the [restart plan](CPC-RESTART-PLAN.md).
