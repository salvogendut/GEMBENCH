# Session handoff — 2026-09-09

Local working memory saved at the user's request. Read this together with
[the v1.0 roadmap](ROADMAP-V1.0.md) before resuming. Recheck Git and current
files rather than assuming this snapshot remains current.

## Quick resume — saved at the user's request, 2026-09-09

- The user requested **commit/push, roadmap and memory/handoff updates**, then
  a pause. Do not interpret this checkpoint as permission to PR/merge, replace
  normal images or implement another slice without a subsequent request.
- This file is the durable repository working memory. Source, contracts,
  diagnostic drivers and test definitions belong in the branch commit; large
  generated evidence and private images remain local in `build/notepad-84/`.
  A push does not back up those ignored artifacts. Preserve this worktree.
- Read the [four remaining work packages](ROADMAP-V1.0.md#saved-checkpoint-and-remaining-delivery-path--2026-09-09)
  and [secondary-code integration contract](PORTABLE-SECONDARY-CODE.md).
  Native MSX Notepad still works; **there is no runnable unified Notepad** and
  no new editor on CPC. The full portable editor link still exceeds memory.
- Resume with measured MSX loader placement, one-open streaming and safe
  interrupt/progress boundaries. Then implement the sealed secondary call gate,
  partition the editor, and qualify/deliver the identical APP on both targets.
  Do not restart the completed clipboard, chooser, owned-page or stream-fixture
  work. The streamed loader is not wired into either receiver; its emulator
  evidence must not be confused with the existing single-segment PAGEPRB runs.
- Budget discussion: the user reported about 20% of the weekly allowance left.
  Four packages are an estimate, not four sessions or a completion promise.
  Prioritize a first testable MSX build; defer full CPC editor acceptance until
  that exists, while retaining shared code and relevant CPC regressions. Neither
  the eventual compile-once requirement nor the safety/feature gates is waived.

### Save-point verification

Before the save commit, **40 focused tests passed, no skips**, using the project
SDCC/RASM toolchain in `my-distrobox`. The repeat includes streamed admission,
data pages, owner/page policy, parameter boundaries, typed clipboard, MSX button
capture, document I/O, chooser and the editor's host model/controller. Log:
`build/notepad-84/evidence/checkpoint-save-tests.log`. Reproduce from the repo:

```sh
PYTHONPATH=tests python3 -m unittest test_package_stream test_data_pages \
  test_owner_page_core test_client_parameter_core test_universal_parameters \
  test_portable_clipboard test_msx_button_capture test_docio test_filepick \
  test_unotepad -v
python3 tools/check_geobench_v2_abi.py
python3 tools/test_gbap4.py
```

ABI conformance and GBAP packaging/corruption checks also pass. This save-only
turn does not repeat emulator or full-distribution qualification; prior evidence
is recorded below. The three normal media hashes still match the saved values.

## Repository and decisions

- Workspace: `/var/home/salvogendut/Dev/GEMBENCH`.
- Public project identity is **GEOBENCH**, with the restored blue/white/black/red
  scheme and lollipop artwork. Keep BSD-3-Clause licensing.
- The user clarified that v1.0 must finish **both MSX2 and CPC distributions**.
  MSX2 is the behavior reference, not a completed universal distribution: only
  Clock and Calculator are production unified apps; ABIProbe is diagnostic.
  CPC has an accepted M4 desktop, but not full MSX2 application/feature parity.
  Both assume >=512 KiB. Track MSX completion, CPC completion and identical-binary
  migration separately, with release acceptance for each target.
- The user finds the current CPC desktop very stable and wants that stability
  on MSX too. Establish a Screen 6/7 baseline at milestone 1's first checkpoint;
  carry responsiveness, repaint, lifecycle and fault checks through migrations
  on both targets. This is an acceptance goal, not a new test result.
- Restore the CPC boot splash using existing GEOBENCH artwork as part of
  milestone 4's boot/desktop integration, with M4 cold-boot/clean-handoff checks
  and later Albireo coverage. Keep the existing MSX splash working.
- Shared kernel policy is authoritative: ownership, window lifecycle, stacking,
  visibility/damage, scheduling, deferred messages and filesystem contexts.
  Use target adapters for hardware; do not introduce another CPC shell/core.
- The user explicitly wants more **unified-ABI application migrations**.
  Shared C source with separate target binaries does not meet compile-once.
  Migrated apps must have identical payloads on MSX2 and CPC.
- Kernel, hardware providers and native root/system components can be target
  builds. File Manager and Settings still need universal application migration.
- PCW is a later port. The v1.0 roadmap follows that existing order, while
  preserving the ABI's future monochrome portability. Product v1.0 does not
  renumber ABI 2.1, GBAP v4 or the frozen GEMBENCH-1 contracts.

## Current checkpoint — shared secondary stream core qualified; receivers next

The user authorized starting unified Notepad after the MSX findings were
resolved. **Issue #82 is closed** as a bounded baseline/inventory checkpoint,
not whole-distribution release acceptance. The
[MSX baseline close-out](V1-MSX-STABILITY-BASELINE.md#close-out--2026-09-09) and
[application ledger](V1-APPLICATION-LEDGER.md) record evidence and limits.

- GEMBENCH PR #83 merged short-button capture at main `1367593`; RainBIOS
  PR #171 merged bitmap dispatch/display/clear at `e28ff2f` (#169 closed).
- The remaining first-VRAM-read discrepancy was 1983 immediate IN timing.
  1983 PR #172 is merged at `c0a0b4a`; 1983 #171 and RainBIOS #170 are closed.
  The normal sibling 1983 executable was rebuilt at that merge. Original
  RainBIOS main/direct-SUBROM/MSX1 probes now pass with unchanged corrected
  ROMs; independent openMSX controls also pass. No bundled ROM was replaced.
- Final evidence: `build/1983-171/.local/evidence/`, including merged-main
  firmware repeats and Screen 6/7 GEOBENCH lifecycle/50-short-Desk-cycle runs.
  Preserve earlier failed evidence in `build/msx-stability-82` too.
- Fixed private MSX images and matching symbols remain in
  `build/msx-buttons-82`, final media `evidence/mode{6,7}/GEOBENCH.IMG`.
  Do not use its stale initial aggregate QA image. Corrected RainBIOS ROMs
  are in `build/rainbios-170/build/`; see baseline hashes.
- Physical/SDL mouse smoothness, 4–6-frame keyboard-pointer gaps, long stress,
  MSX storage faults/exhaustion, hardware and remaining app coverage are still
  release work. Closing the observed blockers does not close those gates.
- [Issue #84](https://github.com/salvogendut/GEMBENCH/issues/84) and branch
  `feature/84-unified-notepad` now track the real editor migration. First work:
  [source/memory audit and document I/O](UNIFIED-NOTEPAD.md). Notepad is still
  native; there is no new testable editor APP or migration-complete claim.
- Isolated native rebuild `build/notepad-84` exactly matches the old payload.
  Data ends at `0x7FF9` (seven native bytes spare), beyond the universal
  `0x7F00` limit. Account for caller-owned scratch, 544-byte FS storage and
  v4 metadata; retain 4096-byte document capacity and measure the full link.
- SDK helper `gbdocio` reuses the real shared FS client: one
  operation/at most 512 bytes per step, explicit EOF/oversize/error/cancel,
  borrowed contexts and no atomicity promise. Three new plus 13 existing
  focused tests pass with no skips; Z80 job is 11 bytes, helper code 888 bytes.
  That first slice did not change receivers; it remains unlinked from Notepad.
- Checkpoint 2a: typed clipboard now has one shared kernel policy, capability
  `typed-clipboard` (`0x01000000`), `GB_PARAMS` operation 9 and
  `UNIVERSAL_SCRAP=1`/`gbscrap.h` SDK bindings. SDK cost: 359 code + 8 data
  bytes. MSX native raw/tag behavior remains; CPC's portable service is now
  implemented, while its legacy raw API slots remain unavailable.
- Identical 4808-byte SCRAPPRB.APP passes 149 checks across three owner
  lifetimes on CPC M4/1984 and MSX Screen 6/7 in both openMSX and 1983.
  openMSX additionally checks 146 call returns/VRAM preservation per mode and
  106 injected parameter boundaries after the real Clock/Calculator workflow.
  Five new clipboard contract tests, native scrap regressions and the complete
  SDK integration pass. See `UNIFIED-NOTEPAD.md` for logs/hashes and limits.
- Full host suite: 301 pass and one initially skipped (isolated worktree lacked
  a sibling 1983 path). Both input tests then pass with the explicit source
  path and a corrected test loader that no longer truncates the enlarged
  module. Private full CPC Desktop stacking/cadence also pass: 58 checkpoints,
  stack high-water main 144/IRQ 4/temporary 6, cursor 49.24/48.86 steps/s with
  focused/background seconds. This is targeted regression coverage, not a
  repeat of all delivery/storage-fault acceptance.
- MSX module is now 2889 bytes. Its private ABI 2.0 sysinfo view moves to
  `0x0FD0`; both still fit the unchanged reserved module region. The complete
  private CPC Desktop also fits. The app/stack boundaries remain unchanged.
- Checkpoint 2b adds the owned portable chooser/content panel, linked through
  `UNIVERSAL_FILEPICK=1`; bounded I/O is now opt-in with `UNIVERSAL_DOCIO=1`.
  Both require `UNIVERSAL_FS=1`. No new kernel/provider changes in this slice.
  Paging, filtering, nested/empty folders, Save As naming, cancel/restart and
  context handoff run without a modal polling loop or disk writes.
- The identical 9834-byte `PICKPRB.APP` reads selected files into an actual
  guarded 4096-byte buffer. Save As only selects a destination; no write/editor
  acceptance is claimed. Data/BSS ends at `0x7E64`; this diagnostic fit is not
  proof that the complete editor fits. Caller-owned chooser: 161 bytes;
  model/renderer code: 2852/1581 bytes, no persistent library data.
- Final chooser evidence in `build/notepad-84/evidence/`: openMSX
  `chooser-msx{6,7}-painted.log` (13 input checkpoints/47 preserved returns per
  mode), 1983 `chooser-1983-{6,7}-painted/result.json` (122/161 checks), CPC M4
  `chooser-cpc-painted/result.json` (13 checkpoints plus exact close exposure;
  stack main 205/IRQ 4/temporary 0). Independent status-glyph checks on 1983
  and CPC catch model-only false passes; final screenshots were inspected.
  APP SHA-256 `b7831fed4c063447559cd2dc4abc8cf8a70ae895a5acb46e0644da0fb536f133`.
  All 25 focused host tests, deterministic SDK packaging and the original
  Screen 7 FS probe (46 preserved returns) pass. This is not a full-suite or
  storage-stress repeat of the earlier checkpoint.
- Known CPC provider gap: dotted directory names such as `/DOCUI/DIR.EXT`
  fail activation; filename punctuation support is also narrower than the
  chooser's DOS 8.3 syntax. The host model handles dotted folders. Actual M4
  failure/cleanup evidence is retained in `chooser-cpc-dotted-failure/`;
  passing runtime fixtures use `DIR`, not `DIR.EXT`. Fix the provider before
  full document portability acceptance; do not add editor target workarounds.
  This was the end of checkpoint 2b; the editor integration below is newer.
- Checkpoint 2c: `apps/unotepad` now contains the actual editor model and unified
  window/menu/clipboard/document controller. Native `apps/notepad` is untouched.
  Host tests cover dirty New/Close/Ctrl-Q, real chooser context handoff, Save As
  overwrite confirmation, failed/cancelled/oversize load preservation, partial
  save errors and cleanup retry. Two-key frame bounds, >255 display rows and
  streaming BASIC CRLF (full 4 KiB documents without rewriting the buffer) pass.
- Complete candidate link **does not fit**: code 18604, preamble 364, startup 34
  = 19002 loaded bytes (end `0x8A3A`); data/BSS 9855; combined 28857 vs allowed
  16128. `DATA_LOC=0x6000` is a rejected diagnostic layout, not runnable media.
  Builder fails before APP packaging. No editor emulator acceptance or normal
  image update. Do not run the overlapping IHX or relax the memory/stack gate.
- Evidence under `build/notepad-84/evidence/`: `editor-final-relink.log`,
  `editor-object-audit.log`, `editor-host-final.log` (two tests),
  `editor-docio-regression.log` (three), `editor-filepick-regression.log` (four).
  Host tests mock public storage/clipboard/drawing, not real emulators. Sanitizer
  linking was unavailable due to missing host/container runtime libraries.
  Retain earlier failed link logs too. The audit records final source hashes.
- **Next dependency:** specify/review and qualify minimum owned data/copy and
  validated secondary-code services from roadmap milestone 2, then repartition
  the actual editor. Even removing the entire transactional load buffer cannot
  fix the code-only overflow. No new page ABI was implemented this checkpoint.
  Shell launch/adoption/reuse, configuration reload, CPC name parity and actual
  editing/write/failure/repaint/input/cleanup acceptance remain after that gate.
- **Newer checkpoint 2d:** user approved the owned-page prerequisite. First
  data-page slice is implemented and privately qualified; next is validated
  secondary-package loading/calling, not editor delivery. See `PORTABLE-PAGES.md`
  for the authoritative contract, sizes, exact evidence paths and limitations.
  Capability `portable-data-pages` (`0x02000000`), GB_PARAMS 10; SDK
  `UNIVERSAL_DATA_PAGES=1`, 283 code + 16 data bytes. Shared policy, DOCUMENT-only
  ownership, <=512-byte synchronous copies, primary buffers, root/nonterminating
  owner checks and unchanged app/stack limits. Receiver `PORTABLE_DATA_PAGES=1`
  stays opt-in; normal delivery remains unadvertised/unmodified.
- Identical PAGEPRB.APP 5004 bytes passes Screen 6/7 in openMSX and 1983 and
  CPC M4/1984: full pages, exhaustion, invalid bounds, three owner lifetimes and
  exact reclamation. openMSX records 407 preserved returns per mode. Additional
  purpose/foreign/worker/terminating/mapping rejection is instruction-fixture
  evidence. All 29 focused tests pass; not a full-suite/storage-stress repeat.
- MSX adds private `GBDPAGE.MOD`, 492 bytes at D100, and its loader after the
  aligned VDP tables; including it directly in the kernel exceeded the child
  loader bound. Screen 7 COM now 15957/16128, opt-in admission module 2931 bytes.
  CPC private support is 2644/3072 and kernel 15505/16384. These are private
  runtime-profile fits, not completed normal Desktop integration.
- **Newer checkpoint 2e:** shared two-segment streaming admission/CRC/load and
  rollback is implemented in `kernel/core/package_stream.asm` and its contract,
  using the existing `app_admission.asm` under internal `ADMISSION_STREAMED`.
  Neither receiver selects it. Transaction 742 bytes; streamed admission/CRC
  1296 bytes (includes 15 mutable fixture bytes), state 22 plus 512 scratch.
  459 actual Z80 checks at each of two fixed layouts; 31 focused tests pass.
- Existing dual-icon admission arithmetic was wrong; corrected in the shared
  validator without changing instruction/module sizes. The same 5524-byte
  dual-icon PAGEPRB passes MSX Screen 6/7 openMSX/1983 and CPC M4/1984. Evidence
  is `secondary-stream-complete.log`, `secondary-dual-icon-msx{6,7}.log`,
  `secondary-dual-icon-1983-{6,7}/`, and `secondary-dual-icon-cpc-artifacts/`
  in `build/notepad-84/evidence/`. Emulator runs cover the existing single-
  segment route, NOT the new stream loader. Full contract/next steps are in
  `PORTABLE-SECONDARY-CODE.md`; no new public call capability or editor APP.
- Next requires measured fixed placement and persistent stream adapters:
  MSX boot/browse and strict paths must survive; CPC's existing read-at loader
  reopens per read and cannot satisfy single-open identity. The low boot region
  is only a candidate for reclamation pending lifetime audit; CPC's named
  FUTURE_STATE region is already occupied. Do not relax bounds or overwrite it.
- Stream-only register CRC reduces maximum fixture cost from 64453420 to
  25602091 T-states, excluding storage/IRQ. Still too long with IRQs excluded:
  qualify safe interrupt/progress boundaries before enabling the receiver
  path. Functional fixture acceptance is not desktop input-latency acceptance.
- No normal media was rebuilt. Before/after SHA-256 values:
  MSX `047a19d38e05f009df8c07a22be90e226a98bc68992fc7474c34015f251ce308`;
  CPC Desktop `c1b09dbc08299b217443d2a06d66f8688ba0e7cf50be0a2a41e2a7475cf94b14`;
  CPC runtime diagnostic `cf9c77e1b277eecab608e6e7b8a19e332848fe1b3f34678cd89e2fb9135f48bd`.

## Git and publication snapshot

- Current branch: `feature/84-unified-notepad`, based on `1367593`.
  The user requested publication of this checkpoint on 2026-09-09. The save
  commit is titled `Save unified Notepad foundations and migration handoff`;
  verify its hash and remote tracking with Git before resuming. Issue #84 stays
  open; no PR/merge or normal-distribution replacement is requested.
- GEMBENCH [PR #83](https://github.com/salvogendut/GEMBENCH/pull/83) and
  roadmap [PR #81](https://github.com/salvogendut/GEMBENCH/pull/81) are merged.
  Sibling RainBIOS PR #171 and 1983 PR #172 are merged separately. Preserve
  their worktrees/evidence; do not stage sibling diagnostic/untracked files.
- Settings integration commit: `9c5a7514bdcc53b6d94e86a6af17997b7fde7510`.
- [PR #80](https://github.com/salvogendut/GEMBENCH/pull/80) is merged;
  [issue #79](https://github.com/salvogendut/GEMBENCH/issues/79) is closed.
  Feature branch `feature/79-cpc-settings` was pushed and retained.
- Earlier accepted desktop sprints were merged in PR #78 at `68b1607`.
- Preserve unrelated untracked user files: `1984-20260906-200304.gif`,
  `1984-20260906-231044.gif`, and parked `QA/CPC/`. Do not blanket-stage them.

## Accepted CPC delivery

`make cpc` builds `cpc-desktop-m4-v3` under `build/cpc-desktop` and
`QA/CPC-Desktop`. The normal M4 image includes:

- actual shared Desktop and native File Manager, Disk C navigation,
  independent browse contexts, list/icon views and persistent View preference;
- unified Clock and Calculator, Desk activation, managed windows and
  background/occlusion-aware Clock repaint;
- actual shared Settings via System > Settings, with font, icons, cursor,
  title bar, gadgets and backdrop. Settings remains native/build-matched.

The user tested and accepted the image, then requested and received PR/merge.
Details and limitations are in [CPC-SETTINGS-INTEGRATION.md](CPC-SETTINGS-INTEGRATION.md).

Manual launch without rebuilding:

```sh
distrobox enter my-distrobox -- bash tools/run_cpc.sh
```

Arrows/joystick move the pointer; Space clicks/drags. Escape cancels/closes.
Clock's S shortcut enables seconds. Saved configuration lives in the mounted
image, not the host CARD staging directory. The user may have changed settings
since acceptance: do not rebuild/reset the manual image just to inspect it.

The earlier accepted image and matching build are backed up locally at
`build/cpc-settings-delivery-backup-Yj4zsp/{CPC-Desktop,cpc-desktop-build}/`.
The backup config still names the normal image path; it is a restore backup,
not a direct alternate launcher. Parked QA/CPC and normal MSX media were preserved.

## Qualification evidence already completed

- Private Settings Gate B: 20 M4 scenarios / 316 pixel checkpoints, including
  storage-fault and repeated-selector/lifecycle stress.
- Final normal delivery: **28/28 scenarios / 323 pixel checkpoints** passed.
  `build/settings-gate-c-final-delivery.log` and
  `build/cpc-delivery-runtime/geobench-cpc-delivery-_v8pxaj0/result.json`.
- Independent stacking repeat: 32 checkpoints passed;
  `build/settings-gate-c-safe-stacking-repeat.log` and
  `build/cpc-delivery-runtime/geobench-cpc-runtime-dg0e7lak/result.json`.
- **285 host tests, no skips**, plus all remaining make-check components passed.
  Logs: `build/settings-gate-c-final-host.log` and
  `build/settings-gate-c-final-check-rest.log`. The latter ran GBR reader tests
  then `make -o gbr-check check`, reusing the completed host suite.
- Rebuilt identical Clock/Calculator passed openMSX Screen 6 and Screen 7
  accessory/background lifecycle checks on disposable cards:
  `build/settings-gate-c-msx6.log` and `build/settings-gate-c-msx7.log`.
  `GEOBENCH_ACCESSORY_REBUILT_APPS=1` lets the harness stage rebuilt apps without
  modifying accepted MSX media.
- Before publication, 21 focused delivery/SDK tests and diff checks passed.
- The roadmap's local links and eight milestone sections were checked;
  `git diff --check` passed. No runtime rebuild was needed for the roadmap.

Qualified pristine CPC image SHA-256 (manual saves may subsequently change it):
`2edf0e72ab0954ebf98eb03c6b34f43adc43fe72efcd6796fbaeeadc15d313ee`.
Clock: 8,163 bytes,
`efb1b136c57969f91eeef186118cfc8296af1a41410ab8ce13a2a63256050102`.
Calculator: 7,833 bytes,
`0f4c3c7625ba4c904ca28663e392d80210fb933ae09a34f80795291d5086df65`.

Avoid repeating the entire qualification without relevant changes. Historical
checkpoint documents contain old "pending" statements: use their dated status
and the latest integration/roadmap documents, not isolated old sentences.

## Important fixes and constraints to preserve

- CPC Settings uses owned FS contexts and a bounded 16-byte icon-header read,
  not the retired 6,656-byte buffer at 0x2200. Its supported save path verifies
  readback before publication, but does **not** promise atomic/power-loss rollback.
- Settings can construct 16 filenames plus SOLID: its native popup limit is 17.
  The default GBUI limit remains 16 for other builds.
- Legacy SDK `POP HL; DEC SP` one-byte arguments are interrupt-unsafe: an IRQ
  can overwrite the caller's next live stack byte. Native Settings-profile
  clients opt into safe reads; universal app builds now always do so too.
  Keep `build_uapp.sh --interrupt-safe` generation and its regression tests.
- A failed first delivery run left five bytes of Clock seconds erased after
  Calculator moved. An unfixed repeat passed; the universal stack bug can
  corrupt Clock's saved X after fill and cause text rejection. That exact IRQ
  was not captured in the failing snapshot, so do not claim trace proof for it.
  Corrected final delivery and independent stacking runs passed without loosening
  the pixel oracle or changing the compositor/glyph renderer.
- Native MSX Settings/GBUI behavior was preserved; universal Clock/Calculator
  payloads changed consistently across targets for the SDK fix.

## v1.0 roadmap and next work

The requested roadmap is saved in `docs/ROADMAP-V1.0.md`, linked from README
and the earlier roadmap. Eight planned milestones:

1. Unified Notepad and its portable document/clipboard/storage services.
2. Portable resources/forms and owned page/secondary-code services; GBRDEMO/FormRef.
3. Unified Settings and File Manager, preserving MSX functionality and explicit
   capability behavior on CPC.
4. CPC boot splash and full file/desktop workflows: copy/move/delete/drag-drop,
   associations, Trash, general qualified-app loading, palette/wallpaper/defaults,
   firmware return.
5. Paged and multi-window apps: PAINT, Viewer, Icon Editor and bundled BASIC.
6. Remaining apps/providers: networking, sound, games, savers and saver controls.
7. Both targets' storage/input/hardware coverage, including CPC Albireo and
   independent confirmation, plus MSX Screen 6/7 validation.
8. Close the migration/parity ledger and SDK/release-artifact/manual acceptance
   gates for both distributions.

**Next: bind the shared streamed loader to measured MSX/CPC layouts and single-
open file adapters, then implement the sealed root call/return gate for #84.**
Data-page service is privately qualified; the streaming core has instruction-
fixture acceptance only. The full editor still fails its code-size gate.
Follow `PORTABLE-SECONDARY-CODE.md`, `PORTABLE-PAGES.md` and `UNIFIED-NOTEPAD.md`:
qualify both receivers, then repartition
the editor and finish portable document handoff/configuration. Preserve 4 KiB
capacity and the reserved stack. Close the CPC provider path-name gap before full
document acceptance. Reuse shared policy; review missing service contracts instead
of inventing target-local workarounds. Qualify MSX Screen 6/7 using openMSX and
1983, then identical APP bytes on CPC/M4, including document/failure/cleanup
workflows before replacing native delivery. CPC splash remains milestone 4.

## Tools and testing workflow

- Use `gh` from `my-distrobox`. **Always specify `--repo salvogendut/GEMBENCH`**:
  its inferred default selected upstream `salvogendut/geobench` during a read.
  `origin` is GEMBENCH; `upstream` is the separate historical GEOBENCH repository.
- Project toolchain inside the container:

  ```sh
  export PATH=/var/home/salvogendut/Dev/sdcc/bin:$PATH
  export SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc
  export SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80
  ```

- Use M4/Albireo-backed CPC tests only, on disposable copies. No floppy fallback.
  `../1984` is the qualified M4 runner; Albireo, other CPC emulators and actual
  hardware remain qualification work. Consult `CPC-EMULATOR-TEST-STRATEGY.md`.
- Sibling emulator fixes need separately authorized issues/branches in that
  repository. Do not alter an emulator to conceal an application/core defect.
- Keep MSX regressions proportionate; use openMSX for independent MSX confirmation.
- Large artifacts now go under `build/`; /tmp previously hit a per-user quota.
  For host tests, `TMPDIR="$PWD/build/settings-check-tmp"` was used.
- Do not delete old worktrees, test evidence, user media or recordings as part
  of resuming. The current checkpoint's commit/push is explicitly authorized;
  this note grants no standing authority for later publication, cleanup, new
  issues, PRs, merges or releases.
