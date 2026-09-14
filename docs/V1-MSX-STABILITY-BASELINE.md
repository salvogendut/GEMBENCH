# v1.0 M1A — MSX2 stability baseline

Recorded 2026-09-08 on `feature/82-msx-stability`,
[issue #82](https://github.com/salvogendut/GEMBENCH/issues/82).
Production source pin: `9ff0825d77004f9a0380e74b3dc45f3d6d9e772c`.
The baseline and [application ledger](V1-APPLICATION-LEDGER.md) are recorded.
**2026-09-09: issue #82 is closed as a bounded baseline/inventory checkpoint.**
The observed input, firmware and emulator blockers are resolved; this is not
whole-distribution release acceptance. Unified Notepad has started in
[issue #84](https://github.com/salvogendut/GEMBENCH/issues/84), with its
[source/memory audit and document-I/O foundation](UNIFIED-NOTEPAD.md).

## Close-out — 2026-09-09

- [GEMBENCH PR #83](https://github.com/salvogendut/GEMBENCH/pull/83) merged the
  bounded short-button capture fix; main merge `1367593`. Both-mode openMSX and
  1983 regressions retain the original 80 ms Desk pulses. See
  [the implementation record](MSX-DESK-CLICK-INVESTIGATION.md#implementation-and-verification--2026-09-09).
- [RainBIOS PR #171](https://github.com/salvogendut/rainbios/pull/171) merged
  main CHGMOD bitmap forwarding, display/VBlank setup and full-width clear;
  main `e28ff2f`, issue #169 closed.
- The remaining first-VRAM-read discrepancy was an immediate `IN A,(n)`
  timing defect in 1983, not another firmware change.
  [1983 PR #172](https://github.com/salvogendut/1983/pull/172) is merged at
  `c0a0b4a`; 1983 #171 and RainBIOS #170 are closed. The normal 1983 executable
  was rebuilt at that merge. The unchanged corrected RainBIOS ROMs pass the
  original main/direct-SUBROM/MSX1 probes; independent openMSX controls pass.
- Retained evidence: `build/1983-171/.local/evidence/`. The emulator correction
  passes 96 CPU I/O cases, 457 PAL/NTSC first-read positions and all 30 emulator
  test programs. `geobench-mode{6,7}/result.json` passes three accessory
  lifecycle cycles plus 50 short Desk cycles per mode (243/273 checks), final
  one window and maximum stack use 53 bytes. `rainbios-probes-merged-main.log`
  repeats the original firmware probes with the rebuilt merged executable;
  `openmsx-controls.log` records the independent controls.

Use the fixed private MSX images and matching symbols under
`build/msx-buttons-82/evidence/mode{6,7}/`, not its stale initial aggregate image.
The corrected RainBIOS ROMs are under `build/rainbios-170/build/`; their hashes:
main `2c5dd90e6994f409f852312bd1f4fe47439b1e19a9400fa4a8733eaa31727337`,
subROM `7b06e3e10990d2d815cf8b9a640e689167ab47b0f90df821cb48d0e7158049a0`,
Omega `5e6b6ffd0a59fe8154d9743f7bf6ee2306549fd0ae75e6233207a231333114f8`.
No new ROM was imported into 1983's bundled firmware, and no normal MSX/CPC
image was rebuilt. Closing this issue does not qualify those old default ROMs.

Physical/SDL mouse smoothness, 4–6-frame keyboard-pointer gaps, long-duration
stress, hardware, MSX storage faults/exhaustion and the remaining application
coverage below still need release qualification. Carry the existing stability
workload into each migration, adding real document/failure/cleanup checks.
The results below preserve the original pre-fix evidence, not new passes.

## Original baseline: scope and isolation

A fresh complete MSX distribution was built in detached worktree
`build/msx-stability-82`, using the project's SDCC toolchain. No production
kernel, app, CPC adapter, emulator or firmware source changed in this checkpoint.
Changes are test tooling, observer/input synchronization and documentation.

All runtime media are private Sunrise/Nextor hard-disk images. The user's normal
MSX image, accepted CPC image/configuration and CPC diagnostic image were not
rebuilt or reset. Runtime tests did not use floppy media. A build can still
produce the distribution's normal floppy artifacts in the isolated worktree.

Tests steer real keyboard-matrix input and use read-only observations. The 1983
bridge links the unmodified emulator core; it does not inject guest RAM, copy
host-side window policy into the guest, or modify the emulator to make tests pass.

## Original baseline results

Paths below are relative to `build/msx-stability-82/evidence/`. Large local
evidence/media are not committed. This document preserves the conclusions,
artifact identity and reproducible tooling; these are bounded checks, not a
whole-distribution release acceptance.

| Configuration / scenario | Result and evidence |
| --- | --- |
| Fresh MSX distribution build | PASS, `build-msx.log`; existing compiler warnings remain. |
| openMSX, Philips, Screen 6/7 Clock/Calculator | Both modes pass launch, exact accessory activation/reuse, chrome/text/menu, background repaint and close/relaunch. `openmsx-clock-{6,7}-input-ready.log` and `openmsx-clock-{6,7}-ready-repeat-1.log`. **Further repeat failed**, see open findings. |
| openMSX, File Manager window workflow | PASS, `openmsx-window-kinds-mapper-safe.log`: maximize/restore, move/resize and resource menus. One moved, one sized and two maximize messages; exact geometry checked. |
| openMSX, Screen 7 PAINT | PASS, `openmsx-paint.log`: three-pane focus/exposure/move and close. Tool/preview/work focus repaint counts 1/1/0; free pages 22 -> 22; final two owners/windows are Desktop and File Manager. |
| openMSX, Settings Screen 6/7 | PASS, `settings-mode{6,7}-final/result.json`: normal System > Settings, select FANCY titlebar, close, verify actual disk bytes, cold boot and verify reloaded choice/clean close. Separate images for each mode. |
| 1983 core, Philips Screen 6 | PASS, `1983-philips-6-final/result.json`: 82 checks / 8495 frames, three accessory lifecycle cycles, final one window/two busy pages, stack fault zero. |
| 1983 core, Philips Screen 7 | PASS, `1983-philips-7-final/result.json`: 109 checks / 8691 frames, same lifecycle and cleanup. |
| 1983 core, Omega/RainBIOS Screen 7 | PASS, `1983-omega-7-final/result.json`: 109 checks / 8499 frames, same lifecycle and cleanup. |
| 1983 core, Omega/RainBIOS Screen 6 | FAIL: firmware never enters the requested bitmap mode. Not a qualified configuration; see below. |
| Installed 1983 CLI, Omega Screen 7 | Boot smoke only, `1983-cli-mode7.log` and `.ppm`, through frame 3001. This is not the full interactive core suite. |

Host verification: seven new tooling tests, four existing Desk catalog tests
and the compiled actual-Clock exposure regression passed (12 tests, no skips).
The bridge built with warning flags; shell syntax and `git diff --check` passed.

The 1983 cadence measurements use keyboard-pointer movement, not an MSX mouse
or SDL host input. In the final three passing core runs, the idle traverse used
68 frames/63 position changes; Clock-seconds traverses used 71–73 frames/64–65
changes. Maximum observed gap was four PAL frames (80 ms). This is a baseline
measurement, not a newly accepted latency budget or proof of smooth host mouse
movement. Earlier diagnostic runs observed a six-frame gap; retain them too.

### Original findings — resolved as recorded in the close-out above

Follow-up investigation: the Desk loss is now traced to a 135–136 ms interval
between input samples during Clock repaint, enclosing the complete 80 ms click.
See [the investigation record](MSX-DESK-CLICK-INVESTIGATION.md) for both-mode
openMSX traces, 1983 confirmation and the subsequent fix. The findings below
preserve their original discovery evidence; see the dated follow-up above.

1. **Short Desk clicks are not consistently accepted with Clock running.**
   After two successful final-script runs per mode, the next Screen 6 repeat
   failed with `Desk popup did not reach input loop`:
   `openmsx-clock-6-ready-repeat-2.log`. Earlier Screen 7 repeats also failed
   at this boundary. The retained 80 ms title-click pulse is therefore not
   reliably sufficient in this workload. The popup-readiness guard prevents
   an early row click, but cannot repair a title click that never opens it.
   A diagnostic 300 ms-click run passed; that does not close the short-click
   failure or prove whether its cause is guest input latency or test timing.
   Next work: trace input polling/press acknowledgement through the title click
   with background Clock active, fix the demonstrated cause, then repeat both
   modes. Do not increase the duration and call responsiveness fixed.
2. **Bundled RainBIOS does not dispatch main-BIOS CHGMOD mode 6.**
   The same image works with Philips firmware in openMSX and 1983. With the
   bundled Omega/RainBIOS ROM, guest sysinfo says 6 but VDP registers are
   R0=0, R1=`0x72`, R2=0: text mode, not the expected bitmap R0 mode bits 8.
   GEOBENCH's `kernel/msx_stub.asm` requests mode 6 through main-BIOS CALSLT.
   At the ROM's documented source pin `dc95be25177b06d9887ba33cfafa5c01e2697677`,
   `rainbios/src/main_msx1.asm` CHGMOD dispatches 0/1/2/3/7, not 6; its subROM
   implements mode 6 but this main entry does not route there. Evidence:
   `1983-mode6-regs/result.json` and sibling `1983/ROMS/README-RainBIOS`.
   This identifies a firmware compatibility gap, not an established 1983-core
   regression. The user authorized and received
   [RainBIOS issue #169](https://github.com/salvogendut/rainbios/issues/169).
   Firmware implementation/branch and the subsequent 1983 ROM update remain
   separate work; neither repository's source was changed here.

At the original checkpoint these findings kept #82 open. Their subsequent
resolution closes that prerequisite, not the full Notepad milestone.

### Test defects corrected during investigation

- File Manager's maximize test observed the correct rectangle, delayed, then
  reread low addresses during a temporary BIOS ROM mapping. It reported four
  zeros instead of the window rectangle. The settle callback now waits for the
  same RAM mapping before asserting geometry; real incorrect geometry still fails.
- Desk and Settings publish modal state before drawing the menu. Row selection
  now waits until the modal actually reaches `GB_POLL`, using read-only hooks.
- The Clock actor originally held S until acknowledgement after initial drawing.
  A trace showed seconds becoming 1, then 0 again after release: BIOS autorepeat
  had queued additional toggles. It now waits for Clock's first keyboard-input
  call, sends one bounded 300 ms press and observes acknowledgement separately.
  An earlier unsynchronized 80 ms S pulse was missed. Mouse/button pulses in
  the Desk regression remain 80 ms, preserving the outstanding failure above.
- 1983's raw Screen 7 VRAM stores even/odd banks separately, unlike openMSX's
  linear debug view. The border oracle now reads the actual physical banks.
- Settings saves `TITLEBAR=FANCY.TBR`, not `TITLEBAR=FANCY`; the host disk oracle
  checks the complete on-disk value. It reads back after a new emulator boot.

Failed diagnostic logs are retained, not converted to passes. The old
`openmsx-settings-vdi.log` alias-launch script did not reach Settings and is not
counted as coverage; normal System-menu persistence tests replace that scenario
only, not its dedicated colour/VDI assertions.

## Toolchain, firmware and artifacts

- openMSX 21.0, Philips NMS 8250 with 512 KiB expansion and SunriseIDE_Nextor;
  networking disabled. Both kernels use the same universal Clock/Calculator.
- 1983 core source: `5fce06fdb4c5604e96865fceb6670620798051f4`, built locally
  without sibling changes. `1983-core-build.log` records source/binary hashes.
  The separately installed CLI identifies as `1983 0.5.0 (git c01c807)`;
  do not confuse its boot smoke with the newer source-linked core suite.
- Philips main BIOS SHA-256:
  `4bc4ae85ca5f28246cd3e7b7e017d298ddd375603657f84ef2c7954bc2d9b919`.
  Philips subROM:
  `6c6f421a10c428d960b7ecc990f99af1c638147f747bddca7b0bf0e2ab738300`.
- Omega/RainBIOS unified ROM:
  `2cdf2bc23ae489a746b246b31ff8331951ec63203125964c72c512039edc0ff4`.
- Fresh Screen 7 image (`QA/MSX/GBMSX.IMG` inside the isolated worktree):
  `f2500dbdc701f59dd2d4afb6269d775c1bd72fe1eb556ad14daeea2bf88e17f6`.
- Private Screen 6 image (`evidence/mode6/GEOBENCH.IMG`):
  `586f2491a3ee70b5703ff840b85532c82e3413cc4b1a65ef17f089f294dcfea9`.
- Child COMs: Screen 6
  `81e6d7f88d1c6c0f099ba594ac965376d7005e11c97a62c532517104d01638b5`,
  Screen 7 `577e787ff7b1e9c6f8f66cf52c62ca166787f8a1db2ec0c0e6aee25129fc38b8`.

The [application ledger](V1-APPLICATION-LEDGER.md) records migration status,
shared APP hashes, remaining dependencies and tight native memory budgets.
The generated manifest also inventories all staged system modules and savers.

## Repeat the checks safely

Use a separate, freshly built checkout with matching app/kernel symbols and
the test-script corrections in this branch. Do not mix stale normal build
outputs with freshly linked symbols or overwrite accepted CARD/image contents.
Use `my-distrobox` for the toolchain, openMSX and mtools where needed.

From that built checkout, sequentially (each harness makes private media):

```sh
MSX_HEADLESS=1 MSX_TEST_MODE=6 MSX_UNAPI=0 bash tools/test_clock_runtime_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=7 MSX_UNAPI=0 bash tools/test_clock_runtime_openmsx.sh
```

From the current repository, after building `build/msx-stability-82`:

```sh
python3 tools/test_msx_settings_stability.py --built-root build/msx-stability-82 \
  --output build/msx-stability-82/evidence/settings-new-6 --mode 6
bash tools/build_msx_stability_1983.sh build/msx-stability-1983/bridge
python3 tools/test_msx_stability_1983.py \
  --bridge build/msx-stability-1983/bridge \
  --omega ../1983/ROMS/rainbios_omega.rom \
  --sunrise ../1983/ROMS/Nextor-2.1.1.SunriseIDE.ROM \
  --image build/msx-stability-82/QA/MSX/GBMSX.IMG \
  --worktree build/msx-stability-82 \
  --output build/msx-stability-82/evidence/1983-new-7 --mode 7
```

For Philips, supply both `--bios` and `--subrom` paths to the same firmware
used by openMSX. For Screen 6, generate a separate image with
`tools/prepare_msx_stability.py --built-root ... --output NEW_DIRECTORY --mode 6`
and pass it with `--mode 6`. The preparation, Settings and 1983 drivers refuse
existing output directories to preserve previous evidence. Images in the 1983
bridge are mounted read-only; Settings deliberately writes its private copies.

## Coverage still required

No claim yet for physical/SDL mouse smoothness, hardware, long-duration stress,
new MSX storage-fault/exhaustion qualification, all Settings selectors/colour
paths, PAINT Screen 6, networking, savers or the rest of the application suite.
No CPC runtime was repeated: production and shared policy were unchanged, and
the accepted CPC artifacts remain the reference. Future shared-code fixes need
relevant CPC regressions as well as MSX checks.
