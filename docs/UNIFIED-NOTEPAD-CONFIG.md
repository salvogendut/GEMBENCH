# Unified Notepad live configuration publication — issue #84, sprint 2

Recorded 2026-09-14 on branch `feature/84-live-config-refresh`. This is the
second issue #84 follow-up sprint. It lets the compile-once Notepad update the
resident raw configuration cache after saving a file with the exact
`GEOBENCH.CFG` 8.3 identity,
without introducing a target pointer, parser or repaint dependency.

## Delivered contract

ABI 2.1 shell operation 5 accepts a caller-primary pointer and a length from
0 through 512. During a root callback, the kernel validates the complete span,
copies it synchronously to the resident raw configuration cache, then publishes
the new length. It retains no pointer. Invalid lengths or spans leave both the
previous bytes and length unchanged; worker, nested-delivery and older receiver
paths reject the request.

The operation deliberately does not parse the text, reload assets, repaint,
change focus or alter application state. This matches the native Notepad's safe
behavior: a successfully saved configuration becomes the authoritative raw
cache for later consumers, while the running desktop remains visually and
structurally stable. Settings or a later explicit apply/reload operation owns
any live appearance change.

Unified Notepad publishes only after a successful save when all of these are
true:

- the adopted or selected 8.3 identity is exactly `GEOBENCH.CFG`;
- the saved document is no larger than 512 bytes;
- the secondary model exports the same bytes which were written to storage.

An ordinary `.CFG`, a larger document, a failed save or a rejected shell call
does not replace the resident cache. Publication does not disturb the document,
cursor, selection, scroll position or normal post-save clean state. The
independent 4096-byte document and 4096-byte staging buffers remain unchanged.

## Target bindings

The shared policy is in `kernel/core/config_publish.asm`; both MSX and CPC
shell receivers include it with target-owned cache addresses. CPC now keeps a
dedicated raw-cache length at `CPC_CFG_LENGTH`, separate from the parser output
scratch previously exposed as `KCFG_LEN`. Native CPC Settings therefore reads
the exact current raw length and remains compatible with publication by a
universal app.

Applications opt into the compact `gb_config_publish` SDK binding explicitly
with `UNIVERSAL_CONFIG=1`; Notepad is the first consumer. The public behavior
and operation number are recorded in `abi/geobench-v2.json`.

## Preserved limits and identity

- `NOTEPAD.APP`: **20,521 bytes**, SHA-256
  `fae9ad2f6da69b906af13836f7230095d2ca8421211a8f80a79e310813f933b7`.
- Primary/secondary stored segments: **14,421 + 6,100 bytes**.
- Primary code ends at `0x7832`; DATA remains at `0x7870`, leaving 62 bytes.
- Secondary image ends at `0x57D4`; its task limit remains `0x7F00`.
- Screen-7 `GBMSX.COM` remains **16,104 / 16,128 bytes**.
- CPC high core is **16,272 / 16,384 bytes** and support is
  **3,035 / 3,072 bytes**.
- The same APP bytes are staged in the MSX and CPC normal CARD trees.

Candidate image hashes for this branch are:

- MSX2 `QA/MSX/GBMSX.IMG`:
  `4ca22c4ad000be4db921bcb596e90088ddd77114b4802c10859db5664cf3dc58`;
- CPC M4 `QA/CPC-Desktop/GEOBENCH.IMG`:
  `e166fc0c176f3d475cb953d810c6129748aa1834b2c8b176d9fba9de66ffc5ef`.

## Acceptance evidence

- The real-Z80 publication fixture passes exact 0, 1, 511 and 512-byte copies,
  source-bound failures and unchanged-cache failure semantics. It caught and
  fixed both the zero-length `LDIR` wrap and the original 256–511-byte bound.
- Unified Notepad host tests cover exact identity, ordinary CFG, over-limit and
  rejected-service cases while checking cursor, selection and dirty semantics.
- The focused host/link suite passes 18 tests plus all shell adapter contracts;
  CPC Settings still passes its owned-context and verified-publication gate.
- `make msx` and `make cpc` pass and validate the candidate normal images.
- 1983 passes the real Desktop → File Manager → `GEOBENCH.CFG` edit/save flow
  in Screen 6 and Screen 7, 24 checks each. It verifies exact disk bytes,
  resident cache bytes/length, and complete page/seal/context cleanup.
- 1984 passes the equivalent normal CPC Desktop workflow from a disposable M4
  image: configuration published, file read back and clean desktop restored.
  CPC qualification uses M4, not floppy media.
- openMSX 21.0 in `my-distrobox` independently passes the Screen-7 editor
  regression with 282 parameter/restoration checks and exact saved bytes.

Passing final runtime artifacts are under
`build/notepad-84/sprint2-config-1983-{6,7}-final`,
`build/notepad-84/sprint2-openmsx-7-final`, and
`build/cpc-delivery-runtime/geobench-cpc-runtime-ybvayjxv`.

## Manual check

On MSX, use a disposable image copy, create or copy a `GEOBENCH.CFG`, then
open it through File Manager, edit and save it:

```sh
MSX_UNAPI=0 tools/run_msx.sh QA/MSX/GBMSX.IMG
```

On CPC, use the normal M4 image:

```sh
bash tools/run_cpc.sh
```

The save must complete normally with no focus jump, global repaint or content
loss. Reopening the file must show the saved bytes. A later Settings launch
must read the current raw cache. Rebuilds replace generated media, so use copies
for destructive or fault-injection checks.
