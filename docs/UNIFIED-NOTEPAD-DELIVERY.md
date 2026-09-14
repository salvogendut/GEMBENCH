# Unified Notepad: acceptance and normal delivery

2026-09-14, issue #84, branch `feature/84-unified-notepad`, baseline `33ba155`.
The user approved completing all three steps in order, not just planning them.

1. **Complete — CPC Escape.** Text windows reserve Escape for POLL's one-shot
   close/cancel event; GETKEY cannot consume or duplicate it. Verify long holds, rearming, dirty Cancel and that a
   closing editor cannot pass the held key to the window underneath it.
2. **Complete — private acceptance.** Real CPC/M4 4096-byte round trip, 4097-byte
   rejection, chooser, clipboard, dirty save/cancel/discard, clipped repaint,
   storage faults and repeated owner/page/context cleanup. Retain MSX Screen
   6/7 regressions in openMSX and 1983; use no floppy tests or guest RAM patches.
3. **Complete — normal distribution integration.** Back up current MSX/CPC
   generated media first. Build and stage one identical universal Notepad APP,
   its required receiver/services, and document associations on both targets;
   verify normal Desk/File Manager launches, existing desktop apps, media
   manifests and saved-file readback. No promotion before the acceptance gate.

Keep the 4096-byte editor and independent staging, memory/stack limits, shared
ABI and private historical test images. No sibling repository changes or new
architecture is included. Record each step's evidence
and remaining issues here before declaring the delivery complete.

Publication follow-up, 2026-09-14: the user requested committing/pushing this
checkpoint, opening/merging its PR, and updating the v1.0 roadmap and acceptance
ledger. This published the completed editor delivery; at this historical
checkpoint issue #84 remained open for safe live-editor reuse and document
integration acceptance.

Subsequent issue #84 sprint 1 implements that safe live-document reuse. Its
new APP identity, normal-image hashes, owner transaction, dirty-decision and
emulator evidence are recorded separately in
[UNIFIED-NOTEPAD-REUSE.md](UNIFIED-NOTEPAD-REUSE.md). Exact sizes and hashes
below remain the historical delivery checkpoint, not the later reuse artifact.

Final status, 2026-09-14: issue #84's later reuse, configuration and closure
sprints are complete. The [closure record](UNIFIED-NOTEPAD-CLOSURE.md) adds the
real BASIC CRLF and portable CPC dotted-path evidence that completes milestone
1. Statements below about outstanding work describe this earlier delivery
checkpoint and are retained as historical provenance.

## Preserved baseline

Before building, copied normal `QA/MSX`, `QA/CPC-Desktop`, and the preceding
private receiver media/work to `build/notepad-84/pre-delivery-R2ZDyU/`.
All older manual editor images are untouched. Baseline normal-image hashes:

- MSX: `047a19d38e05f009df8c07a22be90e226a98bc68992fc7474c34015f251ce308`.
- CPC: `c1b09dbc08299b217443d2a06d66f8688ba0e7cf50be0a2a41e2a7475cf94b14`.

## Input and private acceptance evidence

The unchanged File > Quit APP remains 20213 bytes, SHA-256
`d45f0c5ec151f1a5ca4f9a9a52ff94162360f1aa2883eda4afa80340396ad157`.
The physical Escape latch occupies the boot-cleared routing byte `3308`.
Only the document receiver enables the new path. Non-text GETKEY retains ASCII
Escape; native/cooperative comparison profiles keep their preceding input code.

- `build/notepad-84/evidence/delivery-escape-unit.log`: 5 tests, 2017 executed
  Z80 calls: bank/IFF/register preservation, text/pointer routing, holds,
  release/re-press, focus changes and GETKEY-before-POLL ordering.
- `delivery-escape-1984.log`: real clean close, dirty close and Cancel held for
  150 emulated frames each; no re-open or close of the underlying File Manager.
- `delivery-handoff-1984.log`: launch/edit/navigation/save/nested path cleanup.
- `delivery-boundary-1984-r2.log`: full 4096-byte Save As, independent disk
  readback/reopen, 4097-byte rejection without losing text, chooser Cancel.
- `delivery-clipboard-1984.log`: Copy, producer owner teardown, Paste replacing
  the new owner's selection, save and independent readback.
- `delivery-write-denied-1984-r3.log`: real FAT read-only protection, error
  acknowledgement, dirty text retained, Save As recovery, original unchanged.
- `delivery-disk-full-1984.log`: a real filler file consumes all free M4
  clusters; failed Save As retains dirty text, Cancel preserves edits, explicit
  Discard/New works and all contexts/pages are reclaimed.
- `delivery-stress-1984-r2.log`: 12 actual document owners, File Manager
  covering the editor with unchanged foreground pixels during caret activity,
  refocus and close, per-cycle sealed-page cleanup and final exact reclamation.
- `delivery-openmsx/result.txt`: 286 actual parameter/restoration checks,
  keyboard navigation, save/reopen and guarded File > Quit.
- `delivery-1983-7/result.json`: Screen 7 workflow and full 4096/4097 bounds,
  independent readback and complete reclamation.
- `delivery-openmsx-6-build-r2.log`: newly assembled Screen 6 receiver with
  mode-specific routing module; same APP, 286 parameter/restoration checks.
- `delivery-receiver-regressions.log`: 48 receiver/service/controller tests.
- `delivery-integration-unit-r2.log`: 26 input, delivery-manifest, MSX boot
  module and real editor/popup tests.

All abbreviated logs above are under `build/notepad-84/evidence/`.
Failed earlier runs are retained: first-consumer GETKEY incorrectly swallowed a
clean close (fixed); initial acceptance predicates inspected only the low byte
of 4096 and clicked outside the covering File Manager (test fixes). Error-key
tests now observe actual root-loop settling after the popup's click debounce.
Do not confuse those failed attempts with the passing evidence above.

Normal delivery needs separate MSX `GBPKWM6.MOD` and `GBPKWM7.MOD`: their
resident-call addresses and version signatures are mode-specific. Both use the
same APP and fixed loader/service modules; neither mode's router may overwrite
the other when assembling both kernels.

## Normal delivery — completed locally

`make cpc` now emits profile `cpc-desktop-m4-v4`: the full existing Desktop,
native File Manager/Settings and universal Clock/Calculator/Notepad. The
boot-checked package receiver and filesystem API v3 are enabled together.
The default preemptive MSX build stages the same Notepad plus the qualified
fixed modules and each screen mode's router. Historical cooperative/baseline
comparison builds retain native Notepad; its source was not deleted.

Both File Managers launch `/GBENCH/NOTEPAD.APP` directly or hand off a selected
TXT/CFG's copied drive/path/name to a fresh owner. One build, identical APP
bytes on both targets; no CPC-specific Notepad source or reduced document
buffer. Native File Manager/Settings have not become universal apps by this
change. Existing-instance document reuse and live configuration refresh are
still separate follow-ups, not silently claimed as delivered.

Normal build/test evidence under `build/notepad-84/evidence/`:

- `delivery-normal-cpc-build-r2.log`: validated v4 CARD/image/manifest.
  CORE **16185/16384**, SUPPORT **3035/3072**, HARDWARE **1486/1536**,
  SCHED **1452/1536**, FSCTX **4853/6656** bytes. No limit was increased.
- `delivery-normal-msx-build-r2.log`: complete normal CARD/image; mode-specific
  child COMs **14526/16128** (Screen 6) and **16104/16128** (Screen 7).
  The Screen 7 child has only **24 bytes spare**: preserve its size gate.
- `delivery-normal-msx-inventory.log` and `normal-msx-fixtures/manifest.json`:
  **every file** in the actual packed normal image matches CARD, including
  both mode routers; test fixtures copy that image, not a private receiver.
- `normal-msx-editor-{6,7}/result.json`: 1983, **67/76 checks**, actual typing,
  arrows, save/reopen, dirty decisions, full 4096/4097 bounds and reclamation.
- `normal-msx-handoff-{6,7}/result.json`: 1983, **47/53 checks**, actual File
  Manager root/nested exact-path document launches and saved-file readback.
- `normal-msx-desk-{6,7}/result.json`: 1983, **243/273 checks**, Clock/Calculator
  lifecycle, cursor cadence and **50 short Desk-click cycles per mode**.
- `normal-msx-openmsx-{6,7}/result.txt`: **282 parameter/restoration checks per
  mode**, actual keyboard/chooser/guarded Quit workflow and saved-file readback.
- `delivery-normal-cpc-acceptance.log`: **34/35** scenarios passed in the
  first combined run, including all seven new delivered-Notepad cases. Its
  old workflow expected CFG to be unsupported, which is no longer correct.
  `delivery-normal-cpc-workflow-r3.log` reruns the corrected case against the
  **same image**, with **28 pixel/ownership checkpoints** passing. The test now
  selects unsupported CORE.BIN and parks the pointer outside the alert before
  comparing unhighlighted rows. No runtime change was needed for these test
  corrections. All **35 scenarios** are therefore covered successfully;
  the original failed report is retained, not relabelled.
- `delivery-final-unit.log`: **66** host/Z80 tests; `delivery-gate-unit.log`
  adds the actual primary/document module build and wrong-profile rejection.
  `delivery-manifest-final-unit.log`: **15** focused repeats, including
  rejection of native Notepad payloads and mixed/truncated mode modules.
- `delivery-result.json`: combined evidence and explicit corrected-case
  provenance. Normal source image hashes were checked unchanged after tests.
- `delivery-historical-gate.log`: the historical primary-only gate passes
  in its isolated output directory, without replacing the normal receiver.

Final normal-image SHA-256:

- MSX: `dfb8bbdf178d7295b361d318d61fb3e923c3309f64e44fe44439d20c10e98491`.
- CPC: `a3fc23986f7cfb97f37d9e48e12c74002e6bc595e9191f759344343b0a845ce8`.

The APP remains **20213 = 14447 + 5766 bytes**, primary code ending `786F`
with DATA at `7870` (one byte spare), and secondary state ending `7E27`.
Keep the independent 4096-byte document and 4096-byte transactional staging.

## Manual check

Images are already rebuilt. For openMSX:

```sh
MSX_UNAPI=0 tools/run_msx.sh QA/MSX/GBMSX.IMG
```

For 1983, mount `QA/MSX/GBMSX.IMG` as the Sunrise IDE image. For CPC/1984:

```sh
bash tools/run_cpc.sh
```

Open the disk, enter GBENCH and double-click NOTEPAD.APP, or double-click a
TXT/CFG document. Test typing/arrows, File > Save As, close/reopen, Edit >
Select All/Copy/Paste, and File > Quit with Save/Discard/Cancel. On CPC, hold
Ctrl with arrows/Space to move/click the pointer while text has focus; Escape
closes/cancels once per press. Use copies of generated images for personal
documents: rebuilding replaces generated media. Earlier manual images and the
pre-delivery backup remain untouched. CPC tests used M4 only, no floppies.
