# CPC restart — Sprint 3: usable File Manager

Started 2026-09-08 on `feature/77-cpc-production-adapters` (issue #77), preserving
the uncommitted Sprint 2 delivery work. This is the third of the four sprints in
[the restart plan](CPC-RESTART-PLAN.md).

## Scope and acceptance

1. Stage the actual `apps/filemgr/main.c` native build beside the real Desktop
   in `QA/CPC-Desktop`. Disk C must open it through the existing build-specific
   filename, exact-size and CRC32 admission contract.
2. Qualify root/directory/parent navigation, Icons/List and saved View, scrolling,
   fullscreen/restore, independent directory windows, and portable
   Clock/Calculator launch/return through ordinary user input.
3. Recheck admission failures and exhausted directory contexts on disposable
   copies of the delivered M4 image, with visible errors and resource recovery.
4. Rebuild the manual image only after the integration passes, record evidence
   and retain the existing MSX and diagnostic media unchanged.

The delivery manifest is `cpc-desktop-m4-v2`: this is a media profile revision,
**not** a new portable application ABI. `FILEMGR.BIN` is trusted native code
bound to this exact kernel build; it is not a universal `FILEMGR.APP`. Ordinary
APP admission remains unchanged. The existing shared application and WM code
are reused, not replaced by a CPC implementation.

Only M4-backed tests are used. Builds reject unmanaged entries in generated
CARD staging; tests write disposable image copies, not the user's card, parked
`QA/CPC`, or normal `QA/MSX`/diagnostic images.

## Deferred

Full application parity, Settings, PAINT, BASIC, file associations, copy/delete,
drag/drop and launching arbitrary native applications are outside this sprint.
Only the qualified portable Clock and Calculator in `/GBENCH` are delivered.
Broader stacking/resize stress, emulator cross-checks and stabilization belong
to Sprint 4. No CPC/PCW universal portability claim is added here.

## Progress

**Complete and manually accepted — 2026-09-08.** The rebuilt manual image was
confirmed working by the user; Sprint 4 stabilization is next.
All **140 M4 runtime checkpoints** and the full host regression suite pass.
No kernel, app, ABI, compositor or scheduler source changes were required.
The user approved committing and pushing the accepted Sprint 2/3 checkpoint
before starting Sprint 4.

## Validation — 2026-09-08

- The regular `cpc-desktop-m4-v2` image passes the **33-checkpoint** actual
  Desktop regression, now including Disk C opening/closing File Manager rather
  than its former unavailable dialog.
- The new **28-checkpoint workflow** covers root/GBENCH/parent navigation,
  Calculator input and return, resource View popup/cancel/List selection,
  scrollbar page/down/up, Icons shortcut, fullscreen/restore, unsupported CFG
  opening/dismissal, Clock launch/seconds/drag, focus return, File Manager drag,
  independent directory windows and clean final Desktop.
- The **15-checkpoint lifecycle** checks repeated opens/closes, owner-generation
  reuse protection, independent paths and Calculator launch/return. The
  **14-checkpoint services** run checks persisted and live View configuration,
  no-op save avoidance, reopen preference, and Clock progress across native
  calls. All checks use ordinary input and inspect exact pixels, code,
  ownership/pages, context state, banks and memory/stack guards.
- **Five cold-reboot checkpoints** pass using a validated copy of the services
  image: saved List preference, directory/parent navigation and close, with no
  new disk writes.
- **Six rejection cases, five checkpoints each**, pass on private corrupted
  images: missing, truncated, oversized and corrupt File Manager; unbound
  kernel contract; and a test-only trusted binary returning without window
  registration. Every case shows an error, restores Desktop state and can
  subsequently launch/close the unchanged portable Calculator.
- **15 context-capacity checkpoints** pass: four independent live directory
  contexts, visible failed View save without disk mutation, session-only View
  change after dismissal, failed fifth File Manager cleanup, capacity return,
  successful reopen and complete final release. The failed-save modal retains
  the old listing while the logical session preference has already changed;
  the test checks those states independently.
- Full `make check` passes: **263 Python discovery tests**, no skips, plus
  native/SDK/ABI/form/window checks. Nine delivery-boundary tests include v1/v2
  profile separation and rejection of incorrect native staging metadata,
  payload hashes and kernel admission bindings.
- Kernel **15,516/16,384 bytes**; Desktop **4,813/8,192 code** and **143/256
  data**; File Manager **13,367/14,336 code** and **1,538/1,792 data**. These
  executable payloads are byte-identical to Sprint 1's private combined
  Desktop/File Manager build. Other resident/module budgets are unchanged.
  Observed stack maxima: **162/256 main**, **4/256 IRQ**, **6/128 temporary**.
- Universal Clock and Calculator match the Sprint 1 CPC/MSX payloads:
  `e01b64535507a5c70cf7920d39756f3e05a7affb492bfef9a2c630b7a42b892c`
  and `5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5`.
  No new openMSX runtime execution is claimed for this packaging-only change.
- The rebuilt manual M4 image's **33 payload hashes** match the tested isolated
  build; all 33 were read back from FAT and checked. Its initial SHA256 is
  `080b085ef28c3098f1d7d6d00af06a3aa0e5eefa73e044b539ca32634a7e99f8`.
  Whole-image identity may change with FAT timestamps or manual View saves.
  The previous generated Sprint 2 directory is retained locally at
  `/tmp/geobench-before-sprint3-DQDlc2/CPC-Desktop`.
- Normal diagnostic and MSX images, `../1984/1984`, parked `QA/CPC` and user
  recordings were not modified. Diagnostic image SHA256 remains
  `cf9c77e1b277eecab608e6e7b8a19e332848fe1b3f34678cd89e2fb9135f48bd`;
  MSX image remains
  `047a19d38e05f009df8c07a22be90e226a98bc68992fc7474c34015f251ce308`.

Local evidence: `/tmp/geobench-sprint3-check-YHtGhV` isolated worktree and
`/tmp/geobench-sprint3-{integration,workflow,lifecycle-faults,reboot,contexts,check,manual-build}.log`.
The initial File Manager test failed on its own initialized-View lookup; the
helper was corrected before the passing lifecycle/workflow runs. The Desktop
result in `integration.log` passed; its later obsolete helper failure is not
counted as a passing File Manager run. The new logical-View assertion also
needed to distinguish a changed session preference from the older pixels
retained behind a failed-save modal; the dedicated capacity rerun checks both.

## Manual and automated checks

With this workspace's toolchain:

```sh
distrobox enter my-distrobox -- bash -lc 'export PATH=/var/home/salvogendut/Dev/sdcc/bin:$PATH; make cpc'
distrobox enter my-distrobox -- bash tools/run_cpc.sh
```

Arrow keys move the pointer; Space clicks/drags. Double-click Disk C, then
GBENCH. Double-click CALC.APP or CLOCK.APP; Escape closes the focused window.
Check that File Manager retains its directory when an app closes. Clock's
**S** shortcut enables seconds. Refocus the directory, use View → List/Icons
(or **L/I**), scroll, toggle Fullscreen (**F**), and double-click `..` to go up.
Opening GEOBENCH.CFG deliberately gives an unsupported-file message; dismiss it
with Escape. Open another Disk C window and verify its path is independent.
View changes update GEOBENCH.CFG on the mounted image; rebuilding resets it.

Repeatable acceptance targets (toolchain required):

```sh
make cpc-desktop-1984
make cpc-filemgr-1984
make check
```

The File Manager target uses a fresh image and separate disposable copies for
its lifecycle, workflow, services, context-capacity and six rejection scenarios.
The services scenario additionally cold-boots a copy of its saved image and
checks List view, directory/parent navigation and read-only close after restart.
To run just the workflow against a freshly built image:

```sh
python3 tools/test_cpc_runtime_1984.py --desktop-delivery --filemgr-scenario workflow --skip-build
```

Use these Python commands inside the distrobox in this workspace. A manually
modified image is rejected by acceptance until rebuilt; it is never silently
reset by `--skip-build`.
