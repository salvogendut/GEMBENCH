# Step 3D-G: shared root loop, input routing and gestures on CPC

Date: 2026-09-06. Issue [#77](https://github.com/salvogendut/GEMBENCH/issues/77),
branch `feature/77-cpc-production-adapters`. Previous checkpoints 3D-E/F were
committed and pushed together as `8e856e8` before starting this work.

Status: **14 real-keyboard M4/1984 interaction checkpoints pass**. CPC now runs
the same root loop and native managed-window input/gesture policy as MSX, not
the previous scripted root-turn driver. This still uses native fixture surfaces,
a plain bar and menu-definition sinks. It is not the loaded Desktop, a public
APP loader or completion of the production adapter gate.

## Shared code and CPC leaves

Five units are extracted from the working MSX sources and included by both
targets, preserving MSX instruction bytes:

| Unit | Existing behavior |
|---|---|
| `root_loop.asm` | Map focus before polling; route focus; run the one-head deferred phase; call managed or legacy frame; call the bar in its root bank; yield through the shared scheduler. |
| `poll_publish.asm` | Fresh-click edge, quit/held flags, menu dispatch before coordinate/flag publication. |
| `menu_dispatch.asm` | Modal guard, top-eight-line hit check, focused app callback, click consumption and flag preservation. |
| `window_frame.asm` | Frame and close notifications, kind-aware content/title/gadget routing, maximise/restore and notifications. |
| `window_gestures.asm` | Legacy/silent versus managed move, explicit resize, bounds, outline/backdrop, final geometry/damage publication and notifications. |

The native routing contract asserts the 25-byte record, frame/flag offsets and
byte-sized screen bounds. The root loop's final back-edge is a provider macro:
MSX retains its original relative jump; the diagnostic CPC back-edge observes
or exits only after the actual frame/bar/yield path has completed. Root loop,
focus, routing and gestures are not reimplemented by that observer.

CPC poll uses the already-qualified firmware-free AY/8255 scan, cursor keys
or joystick directions, Space/joystick fire 1, and Escape. A held direction moves
one logical byte-column or scanline per poll, clamped to 80 by 200. Six hardware
IRQs pace each poll (at most 50 polls/sec with the current 300-Hz adapter).
It preserves the mapped application bank and root lock, allows IRQ timekeeping,
and uses the existing software-pointer erase/show leaves only on movement.
The shared publication code supplies click edges; there is no CPC-specific
focus or menu policy in the input adapter.

The diagnostic selects the existing **solid backdrop/plain furniture** behavior.
Themed tiles, logo/backdrop loading, actual menu definitions and bar rendering,
text-key translation/repeat, mouse protocols and acceleration are not claimed.
Joystick mapping is present but runtime qualification in this checkpoint uses
the actual CPC keyboard matrix, not a joystick or mouse test.

Fixed routing state uses `3300..3314` within the existing guarded integration
reservation; service scratch begins at `3350`. Fixture telemetry occupies
`1E00..1E81`. No framebuffer/raster-gap state, stack relocation or public ABI
change. The app-linked timer collector remains 116 bytes in the root app page.

## M4 execution and independent checks

Boot uses real M4 media and the standard 64 root/worker/keyboard/M4 rounds.
The driver then steers cursor/Space/Escape keys through 1984's keyboard input.
F2 is a diagnostic-only pause at a safe root-loop boundary for **read-only**
snapshots. F1 requests balanced-return cleanup; it does not reset the stack.
No saved-state boot, RAM injection, emulator changes or floppy boot is used.

Fourteen checkpoints:

1. Initial native legacy worker and explicit managed control window.
2. Cross-owner focus, including exactly one content click during a long hold.
3. Top-bar click delivered to the focused app and consumed before focus routing;
   its callback queues a message consumed by the same real root-loop iteration.
4. Return to the other application's window.
5. Desktop focus while its z-order remains pinned at the bottom.
6. Same-owner sibling activation consumes the initial click.
7. A second press delivers exactly one content click.
8. Kernel-owned title movement, final moved payload and old-position cleanup.
9. Grip resize, final sized payload and exact composited output.
10. Windowed maximise to `(0,8,80,192)`.
11. Fully covered worker receives no compute time while the root loop continues.
12. Restore the exact pre-maximise geometry.
13. Escape delivers a close request to the managed proc.
14. Legacy title press delivers `GB_MSG_DRAG`, retaining the app-owned contract.

The fixture intentionally logs close/legacy-drag requests rather than choosing
application policy. The final F1 cleanup actually closes the added control
window through the shared lifetime path, unregisters the endpoint and restores
the original root/worker fixture. It verifies normal returns and stack guards.

At every boundary an independent host renderer composes surfaces by topmost
pixel ownership and overlays the software cursor. Full 16-KiB framebuffer
comparisons include the non-display gaps, exposing stale frame/outline/pointer
pixels. Geometry expectations for gestures come from the observed physical
press/release coordinates, not from copying the resulting window record.
Assertions check focus/z-order, bank/root/lock, pointer/public coordinates,
full clip, callback counts/payloads, root-bar/turn accounting and hidden CPU.
The common runner checks code/font integrity, M4 records, IRQ/software time,
state/stack guards, owner pages and 150 additional frames of stable final RAM.

Two negative providers deliberately map the bar into the worker's bank or leak
a consumed top-bar click into focus routing. They must fail on the specific
bar-bank or menu-focus invariant. The callback fixture distinguishes deferred
receiver identity from focus; background delivery is legitimate shared behavior,
not a reason to reject a correctly mapped callback.

## Validation and limits

The initial positive run `/tmp/geobench-cpc-production-b5ovpfql`, log
`/tmp/geobench-77g-routing.log`, passes all fourteen checkpoints in about
88 host seconds: 64 I/O rounds, 717 M4 commands and 1,753 real root-loop turns.
It measures main/IRQ/temporary stack use 26/4/6 bytes and context high-water 26.
Those are workload observations, not worst-case stack/latency bounds.

The final positive run with the corrected diagnostic callback-identity check is
`/tmp/geobench-cpc-production-9_56gr3t`, log
`/tmp/geobench-77g-routing-final.log`. It repeats all fourteen checkpoints with
the same turn/IRQ/stack measurements (23,994 IRQs). M4 image SHA-256:
`779766446fa67c3b350ed4b42377af04eadeda9b59e17ca31e783cb2a0598476`;
final framebuffer SHA-256:
`dd1a6e8c3f0fe4894901bfa283e6187b4befeb8e4d08d46527c3a0e7c87ce23e`.

The shared root/frame/gesture/menu block is 960 bytes (poll publication is
included with the CPC poll leaf). The final diagnostic high payload is
14,650 / 16,384 bytes,
including fixtures, font and older unused vectors; this is **not complete
kernel usage**. Low support/scheduler/hardware stay 1,673/1,437/1,055 bytes.
Only two owner pages are needed; no bank pages are allocated for framebuffer
captures because the host stores read-only observations. Final free pool: 26.

Both MSX kernels retain the previous hashes after reassembly:

- Screen 6: `1f8f5d37e3350a1c07a8e17df947fa95a62dc97d0c78dfad6bb6eaeddeb4d59f`.
- Screen 7: `68898fb51ccb4acfca696609fbddb8b5b2aaac426d572992cb837cb0f3d9dc71`.

Validation completed with RASM 3.2.1, SDCC/SDAS 4.6.2 #16671 and the unchanged
1984 binary (SHA-256
`0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`):

- Both fault providers are rejected at the intended invariants, logs
  `/tmp/geobench-77g-bad-bank.log` and `/tmp/geobench-77g-bad-click.log`.
- The preceding 3D-F service composition still passes all 16 M4 checkpoints,
  log `/tmp/geobench-77g-services.log`.
- Headless openMSX with UNAPI off and private Nextor hard disks passes managed
  kinds/geometry, three-window PAINT focus/movement/cleanup, and Desk/Clock/
  Calculator activation and close/relaunch in Screen 6 and Screen 7. Logs:
  `/tmp/geobench-77g-msx-{kinds,paint,desk6,desk7}.log`.
- Full `make check` passes (exit 0): **176 Python tests without skips**, plus
  native-library, SDK/ABI, layout and distribution checks. Isolated worktree
  `/tmp/geobench-77g-check.uP36nq`, log `/tmp/geobench-77g-make-check.log`.
  The parked untracked `QA/CPC/` directory is excluded from that checkout;
  the retired-target audit itself is unchanged.
- Five new routing unit tests pass, including deterministic native assembly,
  rejected contract drift and corrupted pixel/pointer/focus/bank/guard records.

No additional MSX release-image rebuild is needed. The separately recorded
legacy Notepad-opening failure from [3D-F](CPC-RESTART-STEP3D-F.md) is not fixed
or claimed as passing here.

## Reproduce and remaining work

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-routing-1984
```

Build only: `make diagnostic-cpc-routing` with the same toolchain. M4 card,
image and source-hash manifest: `QA/Diagnostics/CPC-production/routing/`.
Fault variants: `routing-bad-bank` and `routing-bad-click` with
`tools/test_cpc_production_1984.py --variant ...`. Per-checkpoint snapshots and
`routing-checkpoints.json` are written into the runner's private `/tmp` directory.
The parked `QA/CPC/` tree is untouched; there is no Albireo compatibility claim.

Next bounded integration: **public application admission/loading from M4 and
its required filesystem-context binding**, so the shared loop can run a loaded
app instead of native fixtures. Then finish menu/themed graphics and remaining
service bindings, qualify the complete memory/module map and responsiveness,
and advance to the loaded shared-core window, Desktop/File Manager and app
parity gates. Root input routing alone does not close issue #77.
