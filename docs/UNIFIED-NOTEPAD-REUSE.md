# Unified Notepad live-document reuse — issue #84, sprint 1

Recorded 2026-09-14 on branch `feature/84-live-editor-reuse`. This is the
first of the two forecast follow-up sprints for issue #84. It completes safe
existing-instance TXT/CFG delivery on the normal MSX2 and CPC targets. Live
configuration refresh remains the next sprint; this document does not close
issue #84 or milestone 1.

## Delivered behavior

When File Manager opens TXT or CFG it first prepares the existing copied
filesystem transaction. It then offers `GB_SHELL_OPEN` to the topmost
registered text editor. A live unified Notepad:

- is raised and keeps its existing window, owner, primary page and secondary
  page;
- adopts a new context containing the selected drive, exact 8.3 name and full
  path, with no native pointer crossing the shell or application boundary;
- loads a clean selection through ordinary bounded frames, publishing the new
  identity only after the staged load succeeds;
- presents Save / Discard / Cancel when the current document is dirty. Save
  completes against the old exact context before the new load begins; Discard
  loads the offered context; Cancel releases only the offer and retains the
  old text, dirty bit, identity and context;
- rejects an offer while busy without consuming the producer transaction, so
  File Manager can use its normal new-instance fallback.

If there is no compatible editor, or it rejects the request, File Manager
opens `NOTEPAD.APP` as before. The CPC native File Manager and MSX File Manager
now follow the same prepare → live offer → fallback policy.

## Ownership boundary

The shared filesystem policy accepts a producer-prepared state-1 transaction
for another owner only while all of these facts are true in the resident shell
mailbox: delivery is synchronously busy, message type is `GB_MSG_SHELL`, and
request `p0` is `GB_SHELL_OPEN`. The shell has already raised/mapped the chosen
recipient, so the filesystem request captures that recipient's current owner.
No queued path or raw context pointer is introduced.

Authorization does not rewrite the pending record before allocation. A full
four-context table therefore returns `FULL` with the producer transaction
unchanged; a later fallback or error path is not left with a stranded context
bound to the wrong owner. Success allocates for the mapped recipient and then
consumes the transaction exactly once.

## Preserved limits and identity

- `NOTEPAD.APP`: **20,368 bytes**, SHA-256
  `38b1e574dbbfe3a374981334a38860bbf66fe100d8e5b32c19b12b544e904b0e`.
- Primary/secondary stored segments: **14,425 + 5,943 bytes**.
- Primary code/initialization ends at `0x7858`; DATA remains `0x7870`.
- Secondary model state still ends below `0x7E27`; task limit remains `0x7F00`.
- Editable document capacity remains **4096 bytes**, with an independent
  **4096-byte transactional staging area** and the existing stack reserve.
- The same APP bytes are present in both normal CARD trees.
- Screen-7 `GBMSX.COM` remains **16,104 / 16,128 bytes**; its 24-byte limit
  margin was not spent. CPC high kernel remains **16,185 / 16,384 bytes**.

To fit without relaxing a limit, pointer pixel-to-text mapping moved into the
already-owned portable secondary computation core (`NP_POINT`). This keeps
the calculation identical across renderers and reduced primary controller
code. Duplicate primary literals were also consolidated. No editor feature or
buffer was removed.

Normal image hashes for this checkpoint:

- MSX2 `QA/MSX/GBMSX.IMG`:
  `5c2006ad1d0e4f9a7d8bf354e23765b43f04f38be504e27a9b4b8ce8ab154101`.
- CPC M4 `QA/CPC-Desktop/GEOBENCH.IMG`:
  `e9a7d67b68a9c7739281dceb19a594f0c62d9b7263a5bd53da1fa07918b90292`.

## Acceptance evidence

- Host controller/policy: 16 focused Python/C tests pass. They exercise clean
  reuse, dirty Save/Discard/Cancel, busy rejection, identity failure, exact
  owner/context cleanup, authenticated state-1 adoption and a full context
  table with an unchanged pending transaction.
- Native File Manager host and CPC link gates pass; the CPC File Manager uses
  13,632 / 14,336 code bytes in its admitted allocation.
- `make geobench-msx` and `make cpc` build and validate the normal images.
- 1983 normal-image reuse passes Screen 6 (47 checks) and Screen 7 (53 checks):
  root and nested `EXACT.TXT` are opened through File Manager in the same
  Notepad window, saved by exact path, and all pages, seals and contexts are
  reclaimed.
- 1984/M4 passes the prior handoff regression plus clean reuse and dirty reuse.
  The dirty run verifies a real second launch prompt, Cancel retaining the old
  dirty document, a repeated launch, Discard loading the nested document, a
  constant three-window count and final cleanup. CPC testing uses M4 only.
- Native openMSX 21.0 in `my-distrobox` passes the independent Screen-7
  universal editor workflow: 286 parameter/restoration checks, real keyboard
  editing/navigation, chooser save/reopen, dirty Quit and cleanup. The host
  Flatpak frontend failed before emulation with “Unable to allocate instance
  id”; that frontend failure is not counted as application evidence.

The runtime drivers now have explicit `reuse` / `reuse-dirty` scenarios and
wait for the new document's exact length rather than accepting the old idle
editor state before synchronous delivery has been processed.

## Manual check

MSX2:

```sh
MSX_UNAPI=0 tools/run_msx.sh QA/MSX/GBMSX.IMG
```

CPC, using the normal M4 image:

```sh
bash tools/run_cpc.sh
```

Open File Manager, open one TXT file, return focus to File Manager without
closing Notepad, and open another TXT/CFG. Window count must not increase and
the original Notepad must come to the front. Repeat after editing the first
document and check Save, Discard and Cancel separately. Use disposable image
copies for write tests; generated images are replaced by rebuilds.
