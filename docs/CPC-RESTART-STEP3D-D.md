# Step 3D-D: application lifetime and owner cleanup on CPC

Date: 2026-09-06. Issue [#77](https://github.com/salvogendut/GEMBENCH/issues/77),
branch `feature/77-cpc-production-adapters`, following 3D-C at `3d4c252`.
Parent: [production adapter gate](CPC-RESTART-STEP3D.md).

Status: the lifetime/cleanup checkpoint passes on M4/1984. **The complete
production-adapter gate remains open.** Native records, chrome/menu callbacks,
queue contents and logical filesystem records are still diagnostic fixtures,
not a public CPC application loader, desktop or filesystem-context service.

## Shared implementation

`kernel/cpc_lifetime.asm` includes the existing application dispatcher,
window-close orchestration, owner reclamation, FIFO compaction/purge and
filesystem-context cleanup units. The CPC provider binds fixed state and
the existing CPC bank/focus/damage adapters. It does not implement a second
application lifetime, page release or cleanup algorithm.

Close keeps the existing order: establish damage, remove the window's worker
contribution, mark it dead, remove it from z-order, detach its identity, select
and map focus, restore the caller bank, release the owner if no windows remain,
and repaint. One surviving sibling retains its application and all pages.
Owner teardown purges messages by exact sender/receiver owner generation,
invalidates matching logical file contexts, frees owned pages, and resets the
application record. Windowless publication/quit and explicit multiwindow quit
use the same code paths as MSX2.

Filesystem cleanup is intentionally storage-free: native handles do not survive
a bounded operation. The fixture seeds four full 144-byte context records;
it does not claim that the CPC FSCTX allocation/read/write/directory provider
exists. Deferred queue data are seeded too: delivery, endpoint registration and
service lookup are not linked by this checkpoint. Native drag is explicitly
unsupported in this private link, returning status 1 rather than fake success.

## Shared stale-close bug found by the checkpoint

Repeated close of an already-dead window exposed a real shared-code defect.
`window_validate_owned` returns its status in A, without promising flags.
Its dead-window path can return `A=2` while Z remains set. The caller used
`RET NZ` directly and consequently continued into close: live count decreased
again, and the legacy raw-page path could free a newly reused page.

The correction is one shared `OR A` before `RET NZ` in `kapp_window_close`.
Both CPC and MSX therefore use the same status check. No ABI or application
binary change is needed. The earlier byte-identical MSX claims in 3D-A/B/C
remain historical; this checkpoint deliberately changes the shared kernel.
The independent low/high-state assembly test checks the `OR A; RET NZ` bytes.

Before the fix, the M4 repeated-close case returned success and reduced the
two surviving windows to one (`/tmp/geobench-cpc-production-mlvwg81m`). After
the fix, it returns stale status 2 without changing windows, pages or pixels.
The fixture also rejects stale handles after window-slot and owner-ID reuse.

## Memory and execution evidence

| Section | Measured bytes / allocation |
|---|---|
| Added shared lifetime/cleanup units | 851, in fixed high memory |
| Complete diagnostic high payload | 12,686 / 16,384, including fixtures, unused older vectors and font; **not complete-kernel usage** |
| Shared focus/damage policy | 648, unchanged |
| Low support / scheduler / hardware | 1,673 / 1,437 / 1,055, unchanged |
| Logical FS records | `2600..283F`: four records × 144 bytes |
| Deferred FIFO and scratch | existing indexed layout `2376..23C9`, before timer state |
| New guarded fixture state | `3290..32FF`, outside WM/drawing state and stacks |

The future launch/service reservation `2840..28FF` is checked unchanged. Two
root-owned temporary pages hold sixteen 2-KiB state observations; sixteen more
hold complete framebuffers. Captures use the actual allocator and record their
native tags; reclaimed pages can be reused without assuming contiguous capture
storage. Eight pool pages remain free at completion. This is diagnostic
capture consumption, not the RAM requirement of a desktop.

The 16 checkpoints cover root quit denial, foreign-window and generation
rejection, sibling close, last-window cleanup, repeated close, owner/slot reuse,
windowless publication/quit, explicit two-window quit and unsupported drag.
Four generations of owner slot 3 are exercised. A managed pane is task-enabled
through real shared startup; close removes its runnable contribution while the
original worker survives. All work is serialized on the root task; drawing
allows IRQs under the shared lock. Neither the original worker counter nor
its snapshot may change during the lifetime workload.

The independent host model checks status/mapping/focus/runnable state, all page
metadata, owner/window generations and links, sibling counts, code bindings,
application/service/accessory/endpoint reset, exact FIFO order, all 576 context
bytes and their preserved generations/tails, framebuffer damage/exposure and
pointer locking. Linked code, guards, final tables, font page, M4 bytes and
150 extra frames of stable RAM are also checked. Synthetic unit observations
test the checker; actual execution evidence comes from M4 boot, not injected
snapshots or fake storage responses.

Final guarded M4 run: `/tmp/geobench-cpc-production-xs5bslg4`, log
`/tmp/geobench-77d-final-lifetime.log`: 16 checkpoints, 64 root/worker/I/O
rounds, 657 M4 commands, 2,804 IRQs, main/IRQ/temporary stack use 26/4/6 bytes,
context high-water 26. These are workload measurements, not worst-case latency
or stack bounds. Framebuffer SHA-256:
`426de03c64f0a4d957e897a9daadd07b491cd473c39c10b74eca8daa7cfa2e26`.
Fault variants must be rejected at last-window cleanup for surviving messages
or file contexts. The adapter host suite contains 18 passing tests.

## Reproduce and remaining work

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-lifetime-1984
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant lifetime-bad-purge
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant lifetime-bad-fsctx
```

Build only: `make diagnostic-cpc-lifetime` in the container. Generated M4 card,
image and manifest are under `QA/Diagnostics/CPC-production/lifetime/`.
No floppy boot or edits to the parked `QA/CPC/` or sibling repositories.

Next: production window registration/managed chrome, remaining deferred/timer/
FS service composition and public/input bindings, then full resident/module/
state/stack/IRQ-off/M4-ACK qualification. The storage-free cleanup link is not
a complete FS adapter or full-kernel fit proof. Only after these gates should
a loaded shared-core window, then Desktop integration, be considered usable.
