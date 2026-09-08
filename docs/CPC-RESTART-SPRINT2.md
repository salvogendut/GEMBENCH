# CPC desktop sprint 2 — real Desktop delivery

Historical Sprint 2 record. [Sprint 3](CPC-RESTART-SPRINT3.md) extends the same
build target and output directory with File Manager; the root-only limitation
and v1 payload counts below describe the Sprint 2 checkpoint, not later builds.

Started 2026-09-08 on issue #77, branch `feature/77-cpc-production-adapters`,
after Sprint 1 commit `11aecbd`. Part of the
[four-sprint plan](CPC-RESTART-PLAN.md#desktop-first-delivery-update--2026-09-07).

## Scope and acceptance

Deliver the qualified **actual `apps/desktop`**, not the diagnostic launch
surface, as an explicitly built M4 target. Reuse the existing shared core,
native root binding, menus, graphics/input providers and universal apps.
Do not redesign the ABI or enable unqualified native APP loading.

- `make cpc` / `make cpc-desktop` produces `QA/CPC-Desktop/CARD`,
  `GEOBENCH.IMG`, `1984.conf` and a checked build manifest. This new output
  directory avoids overwriting the parked, untracked `QA/CPC/` tree.
- The blue Desktop has Disk C and Clock icons, Desk → Clock/Calculator and
  System → Ram Usage/Tidy Icons/About GEOBENCH. Actual Clock/Calculator support
  launch, exact reactivation, input, focus, dragging and close/menu return.
- Disk C gives an explicit unavailable message. Its File Manager contract
  remains private until Sprint 3; File Manager and diagnostic probe apps/data
  are not staged on the Sprint 2 card.
- M4 acceptance runs use disposable image copies and ordinary input with
  read-only observations: exact pixels, linked code, ownership/pages, contexts,
  memory/bank/IRQ/stack guards. Test the delivered image, not a separately
  configured diagnostic substitute.
- Preserve the default MSX target, its normal media and working app/core code.
  PCW, Albireo and a hardware mouse driver are not claimed by this delivery.

## Work package

1. Add an explicit delivery profile to the existing builder, with checked
   staging and a simple launcher. Keep all diagnostic targets separate.
2. Extend the actual-Desktop acceptance path with both title drags, Disk C's
   visible gate, Clock icon launch/reactivation and title-gadget close.
3. Run host/layout checks and delivered-image M4 acceptance, publish the built
   image for manual testing, and record evidence and remaining limitations.

**Status: Sprint 2 complete — 2026-09-08.** Its defined Desktop-delivery exit
passes; the manual image is built in this workspace. The new build and launcher use the
same native boot binding qualified in Sprint 1, with File Manager admission
still closed. No kernel, app, ABI, compositor or scheduler code changes were
needed for this delivery.

## Manual check (after the image is built)

Use the project's SDCC/RASM toolchain. In this workspace:

```sh
distrobox enter my-distrobox -- bash -lc 'export PATH=/var/home/salvogendut/Dev/sdcc/bin:$PATH; make cpc'
distrobox enter my-distrobox -- bash tools/run_cpc.sh
```

`CPC_EMULATOR` can select another path to the **1984** executable. The launcher
uses the generated M4 configuration, CPC 6128 and 512 KiB, and autostarts BOOT.
It neither rebuilds the image nor edits the emulator's usual configuration.

Pointer input is the qualified keyboard/joystick adapter: **arrow keys** move,
**Space** clicks; hold Space while moving on a title bar to drag. Double-click
Clock or choose it from Desk; enable seconds with **S** while Clock is focused.
Open Calculator from Desk, type digits, switch focus, drag both windows, then
close through their title gadgets or Escape. Check that the Desktop menus and
previously covered pixels return. Disk C currently reports that browsing is
unavailable; this is intentional, not a failed launch.

Rebuilding resets generated media/configuration. Keep personal data and modified
images on separate copies. Unknown files/directories in the generated CARD are
rejected rather than silently carried into a build or removed. Existing
`QA/CPC/`, normal diagnostic cards, MSX media and recordings are not build/test
targets. No floppy emulator testing.

## Validation — 2026-09-08

- The delivered image passes **33 M4/1984 checkpoints**: actual Desktop boot,
  System actions/popups, Calculator input, title dragging of both apps,
  background Clock seconds, focus and exact accessory reactivation, close/menu
  return, Disk C's explicit unavailable dialog, Clock icon launch/reactivation
  and title-gadget close. Full framebuffer/owner/page/context/code/guard checks
  pass; the disposable image is unchanged after the read-only lifecycle.
- All six delivered boot-failure cases pass: missing, truncated and oversized
  `ROOTUI.BIN` and `GBCFG.MOD`. Each private corrupted copy halts before app
  launch, with intact kernel, bank and stack evidence. The original image is
  never corrupted for these tests.
- The manual image's **32 payload hashes** match the isolated tested build;
  all 32 files were also read back from its actual FAT image and verified.
  Binary payloads are reproducible; whole-image byte identity is not promised
  because FAT directory timestamps can vary between builds.
- Observed main/IRQ/temporary stack high-water: **146/256**, **4/256** and
  **6/128 bytes**. Fixed kernel: **15,432/16,384 bytes**. Desktop code:
  **4,809/8,192**, data **143/256**, below the `0x7F00` snapshot. Support,
  hardware, scheduler and filesystem module retain their qualified allocations.
- Clock and Calculator are byte-identical to Sprint 1's CPC/MSX universal
  binaries: Clock `e01b64535507a5c70cf7920d39756f3e05a7affb492bfef9a2c630b7a42b892c`,
  Calculator `5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5`.
  No new openMSX execution is claimed for this app/core-byte-preserving packaging
  change; the MSX default target and normal image remain unchanged.
- Seven new host tests cover the explicit delivery profile, exact app set,
  rejection of wrong/corrupt/unmanaged media, safe staging boundaries and the
  launcher's quoted arguments/missing-image behavior.
- Full `make check` passes: **261 Python discovery tests**, no skips, plus all
  native C, SDK, ABI/layout and distribution checks. The delivered fixed kernel
  is byte-identical to Sprint 1's private Desktop profile. Normal diagnostic
  and MSX image hashes, the 1984 binary, parked `QA/CPC/` and user recordings
  are unchanged.

Acceptance build/worktree: `/tmp/geobench-sprint2-check-qAO4ju`.
M4 lifecycle artifacts: container `/tmp/geobench-cpc-runtime-262b69ov`.
Host logs: `/tmp/geobench-sprint2-desktop-m4.log`,
`/tmp/geobench-sprint2-boot-rejections.log`,
`/tmp/geobench-sprint2-manual-build.log` and `/tmp/geobench-sprint2-check.log`.

Run the delivered-image acceptance test without rebuilding:

```sh
distrobox enter my-distrobox -- python3 tools/test_cpc_runtime_1984.py --desktop-delivery --skip-build
```

`make cpc-desktop-1984` rebuilds first, then runs that same test on a disposable
copy. A pristine build is required for automated acceptance, whereas the manual
launcher does not reset an edited image. Reproduce boot rejection cases from
Python with `test_cpc_runtime_1984.run(desktop_delivery=True, skip_build=True,
root_fault=...)`, choosing `missing`, `short`, `oversized`, `cfg-missing`,
`cfg-short` or `cfg-oversized` and an explicit 1984 executable where needed.

## Next sprint

Sprint 3 promotes the qualified actual File Manager into this delivery: Disk C
browsing, directory/parent navigation, supported app launch and return, with
visible errors and repeated owned lifecycle checks. Keep its private native
contract explicit; do not admit arbitrary native binaries or enable unbound
data-file associations. Complete Settings and broader application parity stay
outside these first-desktop sprints.
