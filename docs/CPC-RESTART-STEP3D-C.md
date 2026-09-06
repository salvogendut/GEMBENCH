# Step 3D-C: shared focus, stacking and damage on CPC

Date: 2026-09-06. Issue [#77](https://github.com/salvogendut/GEMBENCH/issues/77),
branch `feature/77-cpc-production-adapters`, following 3D-B at `d78f788`.
Parent: [production memory/adapter gate](CPC-RESTART-STEP3D.md).

Status: **this compositor checkpoint passes on M4/1984; the full production
adapter gate remains open.** This is not a Desktop, application loader,
managed-window furniture port or interactive application build.

## What now runs together

`kernel/cpc_window_policy.asm` links the same shared hit-test, focus-click,
focus mapping, raise, z-order, explicit damage, focus damage, move/resize and
repaint routines used by MSX2. Those shared files are unchanged. The CPC
provider binds the existing 25-byte native records, fixed scratch, CPC bank
selection and the already-linked shared visible-region iterator. No alternate
CPC focus, exposure, overlap subtraction or repaint algorithm was introduced.

`lib/cpc/window.asm` supplies physical-screen clipping and software-pointer
lock helpers. The iterator intersects window/damage rectangles, but does not
perform hardware clipping: drawing must additionally bound CPC addresses to
80 byte columns by 200 rows. A screen-edge test caught the fixture's initially
missing hardware clip; the adapter now clamps without modifying the iterator's
active clip or immutable damage sources. All framebuffer raster gaps stay data-free.

CPC's pointer is save-under graphics, unlike an MSX sprite plane. The provider
therefore selects both visible regions **and pointer erase before repaint**.
The shared pass removes it once, holds its paint lock across callbacks,
restores the caller bank/full clip, then samples fresh background and shows
it once. Nested callback hide/show requests honor that lock. This preserves
the shared policy's once-per-pass pointer behavior; it does not claim that
an unrelated damage pass avoids all pointer work.

The private fixture supplies five native surfaces, including legacy and
managed callback paths, sibling C0 records, a C4 record and a completely
covered surface. The menu hooks record the received pointer and bank instead
of drawing a menu. Deterministic border/content callbacks count each write
and honor the hardware clip; they are **not production managed chrome**.
The extra records are ownerless fixtures; only the original root/worker pair
has real owner/page/window identities. This is not multiwindow owner teardown.

After the existing 64 root/non-yielding-worker/M4 rounds, the locked root runs
16 compositor events. Drawing callbacks enable IRQ service while the shared
scheduler lock prevents worker reentry. The final worker counter must equal
its pre-compositor value. Geometry/registration inputs are fixture data, not
mouse events injected into the running machine; the host still starts the
workload using a real emulated Right-key press. No firmware call follows takeover.

## Acceptance and measurements

The independent host oracle assigns each screen byte to the topmost surface
by brute force, rather than reproducing the Z80 band iterator. Each checkpoint
checks all 16,384 framebuffer bytes, including the 384 raster gaps, plus:

- Exact write totals per surface: zero for hidden/disjoint surfaces, exactly
  20 bytes for the 5-column by 4-row explicit damage request.
- No callback for a fully covered surface, and no painting for same-focus or
  outside-window clicks. Moving the covering fixture exposes the hidden one.
- Same-page activation-click consumption, cross-page activation, desktop
  remaining at z-bottom, event/menu handoff and focus mapping.
- The exact two-source focus union, movement envelope, shrink exposure,
  top-only paint, empty damage, and right/bottom screen-edge clipping.
- Once-per-pass pointer save/restore and callback pointer-lock behavior.

One fixture is withdrawn via shared z-remove/focus-top with its old rectangle
damaged. This tests stack removal only: it does **not** call application close,
release an owner, purge messages or close file contexts.

| Section | Measured bytes | Interpretation |
|---|---|---|
| Shared focus/z-order/damage policy | 648 | Fixed high code, inside `8000..C000` |
| Complete high diagnostic payload | 10,311 | Includes unused 3D-B vectors, fixture code, drawing and font; not complete-kernel usage |
| Low owner/page/identity/parameter support | 1,673 / 3,072 | Unchanged |
| Shared context/visibility scheduler | 1,437 / 1,536 | Unchanged |
| Bank/M4/IRQ/raw input | 1,055 / 1,536 | Unchanged |
| Firmware-loaded bootstrap / fixed loader | 4,507 / 170 | Unchanged |

New provider/fixture state occupies the guarded `3200..328F` reservation;
actual provider cells are `3210..321F`, fixture cells `3220..323F`.
The 512-byte event trace is `1E00..1FFF`, within private adapter telemetry.
No new state is in the app aperture, framebuffer or raster gaps. Main/IRQ/
temporary stack observations are 26/4/6 bytes, shared context high-water 26;
these remain workload observations, not maximum application call depths.
Sixteen shared-allocator-owned capture pages leave ten pool pages free. That
is diagnostic capture consumption, not a Desktop RAM requirement.

Final M4/1984 run: **16 pixel checkpoints, 36,384 byte writes, 64 I/O rounds,
581 M4 commands, 1,996 IRQs, including 1,225 inside drawing callbacks**.
Runtime artifacts: `/tmp/geobench-cpc-production-bnkq7u8g`; the committed-image
rerun at `2d4ebe5` also passes in `/tmp/geobench-cpc-production-0u1me3av`
with identical pixel/write/IRQ results (`/tmp/geobench-77c-final-windows.log`).
Final framebuffer SHA-256:
`a081f76273032937e9a28db50a06df7efbf05575809e958234c05d8af0c4436c`.
IRQ counts are timing-dependent, not an input/ACK latency qualification.

Fault injection is rejected at the initial checkpoint: one-byte overdraw at
offset `0110` (`/tmp/geobench-cpc-production-w4uf15pv`), omitted pointer erase
at `01FA` (`/tmp/geobench-cpc-production-_6oeognl`). The broad initial overdraw
experiment exceeded the runner's deadline; the committed injection is bounded
one-byte overdraw and must fail the pixel/state oracle, not merely time out.

All runs boot private FAT16 M4 image copies in unchanged `../1984/1984`,
CPC 6128/512 KiB; no floppy boot, snapshot injection or sibling-repo edits.
The runner also checks linked code, guards, stack balance, returned M4 bytes,
bank/ROM/IFF, owner-page capture metadata, font-page integrity, worker snapshots
and 150 further frames of stable final RAM. Host synthetic observations test
the checker only, not Z80 execution. The adapter unit suite has 15 passing tests.

Full `make check` passed at implementation commit `2d4ebe5` in clean detached
worktree `/tmp/geobench-77c-check.pcgyyX`: **156 Python tests with no skips**,
plus native C, SDK/ABI and distribution checks. Log:
`/tmp/geobench-77c-make-check.log`. Tools: RASM 3.2.1 and explicit SDCC/SDAS
4.6.2 #16671 paths from `../sdcc/bin` through `my-distrobox`.
The earlier production context/M4 and drawing/parameter runtime tests also
pass unchanged (logs `/tmp/geobench-77c-normal-regression.log` and
`/tmp/geobench-77c-drawing-regression.log`; the latter still has 58 cases,
26 pixel checkpoints and 279 drawing-loop IRQs).

Fresh universal APPs retain the recorded reference SHA-256 values:

- ABI Probe: `a6a696cc0bef9caf69c38b6c44f8d8e50dbb7dd560c88e99feb9595993e0adfc`
- Calculator: `5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5`
- Clock: `8d605d045087199769dea40bfdfc50009a2a50bf958ffbcc26e97cdfcdfef2f2`

MSX2/shared production sources and the retained MSX2 release image are
unchanged; no new MSX emulator run was necessary or performed for this
CPC-provider-only checkpoint. The static distribution audit does not boot
floppies. Local `QA/CPC/` was preserved throughout.

## Reproduce

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-windows-1984
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant windows-bad-clip
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant windows-bad-pointer
```

Build only: `make diagnostic-cpc-windows` in the container. Generated media:
`QA/Diagnostics/CPC-production/windows/CARD` and `ADAPTERS.IMG`, with the
section/source/hash manifest beside them. This diagnostic does not replace
or rehabilitate the parked `QA/CPC/` release tree.

## Next gate

Connect the real application lifetime/close path, including deferred-message
purge and filesystem-context cleanup, and measure the resident/module split.
Production registration/managed chrome, root event/mouse translation, public
bindings, timers/FS composition and IRQ-off/M4-ACK responsiveness remain.
Only after that combined adapter/layout gate should a loaded shared-core
window, then Desktop/File Manager, be treated as usable. MSX2 remains the
release target; universal APP bytes, ABI/SDK and MSX production sources are
unchanged. Issue #77 remains open; no merge or CPC release target is enabled.
