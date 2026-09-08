# CPC desktop sprint 1 — native services and memory

2026-09-07. Issue #77, branch `feature/77-cpc-production-adapters`.
Part of the [four-sprint delivery plan](CPC-RESTART-PLAN.md#desktop-first-delivery-update--2026-09-07),
saved and pushed in `4bfc372`. **Sprint 1 qualification is complete (2026-09-08).**

The exit is checked **complete linked** Desktop/File Manager profiles and
their required native service/launch tests on private M4 media, including
failure cleanup and MSX regressions. Implemented so far: reliable read status,
the File Manager's explicit native provider, complete linked profile and verified
view-preference binding, plus the actual Desktop's complete native profile and
private boot binding. A separate, build-matched File Manager qualification image
now binds Disk C to the shared native launch transaction. Normal APP admission
remains universal-only. Keep remaining work inside this
sprint rather than making each adapter another user-facing milestone.

**Sprint 1: 100% complete; 0% remaining within its defined qualification scope.**
The final capacity/recovery and combined filesystem/configuration/Clock checks
pass. This is not a percentage of total CPC parity: regular Desktop delivery is
sprint 2, the delivered browsing/launch workflow is sprint 3, and stabilization
is sprint 4. The sections below retain the intermediate checkpoint evidence;
the final closure section records the current binaries and regression results.

## Initial joint source inventory

The consumers are the actual [Desktop](../apps/desktop/main.c) and
[File Manager](../apps/filemgr/main.c), not replacements for those programs.
The existing runtime root module uses extracted Desktop menu/bar policy; it
is not the complete Desktop. The current native config, dialog and picker
modules are useful integration consumers, not proof of native APP admission.

| Boundary | Reuse | Work required for the first desktop workflow |
| --- | --- | --- |
| Window ownership, focus, geometry and damage | Qualified shared core and CPC drawing/input providers | Select File Manager's managed-kind, geometry-message and shared menu paths independently of MSX hardware. Its `GB_MSX2` guards currently also select these software features; compiling the old CPC branch of the app would lose them. |
| Directory browsing | Shared FSCTX policy, native C client and M4 directory/batch provider | Bind the actual File Manager's owned directory state and its remaining legacy entry operations. Preserve each window's cursor/path through interleaving. CPC's qualified M4 drive is slot 0 / Disk C. |
| Reads and configuration | Owned contexts, bounded M4 reader, W1 verified edit/reload | Distinguish failed reads from EOF at the shared API boundary. File Manager's `VIEW=` persistence is not one of W1's six appearance keys; bind it explicitly before exposing persistent view changes. |
| Loading and launch arguments | Shared `app_launch.asm`, owner/page rollback, admission validator and bounded M4 loader | Define and check the native system-app profile. The runtime currently admits only qualified universal v4 apps. File Manager also uses legacy selected-entry state; an exact context/path/name handoff must accompany file opening. Do not assume `prepare_launch` alone ties a pending record to a successful load. |
| Root startup and fixed state | Installed CPC scheduler, boot configuration outputs and qualified visual assets | Bind actual Desktop state to the production map. Do not reinstall an app-carried legacy scheduler or rerun old asset installers into borrowed low RAM. |
| Native menus, modal UI and drawing scratch | Existing shared menu/dialog code, serialized F6 modules and owned save-under | Check all linked helper data and callback/scratch lifetimes for Desktop and File Manager. A main-object size or successful module build alone does not establish an APP layout. |
| Application icons | Qualified icon set and canonical CPC bitmap renderer | File Manager's `GBAPICK.MOD` request currently uses legacy fixed addresses/arbitrary module dispatch. Bind a bounded reader/renderer before enabling embedded APP icon probing; don't invoke that old module on the new map. |

Hardware decisions remain separate: CPC geometry is 80 byte-columns by 200
lines; MSX Screen-7 icons, SCRMOD reads and MSX drive metadata must not be
enabled merely to select shared software policy.

### Minimum profile and deferred actions

The first complete workflow needs the actual Desktop surface/icons, Desk and
qualified System actions, actual File Manager navigation, and launch/return
for supported apps, initially Clock/Calculator/ABI Probe. Unqualified file
associations must give an explicit unsupported result. A failed launch must
not leave an owner, page, filesystem context or stale launch argument behind.

Full Settings, savers, wallpaper/PIC paging, trash/delete, cross-window file
copy, arbitrary native modules and return-to-firmware are not prerequisites
for that workflow. This inventory identifies them as remaining dependencies,
not as working services. Gate or visibly omit their actions until qualified;
never substitute successful no-ops. Keep the established solid/tiled backdrop
and boot-selected assets. Full application parity remains tracked separately.

Desktop's legacy wallpaper, chrome and scheduler paths and File Manager's
copy/module paths still reference the old low-RAM layout. Do not make them
runnable by assigning those addresses to the new CPC image. In particular,
the legacy `gb_copybuf` at `0x2200` overlaps current architecture state.

## First implemented binding fix: reliable CPC read status

The shared FSCTX policy previously treated every provider read count as
success. CPC already knew when M4 failed, but the context API discarded that
distinction: even a partially completed multi-leaf read could advance the
offset and look like a valid short read. W1's config editor compensated by
inspecting a private transport-status cell.

The policy now accepts an optional provider `FSCTX_READ_STATUS` hook. CPC
supplies it; the MSX provider is unchanged. The reader stays in the same F7
module, and the real native/universal C clients still use the same shared
marshaling code and caller-identity gates. There is no new storage engine,
request layout, public capability or permissive APP admission exception.

- Successful short read/EOF: status OK, actual count published, offset advances
  by that count (zero at EOF).
- Read failure: status IO, zero published actual bytes, context offset unchanged
  so a retry starts at the original byte. Transfer scratch may contain a prefix;
  the C client does not copy it into the application's buffer on failure.
- Invalid filename, 32-bit offset overflow or oversized transport reply:
  explicitly rejected, never inherited as a stale successful status.
- W1's config editor now checks the common filesystem status alone. Its bounds,
  exact-EOF verification, write/readback checks, cleanup and publication rules
  remain in force. This does not make writes atomic.

The omitted hook preserves the historical MSX behavior, including its native
EOF/error ambiguity. This change therefore does **not** promise identical
failure reporting on every backend; normal shared semantics and the MSX
binary are preserved while CPC exposes its existing transport evidence.

## Initial read-status validation

Automated media were private M4 copies in isolated worktree
`/tmp/geobench-sprint1-check-2yDGVJ`; normal MSX media, diagnostic cards and user
recordings were not test fixtures. Results so far:

- Real reader host tests: exact/short/empty reads, chunk boundaries, errors at
  each of four leaves, retry, invalid name, 32-bit overflow and oversized reply.
  Shared policy tests use independent low/high host state and verify that failed
  prefixes do not advance either owner's context. These mocks do not substitute
  for Z80 or M4 transport tests.
- M4/1984 production context fixture: **48 checkpoints**, including missing
  file versus EOF, retry, interleaved owners, stale generations, one-shot adopt
  and owner cleanup; 64 root/worker/IRQ/storage rounds, intact memory guards.
- Integrated runtime: **46 checks** in the unchanged portable FSPROBE app,
  followed by closing it and checking exposed window pixels/context cleanup.
- Native config integration: missing-file rejection (**6 checkpoints**) now
  requires common I/O status 6 and an unchanged private image/live config.
  Normal save/no-op/readback/live reload (**13 checkpoints**) and subsequent
  reboot/no-op (**6 checkpoints**) pass alongside Calculator and Clock.
- MSX `GBFSCTX.MOD`: before/after binaries are identical, **2,024 bytes**,
  SHA-256 `9ab4d8b625b34d226eb635f3112a7cf86ac8f6eaddc337680caac9b85f83abdc`.
  This is a shared-module regression check, not a new MSX emulator qualification.
- Full `make check`: **244 Python discovery tests**, no skips, plus the native
  C, SDK, ABI/layout and distribution checks pass. Log:
  `/tmp/geobench-sprint1-check.log` on the host.

The integrated runtime's checked allocations are:

| Allocation | Code used / budget | Data used / budget |
| --- | --- | --- |
| Fixed kernel | 15,223 / 16,384 bytes (unchanged) | Existing production map |
| F7 filesystem module | 4,583 / 6,656 bytes | Checked by the module linker |
| F6 config edit | 3,643 / 6,144 bytes | 645 / 768 bytes |
| Diagnostic Desktop bar | 5,092 / 8,192 bytes (unchanged) | 87 / 256 bytes |

The largest observed integrated root stack was **132 / 256 bytes**; main,
IRQ and temporary stack guards, bank restoration, owner state and code checks
passed. These remain runtime-module budgets, **not complete Desktop or File
Manager linked layouts**. No native system-app admission was widened.

Commands used in the isolated worktree, with the project SDCC/SDAS environment
inside `my-distrobox`:

```sh
python3 tools/test_cpc_production_1984.py --variant fsctx --emulator /var/home/salvogendut/Dev/1984/1984
python3 tools/test_cpc_runtime_1984.py --config-edit missing --emulator /var/home/salvogendut/Dev/1984/1984
python3 tools/test_cpc_runtime_1984.py --skip-build --config-edit normal --emulator /var/home/salvogendut/Dev/1984/1984
python3 tools/test_cpc_runtime_1984.py --skip-build --filesystem --emulator /var/home/salvogendut/Dev/1984/1984
```

1984 binary SHA-256:
`00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`.
Raw emulator artifacts are in the container's `/tmp/geobench-cpc-production-6ih3l59r`
and `/tmp/geobench-cpc-runtime-{kggxx8w4,jcy4qzas,1gyknst2,vc5k58rv}`.
These temporary directories are evidence, not required shipped assets.

Normal media remain unchanged: `QA/Diagnostics/CPC-runtime/RUNTIME.IMG`
SHA-256 `cf9c77e1b277eecab608e6e7b8a19e332848fe1b3f34678cd89e2fb9135f48bd`
and `QA/MSX/GBMSX.IMG`
SHA-256 `047a19d38e05f009df8c07a22be90e226a98bc68992fc7474c34015f251ce308`.

## File Manager provider and complete link

The actual `apps/filemgr/main.c` now has an explicit software-feature boundary
in `platform.h`. MSX retains its defaults; the CPC restart profile selects the
same generated View menu, owned directory batches, managed window kind and
geometry-message handling without defining `GB_MSX2`. CPC retains its actual
320x200 geometry and canonical four-colour icon renderer.

The native profile requires preemptive dispatch and checked runtime bindings.
It does not fall through to old CPC low-RAM filesystem, copy, module-probing,
software dragging or window-manager helpers:

- Each File Manager owns its directory context. Listing batches can interleave
  with other contexts; selecting/opening uses an owned entry record, checking
  its name against the listing before acting. Changed entries trigger a relist;
  failed scans discard the partial cache. Lost contexts terminate through the
  normal owner-cleanup request instead of browsing an inconsistent path.
- Config reads use the published native text. View changes call the existing
  verified config editor through `kernel/kc/cpc_filemgr.c`. `VIEW=LIST` and
  `VIEW=DEFAULT` are explicitly admitted alongside the six appearance keys;
  comments/unknown keys, no-op checks, bounds and write/readback rules remain.
  Persistence failure is shown, even though the session's view can change.
- The initial launch binding allows only Clock, Calculator and ABI Probe from
  exactly `/GBENCH`, the current loader's qualified location. Unsupported files
  or locations and failed launches have visible errors. It does not redirect a
  same-named selection from another directory or claim a data-file handoff.
- Copy/drag-drop and embedded APP-icon probing stay disabled. Themed icon-set
  slots are used; no old arbitrary `GBAPICK.MOD` dispatch or borrowed copy
  buffer is linked. These are recorded limits, not a parity claim.

`tools/build_cpc_filemgr.py` links the **complete** main, provider, shared menu,
filesystem client, scrollbar, paged UI stubs and bounded SDK subset against
the composed runtime. It checks retained SDK cells and every linked allocation,
and rejects known legacy dependencies. Its output is `FILEMGR.native.bin` and
`report.json`, **not FILEMGR.APP**; nothing is admitted or staged in the runtime.
This is a fixed native system-app profile, not a compile-once portable APP or
a general machine-code safety verifier.

| Allocation | Used / budget | Boundary |
| --- | --- | --- |
| Complete File Manager loaded image | 13,261 / 14,336 bytes | `4000..7800` |
| Complete File Manager data/BSS/initialized data | 1,538 / 1,792 bytes | Starts `7800`, ends `7E02` |
| Reserved stack snapshot | 256 bytes, untouched by linked areas | `7F00..8000` |
| F6 config editor | 3,721 / 6,144 code; 645 / 768 data | Existing module allocation |
| Diagnostic root/bar including provider test | 5,562 / 8,192 code; 87 / 256 data | Existing root allocation |
| Fixed kernel including two private test keys | 15,234 / 16,384 code | Existing production allocation |

The File Manager has **not run in the emulator**. Its callback/stack lifetimes,
native APP admission, owner rollback and launch/return still require integrated
qualification. The existing diagnostic root merely calls its real save-view
binding for the M4 service test; it is not a replacement File Manager.

### Provider validation

Worktree: `/tmp/geobench-sprint1-native-HF9aQU`. Normal diagnostic/MSX images
and the sibling emulator binary retain the hashes recorded above.

- Host tests include the actual File Manager plus its actual CPC binding,
  generated-menu runtime and scrollbar. Only kernel/storage leaves are mocked.
  They check sorting, interleaved batches, click/double-click navigation,
  changed-entry rejection, launch gates/failure, menu/shortcut view changes,
  persistence failure, moved/sized messages, partial-scan failure, close during
  listing, lost contexts and exhausted context admission.
- Target tests link all helpers, reject shifted SDK cells and a deliberately
  insufficient data allocation, and require an explicit provider. The standalone
  report is also captured in `/tmp/geobench-sprint1-filemgr-link.log`.
- Private M4/1984: **9 view-preference checkpoints**, followed by **7 reboot
  checkpoints**, cover save, restore, no-op, exact live text, no visual damage,
  retained preference, Calculator interaction and subsequent filesystem access.
  Contexts/modal state are released; bank/code/stack guards and pixel checks
  pass. Root stack peaks at **132 / 256 bytes**. Artifacts:
  `/tmp/geobench-cpc-runtime-wjqqn3kq` and `-q8subyiv` in the container;
  host log `/tmp/geobench-sprint1-view.log`.
- The existing appearance save/live-worker/reboot scenario also passes on the
  expanded provider: **13 + 6 checkpoints** with Calculator and Clock, including
  worker resumption, no-op behaviour and intact pixel/bank/stack checks. Artifacts
  `/tmp/geobench-cpc-runtime-xoco8xz1` and `-vtvfvrwn`; host log
  `/tmp/geobench-sprint1-native-config.log`.
- MSX File Manager preemptive and cooperative images remain byte-identical to
  `4bfc372`: **14,762** and **14,804 bytes**. SHA-256 respectively
  `39fedffb1b0d1b9479559f053117b1068e09c5007435385b79ba8b785403727c`
  and `bf7b48193ab93456039340b94f068e7b4cbb414767a59dd597430a2da84d3d9c`.
- Final full `make check`: **248 Python discovery tests**, no skips, plus all
  native C, SDK, ABI/layout and distribution checks pass. Log:
  `/tmp/geobench-sprint1-native-check-final.log`. Two build tests in the first
  run had loaded an earlier, incomplete root harness binding; the complete
  suite was restarted after fixing it and passed against the final sources.

Reproduce with the project SDCC/SDAS environment inside `my-distrobox`:

```sh
python3 tools/build_cpc_filemgr.py --output /tmp/cpc-filemgr-link
PYTHONPATH=tests python3 -m unittest test_filemgr_platform test_cpc_config_edit -v
python3 tools/test_cpc_runtime_1984.py --config-edit view --emulator /var/home/salvogendut/Dev/1984/1984
```

Run media-building tests in an isolated worktree. The view test uses private
M4 copies, but its build step first regenerates that worktree's diagnostic card.
After rebuilding diagnostics, root-only **L** saves List and **B** saves Icons;
these write the mounted diagnostic configuration, like the existing W/E keys.
The normal image in the user's checkout has **not** been rebuilt this time.

## Actual Desktop profile and private root binding

The actual `apps/desktop/main.c` now selects its software features through an
explicit provider, just as File Manager does. Its CPC profile does not define
`GB_MSX2`, reinstall the scheduler, invoke legacy chrome/wallpaper installers,
or borrow old CPC filesystem/copy addresses. It uses the boot-applied native
config, backdrop, font, REFINED icons and existing shared window manager.

`tools/build_cpc_desktop.py` links the complete Desktop, native service leaves,
shared `gbdoc` menu helper, paged UI stubs and bounded SDK subset. The private
boot binding validates the already-owned root, page, focus, descriptor bounds,
geometry and callback ranges before publishing callbacks. It preserves the
root owner/generation and returns to the existing kernel loop. There is no
second root registration, app-carried scheduler or new public ABI entry.

| Allocation | Used / budget | Boundary |
| --- | --- | --- |
| Complete native Desktop code/initializers | 4,809 / 8,192 bytes | `4000..6000`, padded boot payload |
| Complete Desktop data/BSS/initialized data | 143 / 256 bytes | `6000..608F`, limit `6100` |
| Reserved stack snapshot | 256 bytes, untouched by linked areas | `7F00..8000` |
| Private-profile fixed kernel | 15,432 / 16,384 bytes | Existing production allocation |

The default builder remains link-only. `--integration-image` explicitly composes
a separate `QA/Diagnostics/CPC-desktop-contract/RUNTIME.IMG`; it does not change
the normal experimental launcher or admit native APP files. Its root is the
actual Desktop, not the earlier extracted bar/menu test component.

The minimum profile exposes Desk's Clock/Calculator and System's Ram Usage,
Tidy Icons and About. Disk C is visible but explicitly reports that File Manager
integration is pending. Trash, Settings, savers, media refresh/hotplug and exit
are not exposed. Wallpaper/PIC loading and embedded application icons remain
deferred. Icon dragging and broader Desktop delivery interactions still need
sprint 2 qualification; this is not a claim of complete Desktop parity.

Native integration fixes keep policy in the actual app/shared helpers:

- Refresh the Desktop menu before arming the first input event after refocus;
  the shared root loop dispatches input before the frame callback.
- Repaint a deselected root icon through bounded compositor damage when a
  child covers it, rather than drawing the root directly over that child.
- Repair an exposed top bar without committing a partial-clip clock/menu
  cache. Preserve the optional RAM footprint through bar exposure/refocus;
  do not repaint that label every idle frame.
- Build shared helpers with the existing qualified native-module compiler
  settings. Raising `gbdoc`'s allocation-search limit to 5000 caused the project
  compiler to generate an incorrect `g_nitems[i]` store. M4 observations caught
  zero-item popup requests; the test now checks real item counts and labels as
  well as final pixels. The shared menu source was not rewritten as a workaround.

### Desktop qualification

The host test includes the actual Desktop, its CPC service leaves and `gbdoc`;
only kernel/device calls are mocked. It checks startup, menu publication,
identity-first activation, capacity/missing-app errors, icon actions, System
actions, deferred About, refocus and clipped bar/selection repair. Target tests
link every helper and reject missing providers, shifted SDK cells, wrong boot
profiles and insufficient data allocations.

Private M4/1984 checks cover boot, actual menu contents, Calculator input,
Clock seconds/background work, focus/reactivation/close, System actions and
pixel restoration. They check root identity, owner/page release, modal/context
cleanup, linked code integrity and stack guards. Missing, short and oversized
root modules halt before application launch with intact kernel/stack guards.

The combined scenario passes **26 checkpoints**, with observed stack peaks
of **146 / 256 main**, **4 / 256 IRQ** and **6 / 128 temporary bytes**. Artifacts:
container `/tmp/geobench-cpc-runtime-f3tz2k19`; host log
`/tmp/geobench-sprint1-desktop-m4-system.log`. Boot rejection artifacts are
`/tmp/geobench-cpc-runtime-{xxom28hf,g9169d09,v3j8j61f}`; host log
`/tmp/geobench-sprint1-desktop-reject.log`. The final private image was then
regenerated with the normal integration builder; all **40 staged file hashes**
match its manifest. The padded 8,192-byte Desktop boot payload SHA-256 is
`5cf6e01e83ade908bb3504ffef0a73eebe4c4adad0eb853b99aebc4435bcd9bd`.

Final full `make check` passes: **250 Python discovery tests**, no skips, plus
all native C, SDK, ABI/layout and distribution checks. Host log:
`/tmp/geobench-sprint1-desktop-check-final.log`. The first full run exposed two
test-harness assumptions (one refresh-fragment use and UTF-8 preprocessor
output); both were corrected and the entire suite rerun successfully.

Both MSX Desktop builds remain byte-identical to the pre-change reference:
preemptive **15,147 bytes**, SHA-256
`552199b90097c7a6c5ee398152c0f1c0b15ea952f986a7e86d747ddc10e1abe5`;
cooperative **13,560 bytes**, SHA-256
`217a2b431f17eb34b38aaea10d1a1bf1e1cbca8d499e0a197301538360a19764`.
This is a binary regression comparison, not a new MSX emulator run.

Reproduce in an isolated worktree with the project SDCC/SDAS environment:

```sh
python3 tools/build_cpc_desktop.py --output /tmp/cpc-desktop-link
PYTHONPATH=tests python3 -m unittest test_desktop_native -v
python3 tools/test_cpc_runtime_1984.py --desktop --emulator /var/home/salvogendut/Dev/1984/1984
```

The last command builds only the separate private Desktop contract image and
tests a disposable M4 copy. Normal user/diagnostic/MSX media are unchanged.

## Native File Manager loading and lifecycle

The private `CPC-filemgr-contract` image adds the actual File Manager to the
actual Desktop boot profile. Disk C calls the existing `k_wm_open` transaction;
the shared owner/page allocation, registration, focus, callbacks, rollback and
close paths are unchanged. There is no alternative CPC file browser or WM.

Admission is intentionally narrow and **not a new public APP format**:

- Only the explicit `CPC_NATIVE_FILEMGR` integration build has this gate.
  The default runtime and the Desktop-only image remain universal-only.
- Only `/GBENCH/FILEMGR.BIN`, addressed by its exact 11-byte name, enters it.
  Every other application still passes the existing v4 validator/receiver.
- The complete native app links against this kernel's checked bindings. After
  verifying the linked image's size and SHA-256 against its layout report, the
  builder patches six reserved bytes in the kernel: exact length plus CRC32.
  No kernel code addresses move after linking. An unbound/zero contract fails
  closed; mismatched sizes or contents cannot reach the application entry.
- This fingerprint detects corrupt or mismatched builds. It is **not signature
  verification or a security sandbox for hostile native code**.

The profile does not implement an arbitrary file/path launch handoff. A new
File Manager starts at Disk C root; each instance owns its subsequent path and
directory cursor. The already-gated `/GBENCH` Clock/Calculator/ABI Probe binding
remains the only supported selected-application launch path. Unsupported
locations and data files remain explicit errors, not silently redirected opens.

| Allocation | Code used / budget | Data used / budget |
| --- | --- | --- |
| Fixed kernel, native File Manager profile | 15,516 / 16,384 bytes | Existing production map |
| Actual Desktop, Disk C enabled | 4,813 / 8,192 bytes | 143 / 256 bytes |
| Actual File Manager | 13,261 / 14,336 bytes | 1,538 / 1,792 bytes |

File Manager code starts at `0x4000`, data at `0x7800`, and the allocation ends
at `0x7F00`, below the scheduler snapshot. The scheduler, hardware, support and
F7 filesystem allocations remain unchanged. The File Manager binary SHA-256
is `3de8ef3b76993e1678e0edb2950e7b3c8218ec18f60d56fa9e64743623d2db35`;
its private contract is `cd3353673ef6` at `0xA22E` in this build.

### Qualification

All emulator scenarios use disposable **M4** images and actual keyboard/pointer
input in unmodified 1984. They do not patch guest RAM, call app entry points from
the debugger, or mount user cards. The oracle derives sorted names, icons,
scrollbars, paths and free-space titles from staged files and FAT metadata,
then checks the complete framebuffer independently of guest drawing code.

The lifecycle run passes **15 checkpoints**: Desktop boot, three
open/close cycles with fresh owner generations, browsing `/GBENCH`, a second
File Manager starting at root while the first retains its path, and closure/
exposure restoration. It also launches the unchanged portable Calculator from
the first File Manager, enters `72`, and returns to the same `/GBENCH` window.
Each File Manager owns exactly one context; every close
releases its context and code page. Native code, pending owner/launch argument,
fixed allocations, ROM/bank state and stack guards are checked throughout.

Six disk-fixture rejection cases also pass: missing, short, oversized, corrupt,
unbound and non-registering payloads. The last case deliberately binds a trusted
test payload that returns before registration, exercising rollback *after*
admission. Failures leave only the root, restore its pixels/menu, release the
temporary owner/page and leave no filesystem context or pending launch argument.
Each case then opens and closes Calculator normally: **5 checkpoints per case,
30 total**, with a maximum **146 / 256 main-stack bytes**, **4 / 256 IRQ bytes**
and no temporary-stack use. Host log:
`/tmp/geobench-sprint1-filemgr-reject-final.log`; container artifacts:
`/tmp/geobench-cpc-runtime-{xwmn7eke,h14blc5f,3_gnona7,_y1l7_r7,zfwcovc7,5e9z426d}`.
The normal lifecycle run observes at most **115 / 256 main-stack bytes**,
**4 / 256 IRQ bytes** and no temporary-stack use, with intact guards.

The normal run's artifacts are in container
`/tmp/geobench-cpc-runtime-nl9fein1`; host build/test log:
`/tmp/geobench-sprint1-filemgr-final-m4.log`. All **41 staged files** were read
back from the private image and match its manifest hashes. The normal
diagnostic/MSX media and emulator binary retain the hashes recorded above.

Host checks cover the actual Desktop's Disk C enabled/disabled providers and
error paths; contract binding checks reject wrong profiles, changed binaries,
invalid patch sites and oversized images, and permit identical rebinding
without modifying anything outside the six-byte contract.

Full `make check` passes: **253 Python discovery tests**, no skips, plus all
native C, SDK, ABI/layout and distribution checks. Host log:
`/tmp/geobench-sprint1-filemgr-check.log`. This checkpoint changes only the CPC
private loader/provider and test/build tooling; shared launch/admission policy
and the MSX app sources are unchanged from the byte-regressed state above.
No new MSX emulator run or public native-APP compatibility claim is implied.

Reproduce with the project SDCC/SDAS environment in an isolated worktree:

```sh
python3 tools/build_cpc_filemgr.py --integration-image
python3 tools/test_cpc_runtime_1984.py --filemgr --skip-build --emulator /var/home/salvogendut/Dev/1984/1984
python3 tools/test_cpc_runtime_1984.py --filemgr-case corrupt --skip-build --emulator /var/home/salvogendut/Dev/1984/1984
```

Other rejection choices are `missing`, `short`, `oversized`, `unbound` and
`no-register`. The integration builder stages only the separate private
`QA/Diagnostics/CPC-filemgr-contract` media. Running the builder without
`--integration-image` remains link-only. This does not replace the normal
diagnostic launcher or turn `make cpc` into a delivered Desktop target.

## Final combined qualification — 2026-09-08

The actual Desktop/File Manager profile passes **52 additional checkpoints**
through ordinary input on disposable M4 images in unmodified 1984:

| Scenario | Checks | Evidence |
| --- | --- | --- |
| `contexts` | 15 | Four simultaneous owned directory contexts; View save fails visibly without writing when its temporary context cannot be allocated; the session-only view remains usable. A fifth File Manager registers, reports its missing required context, then releases its owner/page/window after dismissal. Closing an existing instance allows a fresh successful open. |
| `windows` | 23 | Root, four File Managers and three portable ABI Probes fill all eight window/owner slots. The next launch fails visibly without leaking pages or arguments; closing a File Manager allows reopening. Every app then closes cleanly, with exact exposure/selection pixels. |
| `services` | 14 | Actual File Manager switches Icons/List, persists `VIEW=`, skips an unchanged request, browses `/GBENCH`, closes and reopens with the saved view. Clock seconds continue in a partially exposed window. Module calls preserve the File Manager owner, directory and live configuration; returning/exposing Clock leaves no stale hands. |

Every checkpoint verifies the complete framebuffer, focus/z-order/menu, owned
directory contents/path, native code integrity, free-page accounting, pending
launch cleanup and production memory/bank/IRQ/stack guards. Maximum observed
main stacks are **153/256**, **158/256** and **146/256 bytes** respectively;
IRQ use is **4/256**, temporary use at most **6/128**. These are observed
high-water marks for these scenarios, not a proof of all possible call chains.

### Capacity coverage boundary

This profile has 27 application pages, eight owner/window slots and four
directory contexts. Each admitted app uses one primary page. Public buffer-page
allocation and secondary code remain disabled (`CPC_RUNTIME_CAPS_LOW=0x0F8B`,
without the `0x0040` allocator capability), so ordinary input reaches the window
or context limit before exhausting all 27 pages. The tests check the real
reachable limits and page reclamation at every checkpoint, including failure
*after* registration. They do not claim a naturally reached full-page pool.

The underlying allocator's owner/page exhaustion and recovery were exercised
by the actual M4 [3D-H shared launch gate](CPC-RESTART-STEP3D-H.md); that core is
unchanged. Enabling a new allocator or injecting guest RAM merely to fill the
pool is outside this profile. Requalify this limit when additional page-using
apps/services are admitted.

### Shared repaint fixes found by the combined tests

- Portable Clock's partial exposure repaint advanced its global time cache
  while pixels outside the clip still showed the old hands. It now reconstructs
  the completed hand/digit passes without advancing either cache; the next
  focused/timer update erases the actual old pixels. Focused catch-up also checks
  pending digits, not just hands. A host test executes the actual Clock renderer
  with a clipped surface and reproduces both cases.
- Preemptive File Manager cleared its selection state before launching a child, leaving
  the visible frame behind. Clearing the frame with the background pen also
  erased overlapping filename pixels. Selection removal now restores just the
  old cached icon cell before launch, using the same cell renderer as the grid.
  MSX's normal preemptive idle probe revisits an embedded icon if necessary;
  selection painting does not perform inline I/O in that profile. The optional
  cooperative profile retains its compact legacy selection behavior; the new
  repair otherwise exceeds its nearly full code allocation. This fix covers
  production MSX and the new CPC shared-preemptive profile, not cooperative UI.

These are fixes in the shared applications, not alternate CPC repaint policy.
No compositor, scheduler or emulator changes were needed. Host File Manager
coverage checks one-cell selection repair and the intended child launch.

### Final layouts and regressions

File Manager now uses **13,367/14,336 code bytes**, with unchanged
**1,538/1,792 data bytes** and `0x7F00` snapshot boundary. SHA-256:
`7d7ed464e63d41c8ba35925f718fb3377f70f5654d811b418202bbd25f6aee50`;
private length/CRC contract **`373429173230`**, still at `0xA22E`.
Desktop remains **4,813/8,192 code**, **143/256 data**; fixed kernel remains
**15,516/16,384 bytes**. All **41 staged file hashes** match the final private
M4 image manifest.

Full `make check` passes: **254 Python discovery tests**, no skips, plus native
C, SDK, ABI/layout and distribution checks. A complete isolated MSX build also
passes. The shared File Manager and Clock binaries intentionally change with
the repaint fixes; earlier byte-identical comparisons above describe the
preceding provider-only checkpoints, not these final app changes.
The production MSX File Manager links at **14,619 bytes**; the optional
cooperative link fits at **14,654 bytes**, retaining its legacy selection path.
Host log: `/tmp/geobench-sprint1-filemgr-cooperative.log`.

Clock's exact same universal binary is built for CPC and MSX, SHA-256
`e01b64535507a5c70cf7920d39756f3e05a7affb492bfef9a2c630b7a42b892c`.
The openMSX Clock/Desk lifecycle regression passes in **Screen 7 and Screen 6**:
respectively **7,480/7,483 worker calls**, **48/50 timer-source fragments** and
**24/25 clipped rim repairs**, with intact window/menu/owner/stack checks.
The harness now waits for an observed visible, unfocused Clock repaint before
Calculator can cover it. Its previous fixed delay could miss that evidence;
the bounded wait uses read-only probes, not guest-state injection or relaxed
acceptance checks.

Host evidence logs:

- `/tmp/geobench-sprint1-{contexts,windows,services}-verified.log`
- `/tmp/geobench-sprint1-final-check.log`
- `/tmp/geobench-sprint1-msx-build.log`
- `/tmp/geobench-sprint1-msx-final-verified.log`

Reproduce the new M4 scenarios after the integration build above:

```sh
python3 tools/test_cpc_runtime_1984.py --filemgr-scenario contexts --skip-build --emulator /var/home/salvogendut/Dev/1984/1984
python3 tools/test_cpc_runtime_1984.py --filemgr-scenario windows --skip-build --emulator /var/home/salvogendut/Dev/1984/1984
python3 tools/test_cpc_runtime_1984.py --filemgr-scenario services --skip-build --emulator /var/home/salvogendut/Dev/1984/1984
```

Actual File Manager persistence here covers close/reopen; the earlier W1
provider reboot test is separate evidence, not a new full-app reboot scenario.
Arbitrary path/data-file handoff, embedded icon probing on CPC and the other
deferred actions remain gated. No Albireo or floppy emulator qualification is
claimed. Normal diagnostic/MSX images and the emulator binary retain their
recorded hashes; `QA/CPC/` and user recordings remain untouched.

## Handoff to sprint 2

Promote the qualified actual-Desktop profile into a reproducible, explicitly
staged M4 Desktop target with manual boot instructions, correct Disk C/icons,
Desk and qualified System actions, and real Clock/Calculator launch/activation.
Use the existing shared app/core/providers; do not start another CPC Desktop.
Keep the private File Manager contract distinct until sprint 3's delivered
browsing/launch workflow is qualified. This sprint's passing private image does
not by itself turn the regular CPC target into that delivery.
