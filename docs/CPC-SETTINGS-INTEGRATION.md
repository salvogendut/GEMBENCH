# CPC application parity — shared Settings

Started 2026-09-08. Issue [#79](https://github.com/salvogendut/GEMBENCH/issues/79),
branch `feature/79-cpc-settings`, based on `68b1607`.

## Agreed order

1. Accept, commit, push and merge the four-sprint desktop checkpoint. **Done:**
   commit `80800be`, [PR #78](https://github.com/salvogendut/GEMBENCH/pull/78)
   merged as `68b1607`; issue #77 closed.
2. Resume application parity with the **existing shared Settings application**,
   starting from [W2-A's dependency audit](CPC-RESTART-STEP3D-W2-A.md).

This is not a new CPC Settings implementation or a universal binary conversion.
`apps/settings/main.c` remains shared with MSX. The CPC profile uses its existing
selectors and bounded asynchronous picker, with an explicit native provider.
The normal MSX provider and complete MSX feature set remain the default.

## Qualification gates

### A. Owned provider and complete native link

Implemented; host and target-link checks are recorded below. No launch
permission, desktop menu or QA media change is part of this gate.

- Six appearance rows: font, icons, cursor, title bar, gadgets and backdrop.
  Palette, wallpaper, screensavers and full reset remain unavailable; they
  must not silently use retired RAM or unsupported services.
- One caller-owned filesystem context on the existing M4 volume, independent
  of File Manager's browse state. The facade supports only the required root
  and `/GBENCH` paths. Context exhaustion and I/O failures remain visible;
  closing the application releases its context.
- Icon filtering reads a **16-byte header into app-owned storage**, not the
  old **6,656-byte buffer at `0x2200`**, which overlaps live CPC memory.
- At most 16 filenames plus `SOLID`: the worst-case prefixed label list is
  **182 bytes**, inside the real native popup's **232-byte** text buffer.
  Existing per-frame enumeration/filtering limits are retained.
- Save/apply calls the existing W1 verified-persistence service, which itself
  reuses the shared Settings edit block. The app copies published config only
  after success. It has no legacy best-effort `gb_fs_save` or direct transfer-
  name/reload path. This is not an atomic rollback guarantee: a later reload
  failure may follow a successful write, so the UI reports a failed change,
  not an assertion that the disk was untouched.
- Explicit managed title/close/move descriptor; the shared window manager
  owns dragging. No app-side software drag or idle full-window damage path.
- Full SDCC link against the composed runtime's actual bindings, not dummy
  service stubs. All sections, helpers and data must fit below the unchanged
  `0x7F00` snapshot boundary. Unknown app dependencies, ABI-cell drift and
  insufficient popup capacity stop the build.

Run with the project toolchain in `my-distrobox`:

```sh
make diagnostic-cpc-settings-link
python3 -m unittest discover -s tests -p 'test_settings*.py' -v
```

Outputs are private: `build/cpc-settings-link/SETTINGS.native.bin` and
`report.json`. A successful link is **not a runnable/admitted APP**. The
builder neither stages media nor enables a loader exception.

### B. Private M4 launch and persistence qualification — complete

This records the private qualification before normal-image promotion. The
current delivery state and manual-test instructions are in Gate C below.

Implemented in `cpc-settings-m4-private-v1`, under
`QA/Diagnostics/CPC-settings-contract` and `build/cpc-settings-contract`:

- Exact-name `SETTINGS.BIN` admission with checked native length/CRC, sharing
  File Manager's validator. Missing, short, corrupt and unbound candidates are
  rejected before execution. Other APPs retain universal admission. CRC is a
  build/corruption guard, not a security sandbox.
- The real shared Desktop adds System > Settings only in this explicit
  profile. Launch is deferred until the modal menu repaint ends. The normal
  delivered System menu is unchanged.
- Automated input through `../1984` on disposable M4 cards: all six appearance
  changes, cancellation, close/reopen and a cold boot of the saved card. Each
  checkpoint checks exact composed pixels, pointer/theme/font integrity,
  context ownership, page accounting, stack guards and actual saved config.
- A mixed-window sequence keeps File Manager, seconds-enabled Clock and
  Calculator open while Settings saves, moves, changes focus and closes. It
  checks File Manager's independent browse state and complete cleanup.
- Removing `GBEDIT.MOD` exercises a real rejected save: visible error, no
  config publication or disk mutation, and context recovery.

The app-driven storage-fault/stress matrix and final combined regression pass;
see the evidence below. Keep this profile separate until delivery integration
and manual acceptance pass. Provider-only checks do
not substitute for this application's M4 launch/modal lifecycle.

Run with the project toolchain in `my-distrobox`:

```sh
make diagnostic-cpc-settings-image
python3 tools/test_cpc_runtime_1984.py --settings-case normal --skip-build
python3 tools/test_cpc_runtime_1984.py --settings-case mixed --skip-build
for scenario in missing short corrupt unbound edit-missing; do
    python3 tools/test_cpc_runtime_1984.py --settings-case "$scenario" --skip-build || break
done
for scenario in empty-icons malformed-icons long-backdrops directory-error \
    read-error config-oversized config-nul config-full write-denied \
    readback-error contexts stress; do
    python3 tools/test_cpc_runtime_1984.py --settings-case "$scenario" --skip-build || break
done
```

`normal` automatically cold-restarts its saved card. Logs, snapshots, crops
and `result.json` are retained under `build/settings-runtime`. Tests do not
inject RAM, change the emulator, use floppies or touch accepted cards.

For an exploratory manual run of the private image (not delivery acceptance):

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config="$PWD/QA/Diagnostics/CPC-settings-contract/1984.conf" \
  --6128 --memory=512 --autostart=BOOT
```

Use the existing keyboard/joystick pointer and Space to choose System > Settings;
Escape cancels a selector or closes Settings. Rebuild the private image before
automated checks if a manual run saved changes. During B, `tools/run_cpc.sh` and
`make cpc` still selected the accepted desktop without Settings; C changes that.

### Bugs caught while qualifying B

1. Settings' legacy content fill overwrote native side/bottom borders. This
   appearance profile now paints only inside the managed frame.
2. Settings saves `STEM.EXT`, but the old font/icon/cursor parser copied the dot
   into its eight-byte stem: `ALTERN.FNT` became the lookup `ALTERN.FFNT`.
   The private profile enables extension-aware parsing for those three keys;
   the legacy/MSX parser remains unchanged.
3. Verified reload can repaint and re-show the software pointer. Settings
   now re-hides it before the final value repaint and brackets error recovery.
4. The mixed-window close exposed an interrupt race in the legacy SDK's
   one-byte stack arguments. `_gb_icon` used `POP HL; DEC SP`; an IM1 interrupt
   between them changed File Manager's return from `0x51A7` to `0x5173`.
   Execution eventually fell into the old boot loader. The existing 1984
   instruction-ring trace confirms the interrupted sequence. The private
   profile now generates safe reads for fill/frame/icon/icon-half wrappers:
   read the byte before advancing SP. No interrupts are disabled and the ABI
   is unchanged. A host stack-boundary model reproduces the original failure
   and checks every replacement instruction boundary; it is not presented as
   a Z80 emulator. The real runtime regression is the M4 mixed-window test.
5. The full backdrop picker constructed **17 labels** (16 stems plus `SOLID`),
   but the native GBUI dispatcher admitted only 16, so that selector silently
   cancelled. The private Settings UI now uses `GB_UI_POPUP_MAX=17` in both
   request validation and its pointer array. The default remains 16 for other
   builds. The shared host dispatcher tests both limits and the last valid
   selection; M4 checks scrolling down/up, cancellation and selection with
   more than 16 available backdrop files.

The wrapper opt-in covers private Desktop, File Manager, Settings and UI
modules. Default CPC/MSX generation is deliberately unchanged at this gate.
Carry the fix into delivered CPC with C; separately audit the legacy/MSX
wrappers rather than assuming this race is CPC-specific.

### B storage-fault/stress evidence — 2026-09-08

**12 additional scenarios / 222 pixel-checked checkpoints passed** on disposable
1984 M4 cards. Each checks exact composited pixels, pointer/code integrity,
live versus saved config, context ownership, released storage claims, page
accounting and guarded stack use. The repeated lifecycle case runs eight
cycles of all six selectors, cancellation, close and reopen (81 checkpoints).

| Case | Expected outcome | Evidence under `build/settings-runtime/` |
| --- | --- | --- |
| `empty-icons` | No-files dialog twice; icon-free Desktop fallback; cleanup | `geobench-cpc-runtime-b_p215o5/result.json` |
| `malformed-icons` | Short header, bad magic and wrong icon count excluded | `geobench-cpc-runtime-1ojoi9gf/result.json` |
| `long-backdrops` | Capped 17-label popup; scroll both ways; cancel/no-op selection | `geobench-cpc-runtime-kc4olke4/result.json` |
| `directory-error` | Overlong FAT directory response rejected; repeat/recover | `geobench-cpc-runtime-9cn_yu6e/result.json` |
| `read-error` | Asset-open error reported; retry and unrelated selector recover | `geobench-cpc-runtime-b934kmme/result.json` |
| `config-oversized` | 513-byte config rejected at boot; app exits cleanly | `geobench-cpc-runtime-883n6i62/result.json` |
| `config-nul` | Embedded-NUL config rejected by Settings; app exits cleanly | `geobench-cpc-runtime-8aq6jgf1/result.json` |
| `config-full` | 512-byte config loads; growth rejected without mutation | `geobench-cpc-runtime-x8fr396p/result.json` |
| `write-denied` | FAT read-only config rejects write; old live/disk bytes retained | `geobench-cpc-runtime-xye50wb0/result.json` |
| `readback-error` | Successful write, failed verification; disk changed, live config retained | `geobench-cpc-runtime-ta8xs33o/result.json` |
| `contexts` | Four live contexts reject save/fifth app; freeing one permits save | `geobench-cpc-runtime-kvf7rdjj/result.json` |
| `stress` | Eight selector/lifecycle cycles; complete cleanup | `geobench-cpc-runtime-q6d864wx/result.json` |

Fault provenance is explicit. Most cases modify only data/attributes on the
unmounted private copy. `read-error` links a **test-only Settings FS client**
that redirects the enumerated `BROKEN.IST` to an absent file at open time;
the real M4 FOPEN error exercises the unchanged Settings/provider recovery.
Only that copy receives the matching native length/CRC contract.
`readback-error` links a **test-only GBEDIT FS client** that preserves the real
M4 write/read but flips a byte in the verification reply. Production clients,
the emulator and guest RAM are not patched. This is deterministic error-path
qualification, not a claim of hardware card-removal/power-loss testing or
atomic rollback. The reader rejects the mismatch without publishing it;
the successfully written file remains on disk, as expected.

Malformed config currently produces the Settings initialization notice,
followed by the existing Desktop launch-failure notice when focus returns to
Desktop. Both dismiss and leave no resources behind. The first harness attempt
incorrectly waited for root turns between these two modal notices; that was
an observer error, not a CPC hang. An initial empty-icons oracle also wrongly
expected default artwork after both icon files had been removed. Failed
attempts are retained; only the passing paths above count as evidence.

Logs: `build/settings-gate-b-*.log`, with `final-config-*` for the final config
cases. No normal delivery image was rebuilt. All expected FAT payloads in the
completed test cards were independently read back and hash-checked, including
unchanged non-config files and deliberate fixture substitutions. The harness
also records `payloads-before.json` and checks them on subsequent runs.
The added automatic audit was smoke-tested with the missing-Settings case:
all 43 remaining/fixture payloads pass (`build/settings-gate-b-payload-audit.log`).

`make check` passed again: **279 Python tests, no skips**, plus the remaining
native/SDK/ABI checks (`build/settings-gate-b-check.log`). The focused native
UI tests also pass after adding the 17th-row regression. A fresh default/MSX
GBUI build is **byte-identical to `68b1607`** with matching build identity:
6,063 bytes, SHA-256
`38d1d1e37055f3ca70a68a78bf1c0b4a5b52e9aeebdd1876fb8f1a0ce27835a7`.
The private GBUI remains **5,604 / 6,144 bytes**, SHA-256 of its padded module
`36fbdb085578b46c04095702cce08945e2ae02c3077709ba8f9615df7b787f52`.
Maximum observed stack across these cases: main **215/256**, IRQ **4/256**,
temporary **0/128**; all guards intact. Combined-app regression evidence below
also exercises the temporary stack.

### C. Delivery and acceptance — qualified and manually accepted

`make cpc` now builds **`cpc-desktop-m4-v3`**, including the same six-row Settings
application and System menu used in B. Its native admission contract, interrupt-
safe wrappers, extension-aware parser and 17-label popup limit are unchanged.
The delivery validator checks both File Manager and Settings contracts and
rejects Settings in older delivery profiles. It does not turn native system
binaries into portable APPs or bypass admission for other applications.

The normal M4 image contains **34 files**, all independently read back from FAT
and matched to its manifest. **32 payloads remain byte-identical to B**; Clock
and Calculator use the corrected universal SDK described below. Diagnostic APPs, test directories,
extra test fonts/cursors and injected fault clients are excluded. The regular
build uses `build/cpc-desktop` and `QA/CPC-Desktop`, leaving private diagnostics,
parked `QA/CPC` and MSX media alone.

Before rebuilding, the complete previous manual card directory and corresponding
build outputs were copied to **`build/cpc-settings-delivery-backup-Yj4zsp/`**:
`CPC-Desktop/` and `cpc-desktop-build/`. The backed-up image was byte-compared
with the original; SHA-256 remains
`802bfca53dbf15010ddbd056ca8a443d7902bf8ac9ddbe40c0f83acf8c4d7e05`.
This is a local backup, not an archival Git branch; its old emulator config
still names the normal image path, so it is a restore backup, not a launcher.

New manual image: `QA/CPC-Desktop/GEOBENCH.IMG`, SHA-256
`2edf0e72ab0954ebf98eb03c6b34f43adc43fe72efcd6796fbaeeadc15d313ee`.
The combined gate now includes **28 scenarios**: the 20 Desktop/File Manager,
stacking, cadence and admission checks, plus Settings save/reboot, mixed-window,
context-exhaustion and rejected-load/editor cases. Settings delivery tests use
only shipped assets; the B-only injected storage clients cannot be selected
as normal-image acceptance cases. All tests run on disposable M4 copies.

#### C regression follow-up: universal SDK interrupt safety

The first combined run passed 27/28 scenarios but left five incorrect video
bytes in Clock's exposed seconds digit after Calculator moved. An independent
repeat passed, establishing timing sensitivity rather than a deterministic
glyph-clip failure. Both attempts are retained:
`build/settings-gate-c-delivery.log`,
`build/cpc-delivery-runtime/geobench-cpc-runtime-stsg_qy0/stack-calculator-drag.sna`,
and `build/settings-gate-c-stacking-repeat.log`.

Inspection found that universal builds still used the unsafe `POP HL; DEC SP`
byte read fixed for native clients in B. The actual SDCC `draw_seconds` saves
BC across `gb_fill`, with C holding the digit column. An interrupt in the
overshoot gap can replace that saved column with the high byte of the return
PC: fill has already succeeded, but subsequent text can be rejected as off-screen.
The instruction-boundary model now covers that saved-coordinate case. This
explains the symptom, but this run did not capture an instruction trace proving
that exact interrupt in the failing snapshot.

`build_uapp.sh` now unconditionally selects the same interrupt-safe generation
for **all universal targets**, without a platform define or ABI change. Native
MSX generation is unchanged; Clock/Calculator remain compile-once binaries.
The generated wrapper regression and deterministic tier-1 check prevent the
universal build from losing this opt-in. No compositor/oracle tolerance was
relaxed and no application source or glyph renderer was changed.

The rebuilt apps pass the actual Desk/Clock background lifecycle in openMSX
Screen 6 and Screen 7 (`build/settings-gate-c-msx6.log`, `...-msx7.log`). These
runs use `GEOBENCH_ACCESSORY_REBUILT_APPS=1` to copy just the rebuilt apps into
the existing disposable test card; the accepted MSX CARD and image are untouched.
The full **28-case CPC delivery gate passed** on the corrected image, including
**323 pixel-checked checkpoints**, saved-config cold boots for File Manager and
Settings, native/root rejection paths, resource exhaustion and mixed windows.
The independent stacking repeat passed all **32 checkpoints** too. Evidence:

- `build/settings-gate-c-final-delivery.log` and
  `build/cpc-delivery-runtime/geobench-cpc-delivery-_v8pxaj0/result.json`.
- `build/settings-gate-c-safe-stacking-repeat.log` and
  `build/cpc-delivery-runtime/geobench-cpc-runtime-dg0e7lak/result.json`.
- **285 host tests, no skips**, passed in
  `build/settings-gate-c-final-host.log`.
- All remaining `make check` components passed in
  `build/settings-gate-c-final-check-rest.log`, including deterministic universal
  app rebuilds, native/SDK/ABI and distribution checks. The final check was split:
  host discovery first, then `bash tests/run_gbr_reader_tests.sh` and
  `make -o gbr-check check` to avoid repeating that completed host suite.

The combined run's maximum stack use was main **210/256**, IRQ **4/256** and
temporary **6/128** bytes, with intact guards and cleanup checks. Cursor cadence
remained **50 steps/second** without seconds, **49.62** with focused Clock
seconds and **49.24** with background seconds. Maximum gaps were respectively
6, 10 and 9 IRQ ticks; minute rollover retained 50 steps/second and a 9-tick
maximum. Existing admission thresholds and pixel oracles were unchanged.
The source image/staging remained pristine after every disposable run.
Final Clock is **8,163 bytes**
(`efb1b136c57969f91eeef186118cfc8296af1a41410ab8ce13a2a63256050102`);
Calculator is **7,833 bytes**
(`0f4c3c7625ba4c904ca28663e392d80210fb933ae09a34f80795291d5086df65`).
Both still match the canonical universal build after the deterministic rebuild
and are the same bytes exercised on CPC and openMSX.

```sh
# Image is already rebuilt; launch without resetting saved settings:
distrobox enter my-distrobox -- bash tools/run_cpc.sh

# Rebuild + full disposable M4 regression (resets generated configuration):
make cpc-delivery-1984 CPC_TEST_JOBS=4
```

Manual acceptance checklist:

1. Choose **System > Settings** using the keyboard/joystick pointer and Space.
   Check the frame, focus and all six selectors; Escape cancels a selector or
   closes Settings. Font and cursor currently offer the shipped default only.
2. Try `DEFAULT` icons, `WEAVE` title bar, `IMPROVED` gadgets and `WAVES`
   backdrop. Check immediate appearance changes and cancellation. Reopen
   Settings, then restart the emulator **without rebuilding**, and check the
   saved choices persisted.
3. Keep Disk C/File Manager, seconds-enabled Clock and Calculator open while
   changing appearance, moving/focusing Settings and closing it. Check cursor
   responsiveness, exposed areas, window borders and retained Calculator input.

Palette, wallpaper, savers and reset remain outside this reduced profile.
Changes are saved in the image's `/GEOBENCH.CFG`; `CARD/` is build staging, not
the live M4 filesystem. Copy the image before rebuilding if saved preferences
matter. Save verification reports errors but is not an atomic rollback promise.
The user accepted the manual image on **2026-09-08** ("looks good") and
requested PR/merge of #79. No further implementation is required for this
appearance-only integration gate.

## Evidence and delivery state

The focused Settings suite passes **11 tests**, including the real shared UI
and CPC facade with host-owned device leaves, actual SDCC/native-helper link,
layout/capacity rejection and the unchanged full-feature unbound audit.
Host tests cover isolated browse state, context cleanup/exhaustion, failed-save
publication, picker cancellation/error recovery, header reads and popup bounds.
The actual W1 write/readback policy has its existing config-edit tests and the
app-driven M4 fault/stress qualification above. Three additional
stack-argument tests initially covered opt-in trampoline generation and the IRQ
gap; C expands them to five tests, including universal generation/caller data.

Current private native link: **6,743 / 14,336 bytes code**, **777 / 1,792 bytes data**,
including the provider, selector, filesystem client, UI and compiler helpers.
Data ends at `0x7B09`, below the unchanged `0x7F00` snapshot. The raw image's
SHA-256 is `a78160aa172b02c2b29b9d26eface2ecae50ceee0e1d6b9abba401c2a43c4edb`;
the bound contract is `571ac4e76e9d`. Kernel **15,821 / 16,384**, scheduler
**1,452 / 1,536**, Desktop **4,897 / 8,192**, File Manager
**13,383 / 14,336** bytes code. C delivers the same native components; Settings
is not a portable APP.

Fresh MSX builds are **byte-identical to merged baseline `68b1607`** in both
configurations, using the normal Settings recipe and project SDCC:

- Cooperative: 15,011 bytes,
  `150acb7b5a64558ac523b3a06d2c7e1209d3479a68bc1a9699dd9d4be0755221`.
- Preemptive: 15,276 bytes,
  `c08dd22060b83e23bfe77462ba5f522bb817359af526de962ccbd07d64d21387`.

The shared MSX preemptive Desktop object is also byte-identical to `68b1607`
(SHA-256 `dad99237d67c14048ff8ae0884a0727c80fd58c0a1d0739ba10502703688fa39`).
Evidence: `/tmp/geobench-79-settings-msx-final.log`,
`/tmp/geobench-79-desktop-msx.log`, and
`build/cpc-settings-contract/{settings_layout,native_layout}.json`.

Final private M4 profile: **20 scenarios / 316 pixel-checked checkpoints
passed**, including the 12 fault/stress cases above and these eight lifecycle,
persistence and admission regressions. Maximum stack use: main **215/256**,
IRQ **4/256**, temporary **6/128** bytes, with intact guards and full context/page
recovery. These are private Settings checks, not a normal-image acceptance.

| Scenario | Checkpoints | Evidence under `build/settings-runtime/` |
| --- | ---: | --- |
| Six live changes + cancel/reopen | 21 | `geobench-cpc-runtime-tn5hwhwv/result.json` |
| Cold restart with all six values | 9 | `geobench-cpc-runtime-xa94spjd/result.json` |
| File Manager + Clock + Calculator + Settings | 36 | `geobench-cpc-runtime-d9lp9vk2/result.json` |
| Missing Settings | 4 | `geobench-cpc-runtime-6z_cv7dq/result.json` |
| Short Settings | 4 | `geobench-cpc-runtime-9b721ntq/result.json` |
| Corrupt Settings | 4 | `geobench-cpc-runtime-sigoskf0/result.json` |
| Unbound Settings contract | 4 | `geobench-cpc-runtime-w9l2gu5j/result.json` |
| Missing edit module / save recovery | 12 | `geobench-cpc-runtime-j30_8dgz/result.json` |

Final logs: `build/settings-gate-b-*.log`. The earlier eight-case baseline is
retained in `/tmp/geobench-79-settings-{normal,mixed,rejection}5.log`.
The original mixed-window failure is retained in
`build/settings-runtime/geobench-cpc-runtime-h0pxfohn/reclose-trace2.log`.
Earlier normal/rejection passes did not qualify that faulty build. Final
**`make check` passed**, including **279 Python tests, no skips**, and all
subsequent native/SDK/ABI checks. Log: `build/settings-gate-b-check.log`;
the earlier baseline log remains `/tmp/geobench-79-fullcheck5.log`.
All **42 FAT payloads** in the pristine private M4 image also match its manifest
after the disposable runs. `git diff --check` passes.

The #79 implementation follows the merged desktop checkpoint (#78). Its
automated qualification and user acceptance are complete; the user requested
publication and merge on 2026-09-08.

Gate B preserved the then-accepted desktop, original runtime diagnostic and MSX
images. Gate C has since backed up/replaced only the normal Desktop image:

- `QA/CPC-Desktop/GEOBENCH.IMG`:
  `802bfca53dbf15010ddbd056ca8a443d7902bf8ac9ddbe40c0f83acf8c4d7e05`.
- `QA/Diagnostics/CPC-runtime/RUNTIME.IMG`:
  `cf9c77e1b277eecab608e6e7b8a19e332848fe1b3f34678cd89e2fb9135f48bd`.
- `QA/MSX/GBMSX.IMG`:
  `047a19d38e05f009df8c07a22be90e226a98bc68992fc7474c34015f251ce308`.

The parked `QA/CPC` and user recordings are also untouched. Settings is now in
the normal manual image; **Gate C's 28-scenario M4 qualification and manual
acceptance are complete**. No PCW, PAINT, BASIC, saver or full
application-parity claim.
