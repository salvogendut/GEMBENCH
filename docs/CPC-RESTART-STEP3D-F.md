# Step 3D-F: shared deferred messages and timer collection on CPC

Date: 2026-09-06. Issue [#77](https://github.com/salvogendut/GEMBENCH/issues/77),
branch `feature/77-cpc-production-adapters`. Follows
[3D-E](CPC-RESTART-STEP3D-E.md); the two checkpoints are committed together.

Status: **16 service checkpoints pass on M4/1984**. The production adapter
gate remains open. This is not a release CPC kernel, public APP loader,
interactive window manager or Desktop. The fixture supplies native root/worker
records, callbacks, service identities and a scripted root-turn driver.
Deferred policy, timer publication/collection, registration, stacking,
visibility and damage composition are the same implementation used on MSX.

## Composition and contracts

`cpc_services.asm` links the existing shared deferred API and one-head dispatcher.
The queue and purge units are already linked through lifetime support. Newly
extracted `service_lookup.asm` and `root_dispatch_phase.asm` are included by
both targets. The latter is exactly three calls: dispatch one message, map the
resulting focus, reset clip. It is the **post-input phase**, not the full WM loop.
MSX retains the original instruction bytes, layout and public ABI.

CPC maps receiver callbacks through the existing C0/C4 app-bank adapter. Root
mutations require `SCHED_CURRENT=0`; callback pointers and complete six-byte
send records must fit `4000..7EFF`, below the `7F00` snapshot. There is no CPC
fixed-TPA or public jump-table binding yet. Send validation precedes capacity
checks. Lookup walks live z-order and resolves generation-tagged owner service
classes/accessory identities, not an independent CPC registry.

The root-owned app page contains the **unmodified SDAS timer collector**, linked
at `4C00` (116 bytes), not a translated kernel copy. A symbol pass establishes
fixed hook addresses; SDAS/SDCC links the shared source, then RASM incorporates
that payload. All addresses must match between passes before media is emitted.
The eventual Desktop will link this collector normally, as MSX does.

An actual IRQ-preempted C4 worker publishes through shared `GB_PARAMS` op 3.
The first rectangle is immutable while pending; a second publish returns busy.
Workers never render. The root maps its app page and calls the collector after
the shared dispatch phase, standing in for Desktop's bar hook. Real lifecycle
cleanup closes the added covering window at the end.

Retained MSX limits, not new guarantees:

- Eight FIFO records and one head per root turn; handlers can reply but cannot
  recursively dispatch. Delivery validates the receiver, not sender liveness
  independently of teardown purge. Callback self-destruction/slot reuse is not
  newly guaranteed safe; activation retains its pre-callback primary-slot rule.
- One timer mailbox, not a per-window queue. Hidden components are acknowledged
  without paint; stale generation and fullscreen requests are consumed without
  that acknowledgement. A partially visible damage rectangle can also invoke
  the covering window's callback in its intersecting area, matching MSX policy.
- A rejected hidden component can leave the native clip at its damage rectangle
  until the next root phase resets it. This is observed and checked, not hidden
  by a CPC-only fixup. When integrating the bar/input loop, ensure subsequent
  UI drawing establishes its intended clip; assess any correction on both targets.

## Runtime coverage

The private M4 image boots normally; snapshots are observations, never injected
boot state. After 64 keyboard/IRQ/worker/M4 rounds, sixteen captures cover:

1. Initial mixed-kind managed windows and owner/accessory lookup.
2. Eight-record saturation; malformed, stale, absent and terminating receiver
   admission precedence. Exact app-aperture boundary and worker-context rejection.
3. One-head delivery to C4, a reply appended after queued messages, and stable
   current-record access despite an attempted recursive dispatch.
4. Delivery to C0, sender-only cancellation, remaining FIFO order and endpoint
   unregister purge in both directions.
5. Handler-requested activation of the receiver's primary window, then focus
   bank remapping by the shared root phase.
6. Six real worker timer publications: visible, partial, hidden component,
   completely hidden window, stale window generation and fullscreen suppression.
7. A completely covered worker receives four scheduler opportunities without
   changing its compute counter or consuming another queued request.
8. Receiver generation change, terminating state, absent endpoint and absent
   code page between send/delivery all drop without callbacks. A windowless
   endpoint still receives its message but cannot activate. These invalidations
   are explicit fixture inputs, not a second owner-close/reallocation test.
9. Endpoint unregister and real shared close of the covering sibling.

The host independently models FIFO state and per-pixel topmost ownership. It
checks all sixteen 16-KiB framebuffers including raster gaps, delivery records
and mapped bank/root/lock, endpoint and owner tables, geometry/z-order,
publication/busy results, stable current record, callback visibility, pointer
pass counts, occluded acknowledgements and page accounting. The common runner
also checks M4 bytes/commands, bank/ROM/IFF, code/font integrity, guarded stacks
and state, scheduler faults and 150 additional frames of unchanged final RAM.
Service snapshots permit even 24..64-byte live contexts because actual nested
root yields differ from the older flat fixture; prior variants retain their
exact 24/26-byte check. Stack guards remain mandatory.

Fault providers deliberately discard delivery or falsely report hidden damage
as visible. Both are rejected at their corresponding semantic checkpoint, not
accepted because of a timeout. Host mutation tests additionally reject corrupted
FIFO/current-busy state, delivery bank/context, worker status, hidden drawing/
pointer activity, generations, lookup, collector code, font and state guards.

## Measurements and evidence

| Section | Bytes |
|---|---:|
| Shared deferred API/dispatch, lookup and root phase | 606 |
| App-linked timer collector | 116 |
| Complete high diagnostic payload, including fixtures/older vectors/font | 14,580 / 16,384 |
| Low support / scheduler / hardware | 1,673 / 1,437 / 1,055 (unchanged) |
| Shared focus/damage / lifetime / registration-chrome | 648 / 851 / 783 (unchanged) |

The diagnostic payload size is **not whole-kernel usage**. Service scratch and
trace metadata occupy existing guarded low-RAM reservations; nothing is placed
in framebuffer gaps. One owner page stores sixteen 1-KiB state records and
sixteen more store framebuffer captures, leaving nine free pages. This capture
overhead is not desktop RAM consumption.

Positive run: `/tmp/geobench-cpc-production-ul4t3zt1`, log
`/tmp/geobench-77f-services.log`. Five deliveries in fifteen root service turns,
six worker publications, 713 M4 commands, 2,340 IRQs, measured main/IRQ/temporary
stack use 32/4/6 bytes and context high-water 32. These are workload observations,
not maximum stack/IRQ-off/latency bounds.

- Image SHA-256: `4cf3cce15f16a0585c19e82cd0abd35f3ff152291460f457d1393d49e3af59b2`.
- Final framebuffer: `e92acc36545b267c39ef587dba2324ff7a930d3041b245747c2c1caebd600d70`.
- Fault logs: `/tmp/geobench-77f-bad-delivery.log`, `/tmp/geobench-77f-bad-visible.log`.
- Emulator: unchanged `../1984/1984`, SHA-256
  `0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`.

No floppy boots, emulator changes, parked `QA/CPC/` changes, or Albireo claim.

Both MSX kernels reassemble byte-identically to the runtime-tested 3D-E images:
Screen 6 SHA-256 `1f8f5d37e3350a1c07a8e17df947fa95a62dc97d0c78dfad6bb6eaeddeb4d59f`,
Screen 7 `68898fb51ccb4acfca696609fbddb8b5b2aaac426d572992cb837cb0f3d9dc71`.
No additional release-image rebuild is needed for this checkpoint. The openMSX
native covered-Clock regression passes (`/tmp/geobench-77f-msx-timer.log`),
including stable covered pixels, zero hidden work and restored exposed damage.
The dedicated SYSINFO deferred-API/lifetime regression also passes
(`/tmp/geobench-77f-msx-defer.log`): complete deferred test mask, purge at close,
generation-safe owner reuse and final 22 free pages/two live owners/windows.

Full `make check` passes (exit 0) in isolated worktree
`/tmp/geobench-77f-check.TetADX`: **171 Python tests without skips**, plus native
libraries, SDK/ABI, layout and distribution checks. Log
`/tmp/geobench-77f-make-check.log`. This excludes the user's parked untracked
`QA/CPC/`, not by weakening the retired-target audit. Five new service tests
also pass independently (`/tmp/geobench-77f-unit.log`), including deterministic
SDAS/RASM composition and host-checker mutations. The preceding 3D-E M4
registration/chrome runtime still passes (`/tmp/geobench-77f-registration.log`).

An additional legacy shell-service test fails to open its first A.TXT in
Notepad, before any register/find/send/delivery hits
(`/tmp/geobench-77f-msx-shell.log`). Its cause is not diagnosed here; it must not
be reported as a pass. This checkpoint emits no changed MSX kernel/app bytes.

## Reproduce and next checkpoint

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-services-1984
```

Build only: `make diagnostic-cpc-services` with the same tools. Card, M4 image
and source-hash manifest: `QA/Diagnostics/CPC-production/services/`.
Fault variants: `tools/test_cpc_production_1984.py --variant services-bad-delivery`
and `--variant services-bad-visible`. Toolchain: RASM 3.2.1 and SDCC/SDAS
4.6.2 #16671. Emulator output and the state/pixel oracle are diagnostic tests,
not a manual application demonstration.

Follow-up [3D-G](CPC-RESTART-STEP3D-G.md) integrates shared input/root-loop
routing with CPC keyboard/pointer adapters, preserving the MSX focus/gesture/
menu handoffs. Remaining: public
APP admission/loading, menu/themed graphics, file-context/backend and remaining
service bindings, and qualify the complete map, stacks and responsiveness.
The loaded shared-core window, Desktop and application-parity gates remain
ahead. This checkpoint does not close #77 or enable the parked CPC target.
