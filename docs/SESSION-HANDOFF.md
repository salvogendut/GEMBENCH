# Session handoff — 2026-09-08

Local working memory saved at the user's request. Read this together with
[the v1.0 roadmap](ROADMAP-V1.0.md) before resuming. Recheck Git and current
files rather than assuming this snapshot remains current.

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

## Git and publication snapshot before milestone 1

- Current branch: `main`, at `1408e512dd976e882a9e1ae24ad712a70bed0aca`.
  Local main matched origin/main after the last merge.
- Settings integration commit: `9c5a7514bdcc53b6d94e86a6af17997b7fde7510`.
- [PR #80](https://github.com/salvogendut/GEMBENCH/pull/80) is merged;
  [issue #79](https://github.com/salvogendut/GEMBENCH/issues/79) is closed.
  Feature branch `feature/79-cpc-settings` was pushed and retained.
- Earlier accepted desktop sprints were merged in PR #78 at `68b1607`.
- Planning documents at this snapshot: new `docs/ROADMAP-V1.0.md`, links added
  to `README.md` and `docs/ROADMAP.md`, and this handoff. The user subsequently
  authorized committing/pushing them, opening a dedicated issue/branch, and
  starting milestone 1's MSX stability checkpoint using both openMSX and 1983.
  Recheck Git and the checkpoint record for publication/progress after this save.
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

**Next proposed implementation: unified Notepad.** Audit actual dependencies
and linked memory first, then migrate the real application and needed services.
Start the application acceptance ledger, establish MSX behavior/stability checks,
migrate through the universal MSX path, then test identical APP bytes on CPC
with real document and failure workflows. Missing services on either target
are in scope.
The next authorized work is milestone 1's stability baseline and migration
inventory, using a mix of openMSX and 1983 on disposable MSX media. Publish the
planning documents first, then follow the user's issue/feature-branch workflow,
not direct feature work on main. Notepad conversion follows this checkpoint;
CPC splash restoration remains milestone 4.

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
  of resuming. No cleanup, new issue, commit, push or release is authorized by
  saving this note alone.
