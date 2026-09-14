# Unified Notepad — CPC receiver binding

2026-09-14, issue #84, `feature/84-unified-notepad`.

The MSX arrow-navigation / incremental-repaint fixes were accepted by the
user and committed/pushed as **`6e6fe05`**. This work brings the **same APP**
to CPC; it is not a separate CPC editor or a replacement desktop port.
The accepted normal CPC distribution remains unchanged.

## File > Quit follow-up — 2026-09-14

The user accepted the exploratory CPC editor and requested **Quit** at the
bottom of the universal app's File menu. The order is now New, Load, Save,
Save As, Quit. Quit uses the existing deferred close/unsaved-document path;
Save, Discard and Cancel remain available, and errors cannot silently close it.
The user subsequently accepted the updated manual image ("OK looks good") and
requested commit/push of this work together with the private CPC receiver.

The shared popup now permits five items. Tighter padding for five rows keeps
this menu at **756/768 save-under bytes**, without adding RAM; existing menus
of one through four items retain their original dimensions. Host tests exercise
the actual popup (owned and borrowed buffers), all five selections, cancellation
and oversize rejection, plus the editor's menu dispatch and close/error paths.
The final package is **20213 bytes** (14447 primary + unchanged 5766 secondary),
primary end `786F`, DATA `7870`, top `7EF5`; capacities and budgets are unchanged.
New APP SHA256: `d45f0c5ec151f1a5ca4f9a9a52ff94162360f1aa2883eda4afa80340396ad157`.
The earlier `1d554abb…` baseline remains pinned for reproducing prior evidence.

Fresh manual CPC/M4 image (previous image and saved documents untouched):

```sh
../1984/1984 \
  --config="$PWD/build/notepad-84/manual-filequit-tjbVdT/1984.conf" \
  --6128 --memory=512 --autostart=BOOT
```

Open Disk C > ADOC > EXACT.TXT or GBENCH > NOTEPAD.APP. File > Quit is the
last row; dirty text triggers the existing confirmation. Controls remain
Ctrl+arrows/Space for the pointer while the text window is focused.

Build/host evidence: `quit-build-compatible-final.log` and
`quit-host-final.log` under `build/notepad-84/evidence/` (three tests, including
the real popup with both buffer implementations). Earlier emulator evidence:
`build/notepad-84/manual-quit-BS2tm7/openmsx-settled/result.txt` (PASS, 282
parameter calls/restorations, independent saved-file readback and clean owner
teardown). The automated MSX confirmation pulse waits for popup debounce/paint;
the earlier short-pulse failure is preserved in the sibling `openmsx` folder.
Final-build emulator results:

- `build/notepad-84/manual-filequit-tjbVdT/openmsx/result.txt`: PASS, 282
  parameter calls/restorations; clean Quit, dirty Quit/Cancel/Discard, saved
  bytes independently read back, source image and owner cleanup checked.
- `build/notepad-84/evidence/geobench-cpc-runtime-dl9drj3d/result.json`:
  PASS, real File menu clean Quit, nested document edit, dirty confirmation,
  Cancel button retains text, Discard button closes without changing the file,
  clean Desktop and exact page/seal/context reclamation. Log:
  `filequit-cpc-final.log`. Snapshots wait for an idle paint boundary before
  checking integrity; they do not inject RAM or waive a stuck repaint.

All 44 original CPC receiver files, including real Clock/Calculator, are
unchanged in the manual image. No normal-distribution promotion is implied.

Follow-up for CPC keyboard acceptance: Escape is exposed both as a text key and
a level-triggered `GB_QUIT`. A held Escape can cancel the dirty prompt then
request close again, leaving the prompt visible. This is separate from the
new Quit dispatch (MSX Escape cancellation passes). Use the on-screen Cancel
button on CPC for now. Evidence: `quit-cpc-settled.log` / runtime `8th5klaz`;
do not hide this behind a shorter automated pulse or treat keyboard acceptance
as complete. The focused Quit scenario tests the actual Cancel/Discard buttons.

## Current checkpoint: document handoff and focused editing

The preceding two-bank receiver checkpoint is committed/pushed as **`3041971`**.
This follow-up binds the existing MSX filesystem-v3 handoff and text-window
behavior into a separate full CPC private runtime. The **unchanged 20209-byte
Notepad APP now opens, edits and saves real documents on CPC/M4 in 1984**.
This is bounded receiver qualification, not normal-distribution promotion or
complete CPC Notepad acceptance.

- `PORTABLE_FS_HANDOFF=1` requires the full private package/Settings/Desktop
  composition. CPC's F7 filesystem module compiles the same `FSCTX_IDENTITY`
  and `FSCTX_HANDOFF` policy; parameter op 8 accepts identity operation 15.
  The private sysinfo publishes filesystem API **v3**, default remains v1.
- The same `core/document_launch.asm` selects the producer's copied path/name,
  binds the new owner generation, expires failed/unconsumed delivery, and
  clears matching pending identity during owner cleanup. No new public opcodes
  or alternative CPC handoff policy. File Manager's native adapter enables
  `.TXT`/`.CFG` handoff and `/GBENCH/NOTEPAD.APP` only in this build-matched
  profile; existing unsupported file types and non-system APP paths stay gated.
- Fresh CPC keyboard scans give plain arrows and Space to live explicit-kind
  `GB_WK_TEXT_INPUT` windows. Ctrl+arrows/Space retain pointer access; joystick
  input is unchanged. Invalid, native, non-text or unfocused windows retain
  pointer routing. Matrix translation preserves bank/IFF/index registers and
  does not add keyboard or graphics work to the IRQ.
- The full Desktop replaces its initial bootstrap callbacks before entering
  the event loop. This profile omits the **unused diagnostic launcher** code
  and retains the actual Desktop callbacks and Settings config reload. No
  desktop feature, public service, memory budget or editor capacity was cut.
  Ordinary/default and previous receiver profiles retain their original bytes.

Full measured fit: **CORE 16155/16384 (229 bytes spare)**, SUPPORT 3035/3072,
HARDWARE 1486/1536, scheduler 1452/1536, checked package 768/768 and bootstrap
6315/6656. F7 filesystem code is **4853/6656** (1803 spare). Notepad keeps its
14443-byte primary + 5766-byte secondary, full 4096-byte document and independent
4096-byte staging; APP SHA256 remains
`1d554abbd83f65ad2c332b48f7712694d55ed68a1ae5d0358f266c8ecdc340e8`.

Passing evidence under `build/notepad-84/evidence/`:

- `cpc-handoff-regressions-final.log`: **47 host/Z80 tests**, no skips. Includes
  **1001 executed CPC input calls** (focus/kind/CTRL/arrows/Space/held keys,
  joystick preservation, bank/IFF/index registers, stack and framebuffer),
  shared owner-bound handoff, identity, storage, package/calls and editor tests.
  Native Ctrl+Space retains its earlier key behavior; suppression as text is
  limited to a focused text window. The final adjustment is also recorded in
  `cpc-handoff-input-final.log` and `cpc-handoff-build-final.log`.
- `geobench-cpc-runtime-c8fmo3ak`: actual File Manager opens `ADOC/EXACT.TXT`,
  Notepad navigates with all four arrows, inserts text/Space, backspaces and
  saves in place. Focus away restores ordinary pointer arrows without editing
  the background document; focus return works. Opening the same basename in
  `ADOC/SUB` loads different exact bytes. Independent M4 file readback verifies
  the changed root document and unchanged nested document. Close returns to
  clean Desktop with pages, seals and contexts reclaimed. **10 checkpoints**;
  main stack reaches 165 bytes, guards intact. Screenshots are retained.
- `geobench-cpc-runtime-qrgytxx0`: earlier open/edit/save/nested-path run,
  eight checkpoints. Early observer failures were corrected: initialized
  File Manager symbols use their initialized-data base, not the BSS base.
- `geobench-cpc-runtime-z9wo28_1`: corrupt Notepad admission clears the producer's
  pending record. After dismissing the failure alert, a subsequent pristine
  blank launch inherits no document; all contexts/pages/seals are reclaimed.
  The observer uses Escape for native alerts and frame waits shorter than the
  emulator's command timeout; neither correction required guest code changes.
- `geobench-cpc-runtime-y5sa576d`: **32** desktop stacking/Clock/Calculator
  checkpoints. `geobench-cpc-runtime-el99fr7h`: three computation launches,
  **54 checks / 17 copied calls** each, distinct owner generations and cleanup.
- `geobench-cpc-runtime-o00ygoa5` / `-w6vp9v58`: Settings **21 normal + 9
  automatic cold-reboot checkpoints**, all six appearance settings retained.
- `cpc-handoff-default-before` / `-after`: complete default resident and
  bootstrap binaries are byte-identical to `3041971`.

The above full-runtime runs initially used CORE 16144. The native Ctrl+Space
compatibility adjustment adds 11 bytes; final-image reruns are recorded below.

- `geobench-cpc-runtime-6c4z9p7i`: final-image document/edit/save/focus/nested-path
  workflow, all 10 checkpoints pass.
- `geobench-cpc-runtime-t5r1i33g`: final-image bad-APP rejection, subsequent
  blank launch and complete cleanup, four checkpoints pass.
- `geobench-cpc-runtime-y8ixtv0u`: final-image Desktop, Clock, Calculator and
  File Manager stacking, occlusion, dragging, resizing and cleanup, all 32
  checkpoints pass.

Reproduce using the compiler in `my-distrobox`, then 1984 on the host:

```sh
python3 tools/build_cpc_runtime.py --notepad-handoff
python3 tools/test_cpc_runtime_1984.py --skip-build \
  --private-media build/notepad-84/cpc-handoff --notepad-case handoff \
  --notepad-app build/notepad-84/build/msx/portable-notepad-7-ze7nl4tm/probe.APP
```

The builder preserves the earlier `cpc-receiver` image and all normal/manual
images. The test makes a new M4 copy and stages the accepted APP, adjacent
`probe.noi`, and test documents; it never writes the source image. Repeat with
`--notepad-case bad-app` for failed document launch / later blank-launch cleanup.
The plain private builder does not itself stage Notepad into a distribution.

### Exploratory manual image — 2026-09-14

At the user's request, a fresh M4 image is available with the accepted Notepad
APP and two sample documents. It preserves all 44 original receiver payloads,
including the real Clock and Calculator (no test aliases).
The fresh image boots in 1984 with filesystem v3, intact resident/module code
and stack guards, and one clean Desktop window (`boot.sna` / `boot.png` beside
the image). Initial image SHA256:
`7ed1119d2c8494a7f4d8e9b513b8017e8c763172324a5d0aafe58120ae4ca230`.

From the repository root, run:

```sh
../1984/1984 \
  --config="$PWD/build/notepad-84/manual-cpc-jB6Idz/1984.conf" \
  --6128 --memory=512 --autostart=BOOT
```

Prefix with `distrobox enter my-distrobox --` if needed for emulator libraries.
Double-click **Disk C > ADOC > EXACT.TXT**. Try arrows, text, Space and
Backspace; use **Ctrl+arrows** to move the pointer and **Ctrl+Space** to click
while the editor is focused. Choose **File > Save**, close, and reopen to
verify persistence. `ADOC/SUB/EXACT.TXT` is a different sample with the same
basename. `GBENCH/NOTEPAD.APP` opens a blank document.

Saves stay in `build/notepad-84/manual-cpc-jB6Idz/NOTEPAD.IMG`; normal images,
older manual images and automated evidence are untouched. Back up this file
to preserve manual edits. This is exploratory testing, not completion of the
remaining acceptance gate or normal-distribution promotion.

**Next gate:** complete CPC editor acceptance: 4096-byte round trip, 4097-byte
rejection, dirty-close/cancel/discard, chooser/clipboard, repaint bounds and
occlusion under the real CPC renderer, repeated cleanup and storage faults.
The exploratory image above is available before that gate at the user's
request. Normal delivery promotion and a second CPC emulator/backend
confirmation remain separate work.
The CPC translator still emits one character per press/change, as before;
key-repeat timing is not added by this receiver binding and remains an input
acceptance item.

## Previous checkpoint: private desktop two-bank receiver

The shared package loader and sealed secondary-call policy now run in the
**full private CPC Desktop/File Manager/Settings composition**. The transport
foundation was committed/pushed as `fd04dd1`; this follow-up remains on #84.
It does not yet make Notepad runnable on CPC: filesystem identity/handoff and
focused text input still need receiver bindings. No APP source was changed.

- `PORTABLE_PACKAGE_STREAM=1` binds the existing shared launch transaction,
  dual admission, package stream, generation seals and secondary calls to
  CPC's real owner/page tables and bank leaf. CRC/descriptor validation and
  successful CLOSE precede seal publication and execution. Owner/page release
  use the existing shared cleanup hooks.
- Classification consumes one 256-byte prefix, then hands the **same open
  descriptor and cached prefix** to the shared transaction. Native/root/module
  reads use the same bounded sequential reader without package admission.
  Native File Manager/Settings retain their build-matched admission checks.
- After the low M4 bootstrap has jumped to high code, the receiver loads
  `GBENCH/GBPKLOAD.MOD` into `0100..0400`. Exact length, EOF, successful CLOSE
  and a build-bound CRC32 must pass before readiness, capabilities or the
  desktop are published. CRC is a build-integrity check, not authentication.
  A missing, short, appended or corrupt module stops boot without executing it.
- The 510-byte transport is split between SUPPORT (open/close) and HARDWARE
  (read/context handling), without changing the original contiguous diagnostic
  bytes. Fixed state occupies `1F00..1F80`; the locked 512-byte transfer uses
  `1500..1700`. No app bank, framebuffer, stack or live native-edit state is
  borrowed. Fixed IRQ timekeeping continues while the root lock excludes app
  callbacks and other storage users.
- Only this explicit private profile advertises secondary calls (`05DF` high
  capability word). Default remains `01DF`, filesystem API remains **v1**,
  and the unqualified portable-data-page combination is rejected at build time.

Measured full composition, including real native modules:

| Region | Used / reserved | Remaining |
| --- | ---: | ---: |
| High kernel `8000..C000` | 16366 / 16384 | 18 bytes |
| Support `0400..1000` | 3035 / 3072 | 37 bytes |
| Hardware `3800..3E00` | 1483 / 1536 | 53 bytes |
| Scheduler `2900..2F00` | 1452 / 1536 | 84 bytes |
| Checked package module `0100..0400` | 757 code/header, 768 loaded / 768 | 11 padding bytes |
| F7 filesystem module `4400..5E00` | 4583 / 6656 | 2073 bytes |
| Firmware-loaded bootstrap `8000..9A00` | 6312 / 6656 | 344 bytes |

The next bindings must respect these separate address domains. In particular,
18 kernel bytes is **not** enough for the remaining input/handoff work without
measured code savings or reviewed placement inside existing allocations.
Do not enlarge memory limits or shrink Notepad to solve this.

Qualification uses actual 512-KiB CPC/M4 in unmodified `../1984/1984`:

- The existing universal computation APP passes **54 checks / 17 successful
  copied secondary calls per launch**, for three launch/close cycles through
  the real Desktop menu. Owner `(2,1)`, `(2,2)`, `(2,3)` identities, exact primary
  and secondary code bytes, seals, page purpose, reclaimed pages/owners, fixed
  code, stack guards and an unchanged disk are checked. Its 11206-byte APP SHA
  is `ab6e6eef5bea73ff474d3357e69da4b549e2235429eb917478963f82cf1cc0f4`.
- Missing/short/appended/corrupt loader-module cases all stop before root-owner
  or window publication, with closed transport and stable halted state.
- CRC-corrupt, truncated and appended APPs, plus a valid APP returning without
  registering a window, each pass three attempted launches with owner/page/seal
  rollback and no stale transport state.
- The final private image passes **32 desktop stacking checkpoints**, including
  Clock seconds, partial/complete occlusion, pointer save-under, Calculator
  input/drag/close and File Manager edge/resize/cleanup. Settings passes **21
  normal + 9 cold-reboot checkpoints**, six appearance choices, cancellation,
  close/reopen, exact config readback and 46 unchanged expected file payloads.
  Maximum observed main stack is 209 bytes (IRQ 4, temporary 6 in stacking);
  all guards remain intact. The test runner preserves the private profile for
  its automatic Settings reboot; it must never select the normal image there.
- **22 host/Z80 tests pass**, including the original 6,058 transport calls,
  shared stream/sealed-call policy, storage, native loading and complete
  default/private assembly budgets. Baseline CORE, SUPPORT, HARDWARE, SCHED,
  BOOT and LOADER binaries are byte-identical to `fd04dd1` with the private
  receiver disabled.

Evidence under `build/notepad-84/evidence/`:

| Case | Directory or log |
| --- | --- |
| Computation / three generations | `cpc-receiver-normal-2h68i6xu` |
| Bad APP CRC / short / extra / no registration | `geobench-cpc-runtime-eof8sjjd`, `-naxlejlh`, `-ztgnq_zp`, `-ayb2t4s_` |
| Missing / short / extra / corrupt module | `geobench-cpc-runtime-1j509ed_`, `-_3wu4v75`, `-4y7oa0yd`, `-f4xlktwb` |
| Final desktop stacking | `cpc-receiver-stacking-kealzdni` |
| Settings save / cold reboot | `cpc-receiver-settings-kctitpa1`, `geobench-cpc-runtime-j0s8hv60` |
| Host/Z80 regressions | `cpc-receiver-regressions.log` |
| Default binary comparison | `cpc-receiver-default-before`, `cpc-receiver-default-after` |

Abbreviated `-suffix` entries retain the `geobench-cpc-runtime` prefix.
The first normal Settings process passed its guest checks but initially failed
to select the private profile for its automatic reboot. The harness was fixed;
the explicit cold-reboot run uses that exact saved Settings image and passes.
These are private receiver checks, not complete storage-fault or v1.0 acceptance.

Private build and qualification commands (compiler/tools available via
`my-distrobox`; the emulator runs on the host):

```sh
python3 tools/build_cpc_runtime.py --notepad-receiver
python3 tools/test_cpc_runtime_1984.py --skip-build \
  --private-media build/notepad-84/cpc-receiver --package-case normal
```

Use the same test command with `crc`, `short`, `extra`, `no-register`, or
`module-missing`, `module-short`, `module-extra`, `module-corrupt` as the case.
Baseline desktop checks replace `--package-case normal` with
`--filemgr-scenario stacking` or `--settings-case normal`. The computation
fixture replaces CALC.APP only on each **disposable test image**, not in the
private source media or normal distribution. This is not a manual Notepad
image. No normal `make cpc` build or manual saved-document image is replaced.

## Previous checkpoint: sequential M4 transport qualified

`lib/cpc/m4_stream.asm` adds a private single-open reader for the shared
package transaction. It reuses the existing `m4.asm` bounded command/response
transport. Unlike the old CPC app reader, it does not reopen and seek for
every 128 bytes. It performs one dynamic OPEN, sequential READ2 commands and
one CLOSE. A caller's 0–512-byte read is divided into at most four wire reads.

The caller must hold the root scheduler lock for the whole descriptor
lifetime. Each entry preserves the incoming IFF and GA/ROM configuration;
the adapter never switches application banks. The ordinary filesystem gate
is excluded by `io_busy`. Uncertain OPEN/CLOSE replies poison the backend,
without guessing a descriptor or retrying a close. Every failure returns
zero usable bytes; the package loader must discard any partially filled
private buffer and must not publish executable pages before validation and
successful close. No new public filesystem operation or capability is added.

The adapter is **510 code bytes + 11 fixed state bytes**, plus the existing
M4 scratch and a caller-provided fixed 512-byte transfer buffer. It is not
linked into normal CPC delivery builds. The standalone probe addresses are
test bindings; the subsequent full private receiver placement is recorded above.

Evidence:

- `tests/test_cpc_stream_adapter.py`: **6,058 executed Z80 calls**, all counts
  0–512, repeated reads, short/EOF, malformed response lengths/counts/IDs,
  I/O errors, uncertain open/close, nesting, ordinary-gate exclusion, invalid
  context/path/buffer and preserved bank/ROM/IFF/index registers. The device
  model rejects SEEK, writes and guessed closes. Observer-negative tests
  separately reject changed code, segment bytes/tails, guards and context.
- Longest modeled adapter call: **28,587 CPU cycles, 12 stack bytes**. This
  excludes physical M4 bus-hold time and CPC contention; it is not a measured
  desktop latency claim. The caller can service fixed IRQs between reads.
- `tools/test_cpc_stream_1984.py`: actual 512-KiB CPC/M4 in the unmodified
  `../1984/1984`, SHA256
  `b99c482451e67b2a2876487af7021c0ad78a57c5e1778f6c217ab5956df7616a`.
  The accepted **20209-byte** APP is copied to real C4/C5 banks: **14443-byte
  primary + 5766-byte secondary**, with exact-byte and untouched-tail checks.
  One OPEN, **160 READ2**, one CLOSE; real fixed-time IRQs advance. Code,
  stack guards, bank/ROM state, framebuffer and M4 image remain intact.
  Truncation, appended data and missing-file cases also pass cleanup checks.
- Private evidence under `build/notepad-84/evidence/`:
  `cpc-stream-normal-8ruga5sx`, `cpc-stream-short-49xj80tj`,
  `cpc-stream-extra-f4dqs0d3`, `cpc-stream-missing-_x42ljc0`.
  Each has `build.json`, M4 image, emulator log, two snapshots and
  `result.json`. Earlier normal run `cpc-stream-normal-4tj3ych0` is retained.
- All **14 focused tests** pass: the two new transport/observer tests, six
  existing CPC storage tests, and shared package/sealed-call regressions at
  both fixed layouts. No default transport, runtime, application, emulator
  or firmware source was modified.

The hardware probe deliberately **does not execute the APP**, perform GBAP
admission, seal a secondary page, or present a desktop. A transport PASS is
not a runnable-Notepad or full CPC receiver acceptance claim.

## Original receiver work order (progress superseded above)

1. **Document and input bindings.** Enable the existing shared filesystem
   identity / owner-bound launch-handoff policy in CPC's paged FS module and
   File Manager. Port focused `GB_WK_TEXT_INPUT` routing using CPC keyboard
   capture, preserving Ctrl+arrows/Space pointer access. Native/default
   windows must retain their existing input behavior. No editor-side fork.
2. **Identical APP acceptance in a private desktop M4 image.** Open/edit/save,
   arrows/Space/backspace, bounded repaint, exact-path document launch,
   focus/occlusion, dirty close, 4096-byte round trip, 4097-byte rejection and
   repeated cleanup. Only then supply a manual CPC editor image. Normal
   delivery promotion is separate; M4/Albireo tests only, never floppy tests.

## Baseline placement investigation (before receiver binding)

Measured from the accepted `QA/CPC-Desktop/manifest.json`, not a smaller
diagnostic build:

| Resident region | Used / reserved | Remaining |
| --- | ---: | ---: |
| High kernel `8000..C000` | 15821 / 16384 | 563 bytes |
| Support `0400..1000` | 1836 / 3072 | 1236 bytes |
| Hardware `3800..3E00` | 1130 / 1536 | 406 bytes |
| Scheduler `2900..2F00` | 1452 / 1536 | 84 bytes |
| F7 filesystem module `4400..5E00` | 4583 / 6656 | 2073 bytes |

These are separate address domains, not interchangeable free RAM. The new
510-byte transport alone exceeds hardware headroom. Measure the complete
composition before choosing placement or advertising capabilities.

- The shared stream transaction is 742 bytes in the serialized fixture and
  749 bytes with its IRQ profile. `0100..0400`
  was a candidate only **after** the M4 loader jumps to the high kernel. Do
  not overwrite that loader while it is executing. A deferred checked module
  load is now implemented and qualified as described above.
- Growing SUPPORT also grows the firmware-loaded bootstrap payload, which
  must remain below `9A00`. Check both the final resident map and bootstrap.
- `3000..3400` is already used by graphics, window and input state despite
  its historical `FUTURE_STATE` name. Do not allocate over it or framebuffer.
- F7 filesystem code cannot simply host helpers that must execute with an
  application/secondary bank mapped. Primary, secondary, fixed transfer and
  all live stacks must remain disjoint.
- Portable data-page support currently has a diagnostic-only CPC profile.
  If included in the receiver composition, remove that restriction only
  after proving the complete desktop layout and unchanged baseline behavior.
- Keep full 4096-byte document + independent 4096-byte staging. Notepad's
  primary has only 5 code / 11 data bytes spare; do not solve receiver
  placement by reducing the editor or adding CPC-specific APP code.

## Reproduce the transport check

Use the already accepted private MSX APP, not the native normal-image Notepad:

```sh
python3 -m unittest discover -s tests -p test_cpc_stream_adapter.py -v
python3 tools/test_cpc_stream_1984.py \
  --app build/notepad-84/build/msx/portable-notepad-7-ze7nl4tm/probe.APP
```

Its SHA256 must remain
`1d554abbd83f65ad2c332b48f7712694d55ed68a1ae5d0358f266c8ecdc340e8`.
Repeat with `--variant short`, `--variant extra`, `--variant missing` for
negative media. `--prepare-only` allows building in `my-distrobox` and then
running `--stage <printed-directory>` on the host. Every preparation creates
a fresh evidence directory/image; existing media and manual saved documents
are never overwritten. These commands test storage, not the editor UI.
