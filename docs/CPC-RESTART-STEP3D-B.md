# Step 3D-B: shared parameters and CPC drawing integration

Date: 2026-09-06. Issue [#77](https://github.com/salvogendut/GEMBENCH/issues/77);
branch `feature/77-cpc-production-adapters`, following 3D-A at `39d135c`.
Parent: [production memory/adapter gate](CPC-RESTART-STEP3D.md).

Status: this drawing/parameter checkpoint is implemented and validated from
M4 in 1984. **The complete production-adapter gate remains open.** No CPC
desktop, public APP loader, full window-manager port or release capability
is enabled by the private diagnostic.

## Shared code, CPC hardware

`kernel/cpc_support.asm` binds and links the existing shared page-count,
owner identity, page allocation, code-page binding, window identity,
owner-context and receiving-side `GB_PARAMS` units. There is no second owner
table policy, parameter validator, timer publication queue or window-handle
validator. The same pending/mapped/focus owner resolution and primary-page
check run here as on MSX2. Generation/alive/owner checks use the real shared
`window_validate_owned`; the private fixture supplies synthetic native
records, not a substitute WM or a success-only stub.

The fixed low support section is copied during M4 takeover before the high
core overwrites firmware workspace. Shared parameters serialize IX/IFF and
scheduler lock before reading caller memory, then restore them on every
return. Descriptor/text spans and codes remain the frozen ABI 2.1 contract.
The test calls the linked receiver directly; it does not install an incomplete
public jump table or advertise that universal APPs can already launch on CPC.

The CPC-only drawing adapters provide:

- Mode-1 line pixels in all octants, inclusive endpoints, bounded to 320x200
  and the current byte-column/scanline clip. CPC needs a software line loop
  because it does not have the MSX2 VDP line-command engine.
- The archived CPC `lib/text.asm` renderer from `56478578`, with explicit
  low-state bindings, bounded font indices and exact byte/row clipping.
  Whole-glyph culling alone would not protect partially visible glyphs.
  The current diagnostic loads the repository-generated 6x8 stock font.
- The previously proved rectangle fill, canonical save/restore and four-phase
  software pointer. Their private 16-byte primitive gate now has one source
  in `lib/cpc/graphics_gate.asm`; the 3B foundation path is an include wrapper.
  This private gate is not a new public rectangle ABI.
- Pointer exclusion only when clipped damage intersects its saved rectangle;
  restoration samples the newly drawn content. Duplicate show/hide, unrelated
  damage and right/bottom edges retain the existing proved behavior. Line
  exclusion uses conservative clipped bounds, not an exact per-pixel hit mask.

Text data is copied by the shared receiver before F7 replaces the caller
aperture for font access. Rendering restores the original bank before return.
The text and line loops allow interrupts while the shared scheduler lock
prevents task reentry. Native rectangle/pointer requests and M4 transport
retain their earlier request-wide DI; this is **not** an overall latency pass.

## Measured layout

The major allocations from 3D-A are unchanged. Added indexed architecture
tables retain their existing relationships within `2000..2900`; all bindings
are explicit CPC providers, outside the complete framebuffer page.

| Section | Measured bytes | Allocation / interpretation |
|---|---|---|
| Shared context/visibility scheduler | 1,437 | `2900..2F00`, unchanged 1,536-byte budget |
| Bank/M4/IRQ/raw input leaves | 1,055 | `3800..3E00`, unchanged 1,536-byte budget |
| Shared owner/page/window identity/parameters | 1,673 | `0400..1000`, 3,072-byte budget; includes 65 bytes of receiver scratch |
| CPC drawing code/tables | 2,144 | Inside the high `8000..C000` slot |
| Complete diagnostic high payload | 8,766 | Includes drawing code, private orchestration/vectors and the 816-byte font; **not complete-kernel usage** |
| Firmware-loaded bootstrap | 4,507 | Ends below `9A00`; now embeds the low support payload |
| Fixed M4 core loader | 170 | `0100..0400`, unchanged |

Drawing state lives at `3010..308D`, with 16-byte guards on both sides.
The private trace reservation is `3100..31FF`. Text/graphics scratch is not
left at the archived `14BC` addresses and does not occupy raster gaps.
The shared receiver's inline 16-byte request and 49-byte text copy are the
only mutable bytes exempted from the low-support code-integrity comparison.
No font or runtime scratch is hidden in the high framebuffer page.

Observed main/IRQ/temporary stack use is **32 / 4 / 6 bytes**. Shared context
snapshot high-water is 26 bytes, as before. These are workload measurements,
not maximum application/service/WM call-depth guarantees.

The fixture now uses the actual shared allocator: root gets C0, worker gets
C4, and 26 owned temporary pages hold framebuffer checkpoints. All 28 admitted
pool pages are consequently allocated at completion; **zero free pages here
reflects test captures, not desktop memory consumption**. F7 is excluded from
that pool and holds the stock font plus a checked sentinel remainder. Metadata
for every allocated page, generation, purpose and owner is checked.

## Execution evidence

1984 runs from a private 32-MiB FAT16 M4 image, CPC 6128 / 512 KiB. No floppy
or snapshot injection is used; snapshots only observe state. Unchanged runner:
`../1984/1984`, SHA-256
`0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`.
Assembler: RASM 3.2.1 through `my-distrobox`.

The positive workload combines 64 root/non-yielding-worker rounds and 64
real M4 reads with **58 drawing/parameter cases and 26 exact framebuffer
checkpoints**. Coverage includes every line octant, horizontal/vertical/point
lines, empty clips, partially clipped glyphs, bottom/right clipping, 48-byte
strings, NUL termination, out-of-font codes, all pointer phases, canonical
block restoration, invalid spans/length/version/pen, primary/owner context
failures, and timer publish/busy/query/stale/owner/cancel results. A call from
the actual mapped worker is rejected with context status 2 and draws nothing.

The host compares every captured byte, including all 384 raster-gap bytes.
It also checks code, bank/ROM/mode, entry/return IFF, IX, shared lock and
identity state, snapshots, stack guards, M4 returned bytes and the entire F7
font/sentinel page. Final RAM must remain stable for another 150 emulated
frames after completion.

| Case | Result | Artifact directory under `/tmp/` |
|---|---|---|
| Drawing | PASS: 58 cases / 26 pixel checkpoints, 533 M4 commands, 1,085 IRQs | `geobench-cpc-production-q224rqaj` |
| Bypass drawing clip | Rejected at `clipped-line`, offset `00A2` | `geobench-cpc-production-on10nhor` |
| Read text from replaced caller page | Rejected at `text-under-pointer`, offset `019A` | `geobench-cpc-production-obfsbxzp` |

There were **279 IRQs sampled inside interrupt-enabled drawing loops**, and
eight pointer saves/restores. This demonstrates interrupt service during
drawing, not a bound on input latency, interrupt-off duration or M4 ACK waits.
The final framebuffer SHA-256 is
`c5d29635d7c47978621a71f86a2ebe36fe09c3da42d9b3d9a499f289c3cad836`.
IRQ totals vary with workload/emulator timing; exact pixel/state checks do not.

Earlier normal/full-slot/bad-guard/bad-bank/128-KiB production tests all pass.
The standalone 3B graphics suite also passes, with its original raw payload
SHA-256 `e722d7b4235241717e6d6124c51b62a1cf19684389d982abe589907b0ed2232e`:
2,450 requests, 24 pixel checkpoints, 1,753 IRQs; artifacts
`/tmp/geobench-cpc-foundation-1ulx8q9v`.

Four new host tests cover shared composition, exact clipping/gap oracles,
deterministic linked profiles/budgets and corrupted-pixel/code/metadata
observations. Synthetic observations test the checker only; execution evidence
comes from the real M4 runs above.

## Reproduction

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-drawing-1984
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant drawing-bad-clip
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant drawing-bad-copy
```

Build only: `make diagnostic-cpc-drawing` inside the container. Media is staged
under `QA/Diagnostics/CPC-production/drawing/CARD` with `ADAPTERS.IMG` and a
source/section/hash manifest beside it. The runner uses a private image copy
and prints the retained capture/log/result directory. This is an automated
diagnostic, not an interactive Desktop/Clock/Calculator build.

## Still required before the first shared-core window

Connect and measure the remaining shared lifecycle/close, focus/z-order,
damage/repaint, deferred/timer-consumer and FS/provider code in the complete
CPC kernel/module layout. The linked identity subset is not full application
lifetime or teardown. Root input/event translation, mouse-device handling,
time-of-day policy, public drawing/storage bindings and responsive I/O also
remain; no IRQ-enabled M4 transport or broad smoothness guarantee was added.

Then validate the complete map and combined maximum stack/latency behavior
before advancing to the first window with the shared WM. Do not treat the
diagnostic's high-slot space as proven complete-kernel headroom. MSX2 remains
the release target; ABI/SDK/universal APPs are unchanged. `QA/CPC/` is preserved,
PCW/Albireo are not implemented here, and issue #77 remains open.
