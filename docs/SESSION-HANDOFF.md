# Session handoff — 2026-09-13

Local working memory saved at the user's request. Read this together with
[the v1.0 roadmap](ROADMAP-V1.0.md) before resuming. Recheck Git and current
files rather than assuming this snapshot remains current.

## Current resume point — CPC desktop secondary receiver, 2026-09-13

Continuing #84 / `feature/84-unified-notepad` after pushed `fd04dd1`.
The private full Desktop/File Manager/Settings runtime now uses shared
two-bank package admission and sealed calls with CPC owner/page/bank leaves.
Read [UNIFIED-NOTEPAD-CPC.md](UNIFIED-NOTEPAD-CPC.md) for current evidence and
commands. This follow-up has not been promoted into either distribution.

- Build: `python3 tools/build_cpc_runtime.py --notepad-receiver` with compiler
  tools from `my-distrobox`. Work is `build/cpc-notepad-receiver`; media is
  `build/notepad-84/cpc-receiver`, explicitly private. Real M4/1984 tests use
  `--skip-build --private-media build/notepad-84/cpc-receiver`; never floppies.
- `GBPKLOAD.MOD` is 768 loaded bytes at `0100..0400`, installed only after the
  low bootstrap exits. Exact size/EOF/close/build CRC precede readiness. Shared
  `core/package_stream.asm`, `secondary_call.asm`, launch/admission and owner
  cleanup supply policy; new CPC glue only binds transport, mapping and calls.
- Full measured CORE 16366/16384, SUPPORT 3035/3072, HARDWARE 1483/1536,
  scheduler 1452/1536, BOOT 6312/6656. Fixed state `1F00..1F80`, transfer
  `1500..1700`. No memory limits changed. No data-page combination qualified.
- Three real Desktop launches of the existing computation APP pass 54 checks /
  17 copied calls each, exact bank bytes, unique owner generations, seals,
  cleanup and code/stack guards. Bad loader modules stop boot safely. See the
  CPC work record for full regression/evidence details.
- **Next: FS identity/owner-bound handoff and focused text routing**, then the
  identical Notepad APP's CPC editing acceptance. Filesystem remains API v1;
  don't claim the editor works yet. The 18-byte high-kernel remainder requires
  a measured placement/code-size solution for those bindings, not app shrinkage.
- Do not rebuild `build/cpc-notepad-receiver` underneath active emulator tests:
  integrity checks use that directory's exact binaries/symbols. The stream
  implementation now includes `lib/cpc/m4_stream_read.asm`; include this new
  file when syncing sources. Default full resident/bootstrap outputs were
  checked byte-for-byte against `fd04dd1` and are unchanged.
- Preserve accepted MSX APP SHA `1d554abb…cdc340e8` (20209 bytes), both manual
  MSX saved-document images, normal MSX/CPC media, user GIFs and `QA/CPC/`.
  No sibling emulator/firmware changes, PR or merge in this follow-up.

## Previous resume point — CPC Notepad transport, 2026-09-13

User requested commit/push of the accepted MSX fixes followed by CPC receiver
work. **`6e6fe05` is pushed** on #84 / `feature/84-unified-notepad`. The CPC
follow-up adds a private single-open M4 reader and host/Z80 + real 1984/M4
qualification, not a runnable editor. Read
[UNIFIED-NOTEPAD-CPC.md](UNIFIED-NOTEPAD-CPC.md) first for implementation,
evidence and placement constraints. The next gate is **production-budget
private receiver composition with the existing shared loader and sealed call
gate**, then FS identity/handoff and focused text input. Do not advertise a
capability or supply a CPC editor image based only on the transport probe.

- Same APP SHA `1d554abb…cdc340e8`, 20209 bytes, preserved unmodified. Actual
  1984/M4 copied both segments byte-for-byte: one OPEN / 160 READ2 / one CLOSE.
  6,058 Z80 adapter calls pass; malformed/short/extra/missing cases and cleanup
  are covered. Emulator/source untouched. New sources include
  `lib/cpc/m4_stream.asm`, `debug/cpc_foundation/stream_probe.asm`,
  `tools/test_cpc_stream_1984.py`, and their two test files.
- The 510-byte adapter has **no production binding yet**. Stable runtime
  hardware has only 406 bytes free, support 1236, high kernel 563. Probe
  placement is not proof of complete receiver fit. Preserve the loader until
  it has jumped out of `0100..0400`; check the `9A00` bootstrap limit too.
- New tests build only under `build/notepad-84/evidence/`. No mirror sync or
  normal-image rebuild was needed for this isolated gate. Before subsequent
  private runtime builds, sync new and changed sources explicitly.
- Preserve the old manual saved-document images, normal MSX/CPC media,
  user's two GIFs and untracked `QA/CPC/`. No PR/merge requested.

## Previous resume point — focused Notepad editing (2m), 2026-09-13

Latest user request: **commit/push the accepted MSX fixes, then implement the
CPC receiver support for the identical Notepad APP**. The arrow/repaint fixes
are grouped in the 2m save after `d950560` on #84 / `feature/84-unified-notepad`;
check branch history for publication. Read the new current section of
[UNIFIED-NOTEPAD-HANDOFF.md](UNIFIED-NOTEPAD-HANDOFF.md) for precise evidence,
fit, limitations and the fresh image `build/notepad-84/manual-edit-cEUP1X/NOTEPAD.IMG`.

- Appended `GB_WK_TEXT_INPUT` selects plain arrows/Space for the focused
  editor, with Ctrl+arrows/Space retaining keyboard-pointer access. MSX-only
  receiver implementation, default/native behavior unchanged. New source
  `kernel/msx_text_input.asm` must be included when syncing/committing.
- Actual old/new rendered row comparisons in the secondary model bound edit
  damage to changed column spans. Dirty-title strip is separate. Full 4-KiB
  document/staging preserved; viewport scroll retains client repaint fallback.
- Private modules `GBV4,7` and `GBWM,0x66/0x67`, same extents and **CF60 IRQ
  entry preserved**. Never relocate that entry independently of app-carried
  scheduler payloads. CF3B is a new private cached routing byte.
- Final APP `1d554abb…cdc340e8`, 20209 bytes; primary ends `786B`, DATA `7870`,
  top `7EF5`. Only 5/11 bytes code/data headroom. Secondary end `5686`, top
  `7E27`. openMSX Screen6/7 navigation/edit/save/reopen passes with 262 exact
  secondary returns per mode. 1983 Screen6/7 navigation/focus (46/76 checks,
  Screen7 also boundary/dirty-close) and exact-path handoff/save (53 checks)
  pass. 52 host/Z80 regressions pass.
- New observer bridge supports `keys row mask row mask` for real Ctrl chords;
  build with `MSX_TEST_WRITABLE_IMAGE=1 bash tools/build_msx_stability_1983.sh`.
  Use disposable image copies. Do not drive joystick axes with MSXMOUSE=TRUE:
  the receiver interprets those bits as mouse replies. Trigger clicks work.
- Old manual image and normal release images are untouched. No sibling
  emulator/firmware edits. Next architectural tasks remain exact-path reuse
  of an existing editor, configuration reload and eventual CPC qualification.

## Previous resume point — real Desktop document launch (2l), 2026-09-13

Latest request: **commit and push, and explain manual testing**. On #84 /
`feature/84-unified-notepad`; checkpoints 2k/2l are grouped in the
document-handoff save after `e4c8e62`. Recheck branch history and upstream
status for publication; no PR/merge or normal-media change was requested.
The local writable Screen 7 manual copy is
`build/notepad-84/manual-DfNCgT/NOTEPAD.IMG`; commands and checklist are in the
handoff document. The reference fixtures and the user's unrelated files stay intact.

Read [UNIFIED-NOTEPAD-HANDOFF.md](UNIFIED-NOTEPAD-HANDOFF.md) first: it contains
the current private images, build commands, exact limits and test evidence.

- Actual private File Manager document double-click → unified Notepad works.
  Shared resident transaction binds a copied path/name to the allocated owner
  generation, rejects other adopters, and expires on launch failure/return or
  owner cleanup. Filesystem API v3 uses existing operations 12/13, identity 15;
  outer ABI stays 2.1. Normal MSX/CPC profiles remain API v1.
- `PORTABLE_FS_HANDOFF` requires IDENTITY and PACKAGE_STREAM. Pair the v3
  GBFSCTX module with `GBV4,6` and `GBWM,0x56/0x57` private modules. The private
  File Manager enables `GB_FSCTX_LAUNCH`, checks FS API >=3, and omits the native
  shell client. Default distribution builds keep the native route.
- Notepad adopts before registering, uses the copied identity and existing
  staged load, then publishes title/path only on success. No 4-KiB capacity
  reduction or widened limit. APP 18697 bytes, SHA `922b0e5c…9d01e05f`;
  primary end `785C`, DATA `7870`, BSS end `7EF4`. Child Screen 7 has 14 bytes
  spare. Root snapshot mirror now follows wire order; dirty byte is offset13,
  not17. Updated runtime observers require matching new APP/symbol files.
- 50 regressions pass. openMSX Screen6/7 edit/save/reopen with 189/185 exact
  secondary returns. 1983 real same-name/different-directory opens and saves,
  failed CRC launch then blank launch, full-capacity/oversize and cleanup pass.
  Input uses joystick trigger for 1983; known keyboard Space timing remains.
- Next: existing-instance exact-path delivery/reuse with dirty confirmation,
  configuration reload and remaining input/UI qualification. Each private
  File Manager open currently starts a new editor. Do not call reuse complete
  or promote these images to normal MSX/CPC distributions yet.
- Explicitly sync changed **and untracked new** sources into
  `build/notepad-84/`; it is not an automatic mirror. Preserve prior evidence,
  normal images, the user's two GIFs and untracked `QA/CPC/`.

## Previous resume point — Desktop handoff foundation (2k), 2026-09-13

User requested **save progress (commit/push) and go to next step**. Checkpoint
2j (including sealed calls) is now committed/pushed as `e4c8e62` on #84's
`feature/84-unified-notepad`. The subsequent work below is local/uncommitted;
no PR/merge or normal-image changes.

Read [UNIFIED-NOTEPAD-HANDOFF.md](UNIFIED-NOTEPAD-HANDOFF.md) for the new
optional filesystem API-v2 identity query, evidence, private probe images,
and exact launch-transaction work still needed. **This is not yet a document
double-click implementation.** Existing Notepad remains the accepted 2j binary.

- Shared optional `FSCTX_IDENTITY` policy adds operation 15: owned/stale-checked
  60-byte copied drive/name/path, no target-file I/O or context/cursor mutation.
  SDK `gb_fsctx_identity` checks advertised FS API >=2 and preserves output on
  failure. `UNIVERSAL_FS_IDENTITY=1` links it; existing clients stay unchanged.
- `PORTABLE_FS_IDENTITY=1` enables both private MSX gate/sysinfo and module.
  Default FS module remains byte-identical (2024 bytes); v2 uses 2255 bytes.
  Default MSX/CPC API v1 profiles remain unmodified in behavior.
- 48 regressions pass; openMSX Screen 6/7 has 54 APP checks/50 preserved
  parameter returns per run; 1983 passes three real Desk launches per mode,
  cleanup and independent disk readback. New probe hash/paths are in the doc.
- Existing Notepad rebuilt byte-for-byte to `d944f456…e495b3c3` (18684 bytes).
  Do not stage the new filesystem probe as Notepad. No app functionality was
  reduced, no limits loosened, no sibling emulator sources changed.
- Next: exact-path producer/recipient launch transaction, pending rollback,
  then Notepad adoption/load/title integration with measured primary savings.
  Existing `prepare_launch/adopt_launch` lacks recipient binding and failed
  launch cleanup; native File Manager does not call preparation. A paged FS
  call can also change the native directory entry that `GB_WMLAUNCHAS` uses.
  Avoid a superficial prepare-before-launch patch that ignores these facts.
- Sync changed sources explicitly into `build/notepad-84/` before builds.
  Preserve normal images, evidence, user GIFs and untracked `QA/CPC/`.

## Previous resume point — checkpoint 2j, 2026-09-13

Latest user request: **save progress (commit/push) and go to next step**.
Remain on #84 / `feature/84-unified-notepad`. This checkpoint records the
sealed-call service and actual editor split after `86d93fb`; save/push it before
starting Desktop document handoff. No PR/merge or normal-image replacement.

**Actual Notepad is now privately runnable, but the sprint is not complete.**
Read [UNIFIED-NOTEPAD-RUNTIME.md](UNIFIED-NOTEPAD-RUNTIME.md) first for source,
build profiles, exact memory fit, evidence, limitations and manual commands.

- New `protocol.h`, `client.h`, secondary model and `build_unotepad.sh`; full
  4096-byte document plus independent transactional staging in the computation
  bank. Primary owns UI/FS/chooser/clipboard, with exclusive borrowed scratch.
- Complete APP 18684 bytes, SHA `d944f4565d4869d93f361b774fa38dbd657651878f8210133555b48de495b3c3`.
  Primary image ends `784F`, DATA `7870..7EF4` (12 bytes before `7F00`);
  secondary image ends `50AD`, DATA `5E00..7E21`. Kernel layout stays unchanged.
  Extra features need real savings, not relaxed boundaries.
- SDK opt-ins: compact IX frames with preserved generated kernel wrappers,
  minimal helper linkage, borrowed 768-byte popup storage. Defaults remain
  unchanged. New chunked document helper retains the original job/FS contract.
  FS transfer scratch aliases the copied model packet; never read it after an
  FS call without first saving any needed result (BASIC completion is handled).
- 61 final focused tests pass, no skips; ABI/package/MSX layout checks pass.
  `editor-final-suite.log` and `editor-final-{abi,package,layout}.log` in evidence.
  New host cases include malformed stage/export requests, 4-KiB no-mutation
  failure, long-line text splitting and a zero-returning filtered-arrow queue.
- OpenMSX Screen 6/7 real small-file round trips pass in
  `editor-openmsx{6,7}-polled.log` (189/177 exact computation returns).
  1983 Screen 6 keyboard-pointer boundary run passes 50 checks;
  Screen 7 joystick-trigger boundary run passes 59 checks. Both round-trip
  4096 exact bytes and reject 4097 while retaining the old document.
- **Do not lose the failing input case:** 1983 Screen 7 Space-as-click can add
  a stray character before close. Bounded queue draining fixes queued startup
  keys/filtered arrows but does not prove the poll/BIOS timing race solved.
  Passing joystick tests are distinct evidence. No sibling emulator edits.
- Local bridge adds a real joystick command and explicitly opt-in writable
  images. `test_notepad_1983.py` always copies the supplied image first. The
  original bridge's default stays read-only. New bridge hash and input coverage
  are recorded in the runtime document; don't reuse the old read-only binary
  for save tests. `stack_max=0` is not a measured root-stack high-water result.
- Current private image paths: Screen 7
  `build/notepad-84/build/msx/portable-notepad-7-4zhwnl2g/filesystem.img`, Screen 6
  `build/notepad-84/build/msx/notepad-runtime-6/filesystem.img`. Test-only
  CLOCK alias launches Notepad through Desk; NOTEPAD.APP contains the same app.
  Preserve these evidence images and copy before manual writes.
- **Next:** Desktop exact-name/path handoff and configuration contract;
  remaining input discrepancy; full-document latency/stacking/clipboard and
  openMSX boundary/failure/BASIC checks. `gb_fsctx_adopt_launch` allocates the
  context but does not return all title/chooser metadata. Do not add native
  mailbox reads to the portable app. All-newline 4-KiB BASIC can save as 8 KiB,
  exceeding the current raw load cap: qualify/resolve, not silently ignore.
- Explicitly sync sources into `build/notepad-84/`. Preserve normal QA image
  hashes, user GIFs and untracked `QA/CPC/`. Existing failed logs are retained.

## Previous resume point — checkpoint 2i, 2026-09-13

Latest request: **commit and push and continue**. Committed/pushed the loader
checkpoint as `86d93fb` on `feature/84-unified-notepad`. Subsequent sealed-call
work is local, not yet committed/pushed. No PR/merge or normal image changes.
Continue the consolidated sprint on #84, without re-proposing internal tasks.

The computation-only call gate/restricted SDK now works on private MSX,
confirmed in openMSX and 1983 Screen 6/7. **Actual Notepad is not runnable yet.**
See [checkpoint 2i](PORTABLE-SECONDARY-CODE.md#checkpoint-2i--sealed-computation-calls-2026-09-13)
for code, memory, ABI, evidence, build commands and retained failed runs.

- New shared sealing/call core plus optional page/owner-release hooks; MSX
  binding publishes only after full CRC/close. Eight-byte per-owner seals
  include owner/page generations and validated entry/length. GB_PARAMS op 11
  copies 1..512 bytes and restores primary before copy-out; nested/worker/
  stale calls reject. The fixed root stack and caller IFF/lock are preserved.
- Restricted C startup/SDK uses `build_usecondary.sh`, `gb_compute()`,
  `UNIVERSAL_COMPUTE=1` and a matching payload audit. The new capability
  `0x04000000` is opt-in only; normal MSX/CPC profiles do not advertise it.
  No UI, FS, timers, callbacks, kernel calls or banking in the secondary.
- Modules: GBAPV4 v5 3014; GBPKWM 1496 (mode signatures `46`/`47`), fixed
  seals `2180`, state `21C0`, trusted bind record `21D0`, ends `21D8` before
  `2200`. GBPKFIX/GBPKLOAD stay 1061/747; child sizes stay 14534/16112.
  Calls reuse fixed FS transfer scratch `C400`; no filesystem inside leaf.
- Executable COMPUTE probe: 54 app checks per generation; three generations
  on each emulator/mode; same APP hash recorded in the checkpoint. Includes
  initialized data, 4-KiB BSS, first-call reset and retained state. openMSX
  checks 66 parameter returns/mode and live seal persistence/reclamation;
  1983 checks exact live identities/code/pools and unchanged private media.
- Shared fixture: 1058 operations, 1024 maps, 4659 delivered secondary IRQs
  at each low/high layout. An important new regression uses half-page tables:
  RASM rounded `SEC_TABLE/256` into the next page; use `SEC_TABLE >> 8`.
  The 1983 live-table observation caught this after app-only checks passed.
  Keep all failed logs; no sibling emulator or firmware edits were made.
- Final focused suite: 59 tests pass with no skips in
  `build/notepad-84/evidence/secondary-call-suite-accepted.log`; ABI/package and
  low-RAM checks pass. Normal MSX/CPC/Desktop/runtime image hashes remain
  exactly those recorded at the previous checkpoint.
- **Next internal task is actual editor partition/integration.** Existing
  `apps/unotepad/editor.h` is pure model code. Move its 4-KiB document and
  transactional staging behind bounded copied commands; primary keeps UI,
  FS/chooser/clipboard/config/Desktop handoff. Avoid simply retaining another
  full 4-KiB primary scratch if it prevents fitting. Preserve all-or-nothing
  failed load/paste/save semantics. Existing host editor tests still apply.
  Measure both complete linked images/data/stack, then exercise actual
  open/edit/save/reopen, recovery, focus/drag and responsiveness in both
  MSX modes/emulators. Full CPC receiver/editor delivery follows.
- Sync sources explicitly into `build/notepad-84/` before building. Private
  final Screen 6/7 probe images: `build/msx/portable-compute-6-v7du_410/` and
  `portable-compute-7-musp_pfn/` inside that worktree. They replace CLOCK with
  COMPUTE for real Desk input, **not Notepad**. Preserve normal QA images,
  user GIFs and untracked `QA/CPC/`.

## Previous resume point — checkpoint 2h, 2026-09-13

The user said to start the consolidated runnable-MSX Notepad sprint. Continue
on #84, `feature/84-unified-notepad`; do not ask for a new milestone/approval
between its internal tasks. **Normal two-bank Desktop loading is now implemented
and qualified in private MSX Screen 6/7 images. No callable secondary service
or runnable unified Notepad exists yet.** No normal images changed. The user
has now requested committing/pushing this loader checkpoint before continuing
with the secondary-call task; the checkpoint commit records the work since
the earlier pushed save `5437384`.

- Current source and evidence are detailed in
  [checkpoint 2h](PORTABLE-SECONDARY-CODE.md#checkpoint-2h--normal-msx-streamed-launch-2026-09-13).
  `kernel/msx_app_launch.asm` adopts the existing resolver's descriptor after
  its first 256-byte read, supplies the cached prefix once and preserves the
  chosen file through full-stream CRC/close. Shared WM publication/rollback is
  used; early guards protect worker/pending/active/poisoned contexts.
- Opt-in flags remain `PORTABLE_DATA_PAGES=1 PORTABLE_PACKAGE_STREAM=1`.
  Current modules: GBAPV4 v4 2996 bytes; GBPKFIX v3 1061; GBPKLOAD v2 747;
  new mode-specific GBPKWM 380, emitted by matching kernel assembly. Its
  fixed `1C00..2200` reservation reuses only MSX's unused FDC-directory tail;
  backdrop scratch is capped at `1C00`, bulk scratch starts at `2200`.
  Do not use `3C00..3E00`: some native paged helpers still reach that area.
- Child COMs are 14534/16112 bytes, **16 bytes spare in Screen 7**. The route
  module uses 380 of its 1536 reserved bytes; CRC/extra/state slots remain
  strictly below `D400`. There is no permission to loosen APP/stack bounds.
- Full two-bank load takes 468 PAL ticks (9.36 s), so pointer-only progress
  is essential. CRC/read/clear callbacks call existing input/movement/cursor
  leaves, never `k_poll`, menus, clock repaint or application callbacks.
  openMSX maximum pointer-progress gap is 5/4 ticks (Screen 6/7). Loading is
  still synchronous, not a new background scheduler feature.
- openMSX: three successful launches per mode with exact banks/tail/pool and
  401 preserved parameter returns; badCRC/truncation/extra-byte files reject
  three times each with one open/close, no entry and exact rollback. Ordinary
  primary-only PAGEPRB retains 407 service-return checks per mode.
- 1983: identical APP, three generations on Screen 6/7, 352/361 observations,
  exact banks/tail/pool and unchanged disks. In-flight pointer tests record
  78 changes in 100 frames, max gap four frames. Ordinary Clock/Calculator
  also pass three lifetimes per mode (82/109 checks), including ticking-Clock
  pointer cadence. These are core/keyboard-input runs, not SDL mouse tests.
- Final host/Z80 suite: **55 tests pass, no skips** in
  `build/notepad-84/evidence/sprint-launch-final-tests.log`. ABI/package checks
  pass; low-RAM inventory now includes all opt-in code/state reservations
  (55 ranges, nine documented overlays), with assembler guards for the actual
  module ends and unchanged public boundaries.
- Successful private packages: `build/notepad-84/build/msx/portable-data-pages-7-ijn4r1wi/`
  and `portable-data-pages-6-5ndm_qjx/` alongside it. They alias PAGEPRB as
  CLOCK, **not Notepad**. `probe.APP` SHA256 is
  `2000485837e7e8fe8190936e4209d3b748932cb1b2d4517b7503e09aedaf7305`.
  New fixtures retain matching `probe.noi`; use `--app`/`--symbols` with the
  1983 driver rather than a subsequently rebuilt worktree's link symbols.
- Preserve failed logs. The 1983 discrepancy was a test-driver overshoot:
  its third intended Clock-row click actually selected `CALC.APP` (confirmed
  by read-only trace). `Driver.move` now rechecks coordinates after key release;
  host regression covers it. No emulator/firmware changes were necessary.
- **Next internal task:** implement owner/page-generation/entry seals and
  copied, non-nested computation-only secondary calls with bank/stack/IFF
  restoration and teardown; add the restricted SDK/audit profile. Then split
  the real Notepad model/state into the secondary, retain the 4-KiB document
  and primary UI/filesystem, and qualify the actual editor in openMSX/1983.
  `APP_SECONDARY` is packaging support only. No public secondary call opcode
  or new capability has been published. Full CPC delivery remains afterward.
- Explicitly sync source into `build/notepad-84/` before building there. Do
  not overwrite its evidence or normal QA images; preserve user GIFs/QA/CPC.

## Previous resume point — checkpoint 2g, 2026-09-13

Continue #84 on `feature/84-unified-notepad`. The dual-admission/fixed MSX
module composition now boots in private Screen 6/7 builds, with unchanged
application/stack bounds. **No normal WM launch calls the stream loader yet;
no runnable unified Notepad exists.** Normal images are untouched. Changes
since pushed save `5437384` are local, not newly committed/pushed.

**Planning update, 2026-09-13:** the user requested consolidating the remaining
three implementation steps into one sprint. Use the
[runnable MSX Notepad sprint](UNIFIED-NOTEPAD.md#consolidated-sprint--runnable-msx-notepad)
as the current delivery unit: connect normal streamed launch, enable validated
secondary calls, integrate/test the actual editor and provide a private image
with manual instructions. The internal tasks remain ordered; do not repeatedly
re-propose them as separate sprints. Full CPC qualification and normal release
replacement follow. This planning update changes documents only, not the
checkpoint's implementation status, and does not authorize publication.

- `PORTABLE_DATA_PAGES=1 PORTABLE_PACKAGE_STREAM=1` selects the new profile.
  `tools/build_msx_package_modules.py --out PRIVATE_DIRECTORY` builds
  GBAPV4 v3 (2996 bytes), GBPKFIX (1061), GBPKLOAD (757). The low transaction
  occupies `0100..03F5`; helpers/state reuse `CFDB..D100`, CRC `D2EC..D39F`,
  admission state `D3F0..D400`. IRQ still ends exactly at `CFDB`; existing
  data-page code remains `D100..D2EC`. Defaults still use the old module set.
- Ordinary admission resets the stream mode and validates full primary CRCs;
  the separate stream entry checks structure only, followed by package CRC
  and close in the existing transaction. Shared dual fixtures pass at both
  layouts, including stale-mode/invalid-primary cases. Do not use the
  structure-only entry as permission to run primary code.
- **45 focused tests, no skips**, ABI and package checks pass. Log
  `build/notepad-84/evidence/package-modules-regression-20260913-final.log`.
  Includes 39 boot fault/header/size cases, six exact-capacity EOF checks and
  mapped-Desktop/fail-closed observer coverage. File-load faults here are
  instruction stubs, not injected faults on real Nextor media.
- openMSX Screen 6/7: three ordinary PAGEPRB lifetimes, 148/150/150 app checks,
  407 parameter returns each. 1983: same APP, 37/46 lifecycle observations,
  exact teardown/guards and unchanged disks. Evidence and failed-run notes:
  [checkpoint 2g](PORTABLE-SECONDARY-CODE.md#checkpoint-2g--dual-admission-and-fixed-msx-boot-2026-09-13).
  These prove module boot/coexistence and relocated primary CRC, **not calls
  to the fixed stream entry**. Preserve 2f's standalone transaction evidence.
- Screen 6/7 child sizes: **14505/16083 bytes**; only **45 bytes** remain in
  Screen 7's `3F00` envelope. New routing needs measured refactoring, not
  relaxed limits. The opt-in legacy bounded EOF probe now accepts C7/zero,
  but still rejects C7/nonzero or other errors. Normal builds are unchanged.
- **Next:** integrate normal current/strict and boot/browse path resolution,
  one-open handling and pending-owner WM routing through the fixed stream
  module. `kernel/core/app_launch.asm` is not modified yet. Retain primary/
  native compatibility, test actual two-segment success/failure/teardown and
  pointer latency, then implement the sealed call gate and partition Notepad.
  These implementation tasks now form the single runnable-MSX sprint above;
  CPC stream integration and full delivery acceptance follow it.
- Private worktree `build/notepad-84/` is retained. Explicitly synchronize
  changed source into it before using its full-kernel diagnostic builders;
  it does not automatically track root edits. Never replace normal QA images
  while using these diagnostic aliases. Preserve user GIFs and `QA/CPC/`.

## Previous resume point — checkpoint 2f, 2026-09-13

The user resumed #84 on the same branch after save commit `5437384` was pushed.
This turn implements the optional `PKG_ALLOW_IRQ=1` profile and
`kernel/msx_package_stream.asm` (single-open Nextor leaves). They are **not
installed in either normal receiver**; no new unified Notepad is runnable.

- 42 focused tests pass, including IRQ/fault matrices at two fixed-state
  layouts and the fail-closed observer regression. ABI/package checks pass.
- Standalone Nextor diagnostic passes in openMSX (345 observations, six cases,
  exact bank bytes/tail and open/read/close counts) and the existing read-only
  1983 bridge with corrected RainBIOS (same disk, six guest cases). It has no
  Desktop or installed scheduler: BIOS ticks advancing does not qualify root
  pointer responsiveness. No secondary code executes.
- Evidence: `build/notepad-84/evidence/stream-checkpoint-20260913-tests.log`,
  `stream-nextor-openmsx-20260913-eof.log`, and
  `stream-nextor-ph9009o_/1983-result.json`. Preserve earlier failures; the
  initial observer's PASS was invalid (zero completed cases), corrected and
  regression-tested before acceptance. Actual Nextor EOF is `C7` with zero
  bytes; only that combination is normalized by the new adapter.
- Transaction 749 bytes; MSX provider 173; fixed state 22+3; scratch 512.
  Measured candidate placements and the remaining 22-byte admission overrun
  are documented in [PORTABLE-SECONDARY-CODE.md](PORTABLE-SECONDARY-CODE.md).
  Candidate spans are not a complete linked receiver or installed allocation.
- **Next:** integrate normal MSX path resolution/single open, fit and install
  the components while retaining both primary-only/native and streamed
  admission, then test real Desktop launch/rollback and input latency. Keep
  the shared policy; CPC streaming and the sealed call gate still follow.
  Do not restart the qualified fixtures or mistake the DOS diagnostic for
  a finished loader milestone. Normal media hashes still match below.
- Changes in this resumed checkpoint are local; no new commit/push/PR/merge
  was requested. The prior September 9 pause and allowance estimate below
  are historical, not a fresh limit or instruction to stop the resumed work.

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

## Earlier checkpoint — shared secondary stream core qualified; receivers next

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

**Historical checkpoint 2e next action (see current 2g above): bind the shared streamed loader to measured MSX/CPC layouts and single-
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
  of resuming. The September 9 save's commit/push was explicitly authorized;
  this note grants no standing authority for later publication, cleanup, new
  issues, PRs, merges or releases.
