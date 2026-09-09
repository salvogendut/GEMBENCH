# v1.0 M1B — unified Notepad

Started 2026-09-09 in [issue #84](https://github.com/salvogendut/GEMBENCH/issues/84),
branch `feature/84-unified-notepad`, based on main `1367593`.
Follows the [bounded MSX baseline close-out](V1-MSX-STABILITY-BASELINE.md).

**Checkpoint 2 in progress: the actual editor integration source and document
controller now exist, but the complete primary-only link fails the memory gate.
Owned data/secondary-code support is a demonstrated prerequisite.** Portable
clipboard and chooser foundations retain their earlier cross-target evidence;
the new editor has host policy tests only. Checkpoint 1's
source/memory audit and document-I/O foundation are preserved below.
Checkpoint 2d qualifies the portable owned-data-page slice on private MSX/CPC
builds. Checkpoint 2e now qualifies the shared streaming loader in instruction
fixtures; receiver integration and validated secondary calling are still required.
See [portable pages](PORTABLE-PAGES.md) for its contract and evidence.
Notepad remains the native application in the normal MSX distribution and is
not yet delivered on CPC. No unified Notepad APP or emulator acceptance is
claimed by this checkpoint. Normal MSX/CPC images are unchanged.

**Save point, 2026-09-09:** the user requested committing/pushing these
foundations and updating working memory before resuming. The
[roadmap's four remaining packages](ROADMAP-V1.0.md#saved-checkpoint-and-remaining-delivery-path--2026-09-09)
prioritize a first testable MSX editor, followed by full identical-binary CPC
qualification; this is not a reduced feature scope or a migration-complete
claim. [SESSION-HANDOFF.md](SESSION-HANDOFF.md) records the exact restart point.

## Ordered delivery

1. **Complete:** audit the actual editor, linked memory and service
   dependencies; establish bounded document-I/O behavior using the existing
   shared filesystem client. Preserve native delivery and baseline evidence.
2. **In progress:** migrate the real editor and its window/menu/dialog, typed clipboard and
   document-handoff bindings. Measure the complete linked application, retain
   4096-byte editable capacity, then qualify MSX Screen 6/7 with openMSX and
   1983. Review and document any needed public service extension before using
   it; do not weaken the portability audit or copy private mailbox addresses.
3. Qualify the **identical APP bytes** on CPC/M4, comparing staged hashes and
   completing document, failure and lifecycle acceptance on both targets before
   replacing normal delivery. CPC tests use M4/Albireo media, never floppies.

These are checkpoints within roadmap milestone 1, not replacement milestones.
Future page/resource services, CPC splash and release-wide qualification retain
their roadmap packages unless a demonstrated prerequisite is recorded.

## Native reference and memory audit

The reference is `apps/notepad/main.c`, not a new/reduced editor. It already
uses a kernel-managed window: preserve the shared window policy, replacing
native bindings rather than adding app-local dragging, stacking or repaint.

Fresh native build in detached worktree `build/notepad-84` at `1367593`:
SDCC **4.6.2 #16671**, `GB_MSX2`, `GBDOC_BOUNDED_IO`, `DOC=1`, `REPAINTTOP=1`,
`GB_SCRAP=1`, `GB_SCRAP_TEXT_ONLY=1`, `GB_SHELL_TARGET=1`, `DATA_LOC=0x6F48`,
size optimization/max-allocs 100000 and the existing Notepad trampoline subset.
Evidence: `evidence/native-notepad-build.log` and
`build/msx-obj/notepad/app.{map,noi}` inside that worktree. Existing optimizer
and constant-conversion warnings remain; no claim that these are resolved.

| Native allocation | Start | End (exclusive) | Bytes |
| --- | --- | --- | ---: |
| Code | `0x4110` | `0x6F00` | 11760 |
| GSINIT + GSFINAL + initializers | `0x6F00` | `0x6F26` | 38 |
| Gap before data | `0x6F26` | `0x6F48` | 34 |
| Data + initialized data + BSS | `0x6F48` | `0x7FF9` | 4273 |
| Native headroom | `0x7FF9` | `0x8000` | **7** |

`NOTEPAD.RAW` is 12070 bytes, SHA-256
`402bff07cb4fa73e8b395a6e2707c46860708c7eac0b44e9bcd7dfed3bee7458`,
identical to the earlier native reference in the application ledger.

The universal primary span ends at **`0x7F00`**, reserving 256 bytes for the
task stack. The existing native data end already exceeds it by **249 bytes**.
The existing portable filesystem client needs another **544 caller-owned
bytes** (32-byte header + 512-byte transfer), and the new I/O job needs 11.
Native Notepad also reclaims 116 bytes of icon space for line/title scratch
at `0x4010..0x4083`; native `gbdoc` stores eight job bytes at `0x4084..0x408B`.
These are not general-purpose universal memory: allocate actual app-owned
state and budget the v4 package metadata instead of copying these addresses.

This proves that a flag-only rebuild cannot work, not that a portable editor
cannot fit. Replacing the native document/UI glue may save code; measure the
complete replacement before deciding whether an owned-page service is needed.
Do not shrink `NP_MAX=4096`, raise the ABI memory limit, overwrite metadata or
borrow the reserved task stack to make the map pass.

## Service and behavior inventory

| Area | Existing implementation / migration work |
| --- | --- |
| Editor | Retain insertion, backspace/delete, selection, scrolling/reflow, copy/paste/select-all, caret and two-key-per-frame editing bound. Replace compile-time geometry with runtime extents and owned line/title buffers. |
| Managed window and menus | Universal runtime/message, managed-kind, semantic drawing and popup helpers exist. Bind File/Edit/View, resize/fullscreen and partial damage to the shared kernel; native `gb_doc` and GBUI dialogs are not portable drop-ins. |
| Document filesystem | `UNIVERSAL_FS=1` already supplies the shared context client through `GB_PARAMS_FILESYSTEM` on MSX and CPC. Reuse open/path/name/read/write/rewind/adopt/close; no second filesystem state machine in a target adapter. |
| Document UI | Portable owned-context chooser/panel now provides directory paging, TXT/BAS/CFG filtering, cancellation and Save As naming. It is exercised with bounded document readback, not integrated into Notepad. New/Load/Save/Save As lifecycle, dirty Save/Discard/Cancel and document recovery remain. See the CPC path limitation below. |
| Typed clipboard | **Binding implemented:** `UNIVERSAL_SCRAP=1`, required `typed-clipboard`, shared kernel policy on both receivers. MSX retains the native tag/510-byte payload; CPC now exposes the portable typed service while legacy raw slots remain unavailable. Three-owner diagnostic tests pass on both targets; real editor exchange still needs acceptance. |
| Launch and editor reuse | Existing shell policy and owned filesystem launch preparation/adoption are reusable. Remove native `gb_msg`/`gb_shell_argument` access; preserve exact drive/path/name, dirty/busy rejection, response status and owner cleanup for normal File Manager handoff. |
| BASIC files | Existing open strips CR; save expands LF to CRLF and ensures a trailing line ending when space permits, then restores editing contents. Near-capacity expansion and failure restoration need explicit byte tests; raw I/O alone does not implement this. |
| Configuration files | Native `np_saved` copies small `GEOBENCH.CFG` contents into private `0x1000`/`0x1200` cache. Determine the supported portable configuration/reload contract; do not reproduce that write or silently discard the behavior. |
| Input | Current MSX arrow-reading helper is a no-op; the historical CPC path calls firmware directly. Do not revive that firmware code in the universal app. Preserve current supported input and qualify normal keyboard/pointer behavior on both targets. |

Additional source-review risks, **not newly reproduced bugs**: display-row
counters are eight-bit despite a 4 KiB document, and Ctrl-Q has a direct close
path. Test many-short-line documents and every close route before deciding
whether corrections are needed; dirty confirmation must not be bypassed.

## Implemented foundation: `gbdocio`

`include/gembench/gbdocio.h` and `lib/gembench/gbdocio.c` provide a small SDK
helper over `gb_fsctx`, without changing the kernel ABI or existing delivery.
It is not yet linked into Notepad. `UNIVERSAL_DOCIO=1` now links it through
`build_uapp.sh`, requiring `UNIVERSAL_FS=1`.

- Caller owns a zero-initialized job, an exclusively borrowed named context
  and stable buffers. Root callbacks only; no workers or reentrant calls.
- Start performs no I/O. Each active step performs **one** synchronous FS
  operation and transfers at most **512 bytes**. Call at most once per frame.
  This bounds work size, not worst-case storage-provider time or pointer latency.
- Load rewinds and reads raw bytes, distinguishing error status from EOF.
  At capacity it probes one byte into the job itself: exactly 4096 bytes
  succeeds; 4097 is an explicit size error, not silent truncation or overflow.
  No terminator or newline conversion is added.
- Save rewinds and writes bounded chunks. Empty saves issue the actual
  zero-length truncating write. Only acknowledged writes advance progress.
- Cancellation stops future work without releasing someone else's context.
  Busy/invalid starts leave the job intact. Terminal jobs retain their own
  error/progress and do no more I/O; another FS call cannot erase the error.
- Failed/cancelled loads may have replaced a destination prefix; save failures
  may leave a partial disk file. This is **not atomic I/O**. The editor must
  own dirty-state, publication, any staging/rollback and post-error UI policy.
  Never publish a partial load as success or clear dirty state on failed save.

Caller example (after opening/naming a context):

```c
static gb_docio_t job;       /* zero initialized, in primary application RAM */
/* gb_docio_load(&job, context, destination, capacity); */
/* In each eligible root frame: */
if (gb_docio_busy(&job)) gb_docio_step(&job);
/* DONE commits; ERROR/CANCELLED recover; caller eventually closes context. */
```

## Verification and limits

Run from the repository with the project toolchain available (or via
`distrobox enter my-distrobox --`):

```sh
python3 -m unittest discover -s tests -p test_docio.py -v
python3 -m unittest discover -s tests -p test_client_parameter_core.py -v
python3 -m unittest discover -s tests -p test_universal_parameters.py -v
```

All **16 tests pass, no skips** (3 new, 13 existing). The new executable runs
the real helper and shared FS client, with only the storage gate faked:
0/1/511/512/513/4095/4096-byte roundtrips, arbitrary bytes and CRLF preservation,
oversize/zero-capacity/short-read cases, **133 injected errors** spanning every
load/save step and all seven FS error codes, busy rejection, cancellation,
restart/truncation, stale context and interleaved independent-context jobs.
Guard bytes detect destination overruns; every active step is checked for one
FS operation, and terminal steps for none.
The container repeat logs are saved under `build/notepad-84/evidence/` as
`docio-tests.log`, `client_parameter_core-tests.log` and
`universal_parameters-tests.log`.

SDCC compilation verifies an **11-byte job**, **888 bytes of code** with the
test's recorded size flags, and no persistent library data/hidden transfer
buffer. Source and generated assembly pass the existing portability audit.
This object size is not a full APP link/stack-fit result. Host gate tests do
not prove GB_PARAMS transport, emulator behavior, disk recovery or real-time
responsiveness; those belong to the actual app qualification.

The original I/O-only checkpoint did not change kernels/providers or repeat
runtime suites for its unlinked helper. The following clipboard checkpoint
does change receivers and therefore adds cross-target runtime checks.

## Checkpoint 2a — portable typed clipboard, 2026-09-09

The append-only [clipboard contract](UNIVERSAL-APPLICATION-ABI.md#typed-clipboard-binding-optional-abi-21-service)
adds capability `0x01000000` and parameter operation 9. It reuses the existing
510-byte clipboard, shared parameter serialization and mapped-owner checks.
Both target providers bind **one** `parameters_clipboard.asm`; MSX native raw
writers keep their tag-invalidation behavior. CPC explicitly clears its private
length/tag on cold boot. No app-private mailbox, worker clipboard access,
payload allocation or new application memory/stack limit was introduced.

The portable `gbscrap.h` binding adds 359 code + 8 data bytes. It is tested but
not yet linked into Notepad. The private MSX gate grows from 2549 to 2889
bytes; its 48-byte legacy sysinfo view moves from `0x0F00` to `0x0FD0` inside
the same reserved module area. It still hides new services from ABI 2.0 apps.
The complete private CPC Desktop build also fits: resident kernel 15835/16384,
support 2171/3072 bytes. Neither target's primary/stack boundary changes.

The diagnostic `apps/scrapprobe` builds to **4808 bytes**, SHA-256
`de02ed6eaaaa4706e6f29c4af5b80d52f5343709f5031c9edd265e3b5218ef54`.
The same bytes are read back from each test disk. It is not a reduced editor:
it only qualifies the prerequisite service, using actual loader/SDK calls.

Evidence relative to `build/notepad-84`:

| Check | Result / evidence |
| --- | --- |
| CPC M4, 1984 | PASS, 49+50+50 app checks across owner generations `(3,1)`, `(3,2)`, `(3,3)`; clipboard survives close/relaunch. Exact exposure/code/stack guards pass after each close. `evidence/clipboard-cpc.log`, retained `evidence/clipboard-cpc/result.json`. |
| openMSX Screen 6 | PASS, same three lifetimes/149 app checks; 146 parameter return checks preserve mapping, SP, interrupt/lock state, snapshot guard and VRAM. `evidence/clipboard-msx6-run3.log`, image under `build/msx/portable-clipboard-6-tu_rgbyf/`. |
| openMSX Screen 7 | PASS, same workload and return checks. `evidence/clipboard-msx7.log`, image under `build/msx/portable-clipboard-7-9ti1kj4_/`. |
| 1983 Screen 6/7, corrected RainBIOS | PASS, same APP/images and three owner lifetimes, independent read-only bridge/real Desk input. 34/43 lifecycle observations in addition to 149 app checks per mode. `evidence/clipboard-1983-{6,7}/result.json`. |
| openMSX existing Clock/Calculator plus parameter boundaries, both modes | PASS, 106 injected public-service checks per mode after the real Desk workflow, including IFF disabled/enabled, worker rejection, invalid header, corrupt length and unknown-tag normalization. `evidence/clipboard-parameters-{6,7}.log`. Injected boundary calls are labeled diagnostic, not UI input evidence. |
| Universal SDK integration | PASS deterministic packaging, v6 layout and existing source/object audits. `evidence/clipboard-sdk.log`. |
| Focused clipboard/native tests | Five new contract/size/build-flag tests pass. Native typed-scrap C tests and both SDCC adapters pass unchanged (552-byte general helper; 100-byte native text helper). |
| Complete host suite | 302 tests: 301 pass, one initially skipped because the isolated worktree could not locate sibling 1983 sources. With `MSX_1983_SOURCE` set explicitly, both input tests pass after fixing the fixture's truncated module load. `evidence/clipboard-host.log`, `evidence/clipboard-button-capture-repeat.log`. |
| Complete private CPC Desktop, M4/1984 | Stacking (32 checkpoints) and cursor cadence (26 checkpoints) pass, including hidden Clock, partial exposure, focus/drag/resize and page/context cleanup. Stack high-water values: main 144, IRQ 4, temporary 6 bytes. Cursor movement with seconds enabled measures 49.24 steps/s focused and 48.86 steps/s background, with no stationary video frames in those samples. `evidence/clipboard-desktop-{stacking,cadence}.log`. These targeted regressions do not repeat the entire delivery/storage-fault qualification. |

The 1983 bridge was rebuilt from unmodified sibling main `c0a0b4a`;
`evidence/clipboard-1983-build.log` pins source/binary hashes. This is core/input
testing, not the SDL mouse front end. Corrected RainBIOS is explicitly supplied;
the bundled ROMs have not been replaced.

Earlier failures are retained: the first MSX attempt lacked copied build
dependencies, and the second passed the service checks but the driver clicked
maximize instead of close. Correcting the fixture staging/gadget coordinate
produced the passing repeat without changing service code or shortening checks.
The previously skipped instruction-level input test also exposed its own
`0x0B00`-byte module read cap: the grown module was silently truncated. Its
loader now reads the full reserved `0x0C00`-byte region and asserts EOF; input
behavior assertions remain unchanged. The failed log is retained as
`evidence/clipboard-button-capture.log` alongside the passing repeat.

Normal MSX/CPC media remain untouched. Notepad still uses native delivery.
Next at checkpoint 2a: portable document UI/chooser, shell handoff/configuration behavior and
the real editor binding with its complete linked-memory budget; then actual
Notepad document/error/repaint acceptance on MSX and CPC. The clipboard service
diagnostic alone does not satisfy the editor-to-editor copy/paste gate.

## Checkpoint 2b — owned document chooser, 2026-09-09

`gbfilepick.h` / `gbfilepick.c` implement a caller-owned chooser over the existing
shared filesystem client; `gbfilepick_ui.h` / `gbfilepick_ui.c` draw its content
panel inside an existing managed window. `UNIVERSAL_FILEPICK=1` links both and
requires `UNIVERSAL_FS=1`. This slice adds **no kernel ABI, provider changes or
normal distribution changes**.

- Begin performs no I/O. Each eligible root-frame step performs at most one
  FS operation, with at most four directory entries in a batch. Six rows per
  page; Next/Prev rescan the directory rather than truncating its listing.
  This bounds work per step, not provider latency; the directory is not a snapshot.
- A separate temporary context protects the editor's existing context/buffer.
  Directories remain visible through extension filters; Up, empty directories,
  path-length rejection and filenames with extensions are handled by the model.
- Open returns a fully named context through `take()`, transferring ownership
  explicitly. Cancellation/errors close the temporary context on a later step.
  A failed close retains its handle and error for explicit cleanup retry; never
  reinitialize a live object. No filesystem writes occur in this chooser.
- Save As accepts bounded uppercase 8.3 names, rejecting malformed/overlong
  input without silently saving a truncated name. Clicking an existing file
  fills the name field; accepting the destination is a separate action.
  Overwrite/dirty-document policy belongs to the editor, not this selector.
- The renderer has no nested polling loop, window manager or saved-under buffer.
  The caller requests a **client-only** clipped repaint when state changes.
  Setting `gb_wm_damage` alone does not enqueue a repaint: follow it with the
  normal `gb_restore_parent` compositor call, as the existing Calculator does.

### Size and integration boundary

SDCC 4.6.2, size optimization/max-allocs 100000:

| Component | Cost |
| --- | ---: |
| Caller-owned chooser | 161 bytes, including six 12-byte rows |
| Chooser model | 2852 code bytes, no persistent library data |
| Content renderer | 1581 code bytes, no persistent library data |
| Existing bounded I/O job/helper | 11 caller bytes / 888 code bytes |
| `PICKPRB.APP` diagnostic | 9834 bytes; code starts `0x416C`, data `0x6B40..0x7E64` including BSS |

The model/I/O use IX frames for size because their external kernel-bound calls
all pass through the IX-preserving filesystem parameter bridge. The renderer
retains the IY/omit-frame-pointer profile required by legacy drawing calls.
The source/object audits and the actual target runs check this combination.

`apps/filepickprobe` links these components with an actual **4096-byte read
buffer plus two guards**. It loads selected files through `gbdocio`; Save As
only chooses a destination and explicitly reports **no write**. It is not an
editor, does not exercise dirty-save recovery, and is not the complete Notepad
link. Its code/data gap and 156 data-tail bytes are not evidence that the real
editor fits: that full link remains required before changing the memory plan.

### Runtime evidence

Identical final APP SHA-256:
`b7831fed4c063447559cd2dc4abc8cf8a70ae895a5acb46e0644da0fb536f133`.
Evidence paths below are relative to `build/notepad-84`.

| Check | Result |
| --- | --- |
| openMSX Screen 6/7 | PASS: 13 real-pointer checkpoints, selected 42-byte CRLF payload read back exactly, cancel/restart/close; 47 FS returns per mode preserve mapping, SP, IFF/lock, snapshot region and VRAM. `evidence/chooser-msx{6,7}-painted.log`. |
| 1983 Screen 6/7, corrected RainBIOS | PASS: same input scenario, independent glyph checks of visible status text, window borders, code/document guards, context/page cleanup and unchanged disks. 122/161 observations. `evidence/chooser-1983-{6,7}-painted/result.json`. No injected guest calls or RAM writes. |
| CPC M4/1984 | PASS: same 13 checkpoints with independent visible-text checks, plus exact post-close exposure oracle; disk unchanged. Stack high-water main 205/256, IRQ 4/256, temporary 0. `evidence/chooser-cpc-painted.log` and retained `evidence/chooser-cpc-painted/result.json`. |
| Host/SDK | 25 focused tests pass, no skips: four chooser/model/renderer/builder/layout tests, three I/O, five clipboard and 13 shared parameter/client tests. Native helper tests include 42 injected open/path/activate/scan errors, failed selection/close, ownership transfer, >255-entry paging, filename/path bounds and content-only drawing. `evidence/chooser-*-tests-repeat.log`. |
| Existing workflows | Universal SDK packaging remains deterministic (`evidence/chooser-sdk.log`); the original Screen 7 FS probe still passes all 46 return checks (`evidence/chooser-existing-fs-msx7.log`). This is targeted regression coverage, not full release/storage-stress acceptance. |

The diagnostic disk aliases `PICKPRB.APP` to Clock on MSX (real Desk launch),
and to FSPROBE on the private CPC M4 launcher (F5). Normal Clock/Notepad delivery
is untouched. The 1983 bridge/firmware remain those recorded in checkpoint 2a.

Retained failures matter: host-recursive `mcopy` did not preserve fixture row
order, so fixture directories/files are now inserted explicitly. The openMSX
return breakpoint initially matched the same numeric address **inside Nextor
ROM**, not the caller's bank; it is now qualified by caller slot/mapper as well
as PC, with all preservation assertions retained. Diagnostic symbol exports,
menu-range hit-testing and bounded bridge reads were corrected. An initial
state-only workflow missed the absent repaint call; visual inspection exposed
it and the final runs add independent glyph assertions. Earlier `*-workflow`
results are **not final UI acceptance**. Renderer-none openMSX captures are
optional; final CPC/1983 screenshots were inspected.

### Known CPC provider gap — not fixed or hidden by this checkpoint

The chooser correctly constructs `/DOCUI/DIR.EXT`, but the existing CPC
`cpc_fs_activate` rejects dots in directory components (currently at most eight
`A-Z`, `0-9`, `_`, `-`, `~` characters per component). Its filename helper also
accepts a narrower character set than the chooser's 8.3 syntax. The actual M4
failure returns IO error and cleans up the context; evidence is retained in
`evidence/chooser-cpc-dotted-failure/` and `evidence/chooser-cpc-ordered.log`.
The passing common scenario uses `/DOCUI/DIR`; it does **not** qualify dotted
directories or wider filename characters on CPC. The host model's dotted-folder
tests pass, isolating this limitation to the existing provider. Address it before
claiming full document portability; do not add target branches to the editor or
silently trim names to work around it.

Next: bind the real editor with dirty Save/Discard/Cancel and load/save recovery,
complete its linked-memory budget, preserve BASIC newline handling and portable
shell/configuration behavior, then qualify real editing/writes on both targets.
This chooser/readback diagnostic does not replace any of those gates.

## Checkpoint 2c — real editor integration and failed full-link gate, 2026-09-09

`apps/unotepad/main.c` now binds an editor derived from `apps/notepad/main.c`
to the unified SDK. `editor.h` separates its buffer, selection and wrap policy
from native document/UI code. This is application integration source, not another
service probe, but **it is not a runnable/qualified migration**. The original
native app and all normal media remain unchanged.

Implemented source paths:

- Managed standard window furniture, runtime geometry, File/Edit/View menus,
  fullscreen/reflow, insertion/backspace/delete/tab, scrollbar, selection,
  select-all and typed clipboard. Selection tracking runs in frame callbacks;
  the existing SDK menu popup still uses its documented modal loop.
- Two typed keys per frame. Row counters are 16-bit so a 4096-line document does
  not wrap at row 255. Painting follows the same row walk as caret hit-testing.
  Edit damage covers the affected visible suffix (reflow can change later rows),
  with cell-only caret damage; this still needs runtime performance/visual tests.
- New/Load/Close share Save/Discard/Cancel, including Ctrl-Q. The chooser hands
  over its exact named context. Save As requires explicit destination overwrite
  confirmation before any write; cancellation retains the current document.
- Loads stage a complete candidate before publishing its bytes/name/context.
  Error, oversize and cancellation retain the old editor, including dirty text.
  Failed saves retain text and mark it dirty, reporting possible partial disk
  writes. Failed context release retains the handle for explicit retry.
- BASIC saves stream LF-to-CRLF expansion in bounded 512-byte chunks without
  modifying the editor buffer, including a full 4 KiB document and final line
  ending. The old near-capacity fallback to silently writing LF is not retained.
  TXT/CFG raw transfers reuse `gbdocio`. Saving CFG bytes is implemented, but the
  native configuration-cache reload side effect is **not yet portable**.

The staging buffer, clipboard temporary and BASIC transfer chunk share one
phase-exclusive union with the chooser. Its 4096-byte allocation is explicit,
not borrowed from metadata, stack or private RAM. It provides transactional
**load publication**, not atomic disk saves. Public shell launch/adoption/reuse
and configuration reload remain unbound: no private mailbox/cache access has
been reintroduced and this candidate is not registered for File Manager handoff.

### Host checks and limits

`tests/test_unotepad.c` executes the actual integration source with real chooser
and I/O helpers and mocked public filesystem/clipboard/drawing services. The
tests exercise selection/replacement/capacity, 84 wrap widths, >255-row scrolling,
full-capacity BASIC encoding at chunk sizes 1/511/512, dirty close/New routes,
chooser cancellation and real context handoff, overwrite confirmation, failed
clipboard reads, two-key frame bounds and client/caret damage bounds.

Fault injection covers all ten full-size load operations, all nine raw save
operations, and all seventeen full-size BASIC save operations, plus release
failure/retry and a previously clean document's failed save. These are mocked
IO errors, not all provider statuses or actual disk-fault acceptance. Each frame
is checked for at most one filesystem operation; transfers never exceed 512.

Two new host tests and the seven existing I/O/chooser tests pass. Evidence:
`build/notepad-84/evidence/editor-host-final.log`, `editor-docio-regression.log`
and `editor-filepick-regression.log`. Address/undefined-behavior sanitizer linking
was unavailable on the host and in the container (missing libasan/libubsan);
`editor-sanitized-container.log` records that limitation. No sanitizer or emulator
acceptance is claimed for this editor.

### Required next dependency

Final SDCC 4.6.2 full-link result, size optimization/max-allocs 100000:

| Allocation | Bytes / result |
| --- | ---: |
| v4 preamble before code at `0x416C` | 364 |
| Linked `_CODE` | 18604 |
| Startup/finalization | 34 |
| Loaded span from `0x4000` | **19002**, ending `0x8A3A` |
| All data/BSS allocations | **9855** |
| Combined non-overlapping requirement before alignment | **28857** |
| Allowed primary allocation | **16128** (`0x4000..0x7F00`) |
| Total excess | **12729** |

The diagnostic `DATA_LOC=0x6000` deliberately exposes overlap; it is not a
proposed runtime placement. `editor-final-relink.log` and
`build/universal-obj/unotepad/app.map` in the private worktree retain the rejected
result. The builder exits with a fit error and emits **no `NOTEPAD.APP`**.
The unchanged source/object/module portability audit passes separately
(`editor-object-audit.log`); passing that audit does not make the memory map safe.
Final source SHA-256 values:
`main.c`: `0a259a370af143368fe77c02bf855dbddfa73a37e968091f7306d40b6c440f8e`;
`editor.h`: `c16771830c3715b39a175fa1652820066762bb1d8dfe6f48bbb6e1d495e7c55f`.

The failed link is the full source integration, not an extrapolation from the
native editor or chooser diagnostic. Keep the rejected map and logs for budget
analysis; never execute the overlapping image. Moving `DATA_LOC`, removing the
transactional load staging buffer, or shrinking the clipboard/menu scratch
cannot fix an executable image that alone exceeds the primary limit.

Bring forward only the necessary **owned data/secondary-code services** from
roadmap milestone 2, before completing milestone 1:

1. Specify the minimum portable ownership, bounded page-copy and validated
   secondary-entry contracts, using the existing shared allocator/owner policy.
   Review ABI/package changes before implementing or advertising them.
2. Implement and qualify the same policy on MSX and CPC: generation/owner checks,
   page exhaustion/cleanup, stale/foreign/worker/nested-call rejection, and exact
   caller mapping/SP/interrupt restoration. A native bank API is not a portable
   binding and an app must never carry physical page numbers.
3. Partition this actual editor/document UI and staging storage using those
   services; measure the complete package and every primary/secondary allocation.
   Keep the 4096-byte document capacity and the current reserved stack boundary.
4. Complete shell/configuration behavior and the CPC pathname gap, then run real
   editing, reopen/readback, failure recovery, repaint/input and teardown checks
   with identical APP bytes in openMSX/1983 Screen 6/7 and CPC M4/1984.

This is a demonstrated service dependency, not completion of milestone 1 or an
implicit start of all forms/resources work in milestone 2. No new kernel/page
ABI was implemented in checkpoint 2c; checkpoint 2d below is newer.

## Checkpoint 2d — portable owned data pages, 2026-09-09

The approved prerequisite is split into data pages, validated secondary code,
then actual editor partition/acceptance. The first slice is implemented and
qualified in opt-in receiver builds; see [contract, memory and evidence](PORTABLE-PAGES.md).
It reuses the shared generation/owner allocator, accepts DOCUMENT-purpose pages
only and copies at most 512 bytes through fixed scratch. Public APP code never
sees native bank numbers. SDK cost is 283 code + 16 data bytes.

The identical 5004-byte PAGEPRB.APP passes MSX Screen 6/7 in openMSX and 1983
and CPC M4/1984, including full-page roundtrips, exhaustion and three owner
lifetimes with exact page-pool recovery. Twenty-nine focused tests pass.
Default delivery remains unchanged and does not advertise this private option.

This does not remove the code-only link overflow or turn `apps/unotepad` into
a runnable APP. Next is the validated packaged-secondary loader/call gate, then
editor partitioning, shell/configuration bindings, the CPC path-name gap and
actual editing/save/failure/repaint/input acceptance. Keep native Notepad until
the complete replacement passes those gates on both receivers.

## Checkpoint 2e — shared streamed package loader, 2026-09-09

The [secondary-code contract](PORTABLE-SECONDARY-CODE.md) records a bounded
two-segment package and computation-only future call model. Shared structural
admission, whole-stream CRC, secondary allocation/loading and rollback now run
in the actual Z80 instruction fixture: 459 checks at each of two fixed layouts.
No secondary application instruction executes and neither receiver selects the
new path yet. Thirty-one focused tests pass; this is not runtime editor acceptance.

That work also fixed an existing shared dual-icon admission calculation. A
5524-byte dual-icon version of PAGEPRB passes normal single-segment admission
on MSX Screen 6/7 (openMSX/1983) and CPC/M4/1984. See the secondary-code document
for logs/hashes and the distinction between emulator and fixture evidence.

Next: measured receiver placement and single-open MSX/CPC stream adapters,
then normal launch/rollback qualification and the sealed call gate. The current
CPC read-at loader cannot simply stand in for a persistent file stream. Notepad
remains native, the candidate is not repartitioned, and normal media are unchanged.
