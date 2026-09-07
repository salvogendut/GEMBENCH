# CPC restart 3D-T — icons, cursor and backdrop

Issue #77, branch `feature/77-cpc-production-adapters`, 2026-09-07.
Follows [3D-S](CPC-RESTART-STEP3D-S.md) and the
[Clock responsiveness fix](CPC-CLOCK-RESPONSIVENESS.md).
This is an asset-provider checkpoint, **not the complete CPC Desktop**.

## Connected providers

- The actual MSX icon selection/fallback and full/half geometry routines now
  live in shared `kernel/core/icon_*.asm` files. MSX keeps its original binding;
  CPC supplies only storage/publication and Mode-1 rendering.
- `ICONS=REFINED` now genuinely loads the repository's `REFINED.IST` from M4.
  `GB_ICON` and `GB_ICONHALF` use validated directory entries. Full root icons
  preserve pen-0 background pixels; other full icons and middle-band half
  icons are opaque, matching the MSX native contract.
- `CURSOR=<name>` loads the existing CPC masked-sprite representation. The
  normal default is generated from `assets/pointer.png`. Both stored phases
  are loaded; phases 1 and 3 are derived for pixel-position rendering.
- `BACKDROP=<name>` loads a canonical 64-byte, 16x16 Mode-1 tile. Rendering
  uses absolute screen phase, so clipped exposure repairs meet without seams.
  `SOLID`, missing/invalid tiles and unsupported explicit drive selections
  produce the normal solid pen-0 background.
- Root diagnostic **R** applies these assets after the shared config parser.
  Unchanged assets do not invalidate surfaces. Font/icon/tile/frame changes
  mark visual damage; palette-only changes and cursor replacement do not
  demand a desktop repaint. Cursor replacement restores its old save-under
  before publishing new phases and respects explicit hiding.

The normal card stages DEFAULT/REFINED icon packs, DEFAULT.SPR and all four
existing backdrop tiles. It retains the GEOBENCH blue/white/black/red palette
and solid backdrop by default.

## Format and admission boundaries

IST and BDP bytes are shared across targets. **SPR files are not currently
portable assets**: MSX uses its existing 66-byte V9938 two-plane representation;
CPC uses 256 bytes of interleaved mask/data for two 4-byte-wide, 16-row phases.
No new public file format or APP ABI is introduced. CPC rejects MSX sprites
instead of interpreting them as software masks.

All reads use the existing bounded single-volume M4 reader and strict /GBENCH
8.3 path conversion. Candidates are staged in reserved F6; malformed data does
not partially overwrite live F7 assets. The reader's 0x3F00 I/O cap is **not**
an asset allocation: publication checks the smaller destination budget.

| Asset | Admission | Fallback |
| --- | --- | --- |
| Icons | GBIS v2, at least the 21 positional catalogue slots; contiguous directory payloads; widths 1–80 bytes, heights 2–200; exact file extent within 7,680 bytes | Configured → DEFAULT.IST → empty catalogue; invalid slots draw nothing |
| Cursor | Exactly 256 bytes; masks preserve whole Mode-1 pixels; ink never overlaps preserved mask bits | Configured → DEFAULT.SPR → embedded default, keeping recovery input visible |
| Backdrop | Exactly 64 bytes; default mounted volume only | Solid background |

Icon geometry is clipped before traversing bitmap data. In particular, a valid
tall icon at the bottom cannot wrap an 8-bit line counter and draw at the top.
Pointer exclusion uses the effective clipped damage. No raster gaps, ownership
tables, filesystem scratch or application snapshots are used as asset storage.

## Memory and responsiveness

| Allocation | Used / budget |
| --- | --- |
| Fixed resident kernel, including cursor tables/default | 14,583 / 16,384 bytes |
| Support / hardware / scheduler | 1,836 / 3,072; 1,130 / 1,536; 1,446 / 1,536 |
| F7 filesystem module, 4400–6000 | 4,502 / 7,168 bytes |
| F7 icons, 6100–7F00 (after I/O scratch) | 5,284 / 7,680 bytes for REFINED |
| Fixed backdrop, 1880–18C0 | 64 bytes |
| Fixed cursor save-under, 18C0–1900 | 64 bytes |
| Resident cursor phases / embedded fallback | 512 / 256 bytes, included in kernel budget |

Application capacity remains **27 pages including root**; F6/F7 remain excluded.
The larger cursor exposed cadence drift in a background-Clock test. The input
adapter now retains its six-tick deadline through sub-period jitter, resets it
when a whole period is missed, and never loops to replay accumulated movement.
Actual sample timestamps remain separate from the deadline for gap measurement.
The normal polling path also permits time IRQs during software pointer copying,
under the existing scheduler lock. No drawing or input was moved into the IRQ.

The existing video-timed regression passes with 50.0 steps/s idle, 49.6 with
focused seconds, and 47.7 with background seconds. Maximum measured moving
sample gap is 10 IRQ ticks; no stationary sample span was observed. Nine pointer
crossings through active timer damage also pass full-surface pixel checks.
Software-clock IRQ loss remains a separate limitation (background IRQ/video
ratio 0.955); the throughput measurements use video frames, not that clock.

## Validation

- **Full isolated `make check`: PASS**, 230 Python tests without skips plus
  native C, SDK/ABI and distribution checks. Worktree `/tmp/geobench-77t-check`;
  log `/tmp/geobench-77t-check.log`.
- **27 private M4 asset cases: PASS**, including default/custom artwork, a
  valid 200-row icon, malformed directories, missing/default recovery, cursor
  mask/ink admission, all four pixel phases and clipped right/bottom pointers.
  Default/custom cases each include 23 checkpoints with Calculator retaining
  72, native popup save-under, close/drag exposure and filesystem access.
  Logs: `/tmp/geobench-77t-bitmaps-{a,b,c}.log`.
- **Video-timed Clock/input regression: PASS** with the rates above and nine
  pointer crossings, unchanged acceptance thresholds.
  Log: `/tmp/geobench-77t-latency5.log`.
- **Final-image integration: PASS** for ordinary window lifecycle/exposure
  (11 checkpoints), Desk (26), native config/dialogs with a live Clock (23),
  and both missing-root/missing-parser boot rejection paths.
  Logs: `/tmp/geobench-77t-regressions-a2.log` (ordinary window portion) and
  `/tmp/geobench-77t-regressions-b.log`.
- **Clock occlusion/lifecycle (22) and custom-font reload (10): PASS** after
  the observer correction described below. Log:
  `/tmp/geobench-77t-regressions-clock-final.log`. Maximum observed stack use
  across the integration runs is **127/4/6 bytes** (main/IRQ/temporary);
  all guards remain intact.
- **MSX extraction: byte-identical** preemptive Screen 6 (13,956 bytes),
  preemptive Screen 7 (15,534 bytes) and cooperative Screen 6 (13,929 bytes).
  Isolated before/after builds are in `/tmp/geobench-77t-msx.fdB199`; comparison
  logs are `/tmp/geobench-77t-msx-{before,after,other-before,other-after}.log`.
  No new MSX runtime behavior is introduced; this checkpoint does not claim
  a new openMSX run.

The first cursor tests found an incorrect nibble carry in derived phases and
a save-under reservation overlapping native launch state. Both were corrected
before the passing runs. A tall-icon test covers clipped traversal rather than
8-bit row wrap. The ordinary ASCII-input test now uses unbound **B**, because
**A** intentionally changes the gallery; pixel assertions were not removed.
Failed-root-load checks separately verify initialized cursor tables, which are
mutable data inside the loaded kernel image, while retaining code/stack guards.

The longer Clock test exposed an observer assumption, not a new repaint:
a fully covered, suspended worker retained hand second 54, digit second 53 and
a pending digit update. The old observer demanded that this hidden worker run
to finish the update. It now accepts the parked cache only after independently
proving complete foreground coverage and checking both window/task visibility
are zero. Visible/partially visible clocks retain the complete-cache check;
the existing pixel, no-CPU, no-drawing and frozen-snapshot assertions remain.
The added host regression and the other three Clock unit tests pass.

Final identities:

- M4 image: `c0c3af85793a3d620b65cc69f5df594e4feae87ca892e6cf570986c9c0fa1447`
- CPC CORE.RAW: `e44583a89bde9a1b4a9ef370b08e1b3cebd7a5b0b8fe22372686a59b0b4d4b62`
- CLOCK.APP unchanged: `9065baf3bc28430d0c1f90b463507027e3b60795930d814c382e0dfdf1329d96`
- CALC.APP unchanged: `5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5`
- Normal MSX image unchanged: `047a19d38e05f009df8c07a22be90e226a98bc68992fc7474c34015f251ce308`
- 1984 executable unchanged: `00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`

## Manual test

The private M4 image is rebuilt by:

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-runtime
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Click the background with **Space** (arrow keys move the pointer), then:

- **A** toggles a small icon gallery. This is a rendering test, not clickable
  Desktop icons or another shell implementation.
- **V** cycles the four cursor pixel phases, including at the right/bottom edge.
- **R** reloads the unchanged configuration without repainting all windows.
- **F2/F7** open Clock/Calculator. In Clock, **S** enables seconds. Move the
  pointer, overlap and drag windows, then close them to check exposure repair.

`make diagnostic-cpc-bitmaps-1984` exercises custom icons, cursor and a patterned
backdrop using **only a copied image**; it does not change the ordinary manual
card's SOLID default. `--bitmap-case` on `tools/test_cpc_runtime_1984.py` selects
individual admission/fallback cases; `--skip-build` uses the built image.
Do not edit a filesystem image while an emulator has it mounted.

User recordings, `QA/CPC/`, normal MSX media and sibling emulator sources are
untouched. CPC runtime tests use M4 only; this does not qualify Albireo.

## Next

**[3D-U: titlebar/gadget asset modules](CPC-RESTART-STEP3D-U.md)** is now implemented,
retaining shared native furniture
policy and testing fallback, clipping and storage budgets. File pickers,
System/Settings, the complete shared Desktop/File Manager and remaining
application migrations still follow. `GB_RELOAD` stays unavailable until its
complete native contract is implemented; capability masks are unchanged.
