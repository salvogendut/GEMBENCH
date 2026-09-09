# GEOBENCH

GEOBENCH is a native graphical desktop and application environment for the
Omega MSX2. It combines its Z80 kernel, banked application model, and hardware
backends with the
declarative resources and consistent desktop conventions associated with
Digital Research GEM.

This is not an x86 GEM emulator, an AES compatibility layer, or a loader for
historical GEM applications. GEOBENCH borrows interaction and architecture
ideas while retaining a native Z80 ABI and independently implemented BSD code
and artwork.

![GEOBENCH on MSX2 Screen 7](screenshots/MSX-Mode7.png)

## Status

See the [roadmap to v1.0](docs/ROADMAP-V1.0.md) for finishing **both MSX2 and
CPC distributions**: unified application migration on both targets, remaining
CPC feature parity, and separate release qualification. MSX2 is the behavior
reference, not a finished universal distribution; currently only Clock and
Calculator are production apps using the unified ABI.
The plan preserves the accepted CPC desktop's stability while aiming for the
same quality on MSX2, and includes restoring the CPC boot splash.

The repository contains the complete GEOBENCH foundation plus the GEM-inspired
resource, multitasking, ownership, messaging, and compositor work developed
during the archived GEMBENCH phase. The public identity is once again the
original GEOBENCH blue, white, black, and red palette and lollipop logo.

The completed foundation currently covers:

- a compact, bank-safe `.GBR` resource format and deterministic host compiler;
- strict host and allocation-free Z80 validation of resource binaries;
- bounded lookup and navigation of strings, trees, and objects;
- an app-linked Screen 7 runtime for box, text/string, and button objects;
- caller-owned state overlays plus deepest-selectable-object hit testing;
- an MSX2 File Manager association and external `HELLO.GBR` demonstration;
- source-only object IDs, deterministic C-header generation, field objects,
  live text bindings, and cyclic keyboard focus;
- an MSX2 FormRef dialog whose drawing and hit geometry come from embedded GBR;
- a generated MSX2 File Manager View menu with resource-owned labels, stable
  action IDs, checked/radio state, pointer selection, and `F`/`I`/`L` shortcuts;
- an opt-in, non-blocking MSX2 event adapter that combines keyboard, pointer,
  timer, and window-manager activity in one caller-owned record, demonstrated
  by Clock;
- a global allocation-free MSX2 compositor that emits exact visible damage for
  every application, skips fully covered callbacks, repairs the destructive
  drag-outline sweep, and fully refreshes both focus endpoints without repainting
  their bounding box;
- a bounded MSX2 typed-scrap layer for text, bitmap, icon, and file-list data
  that preserves the complete 510-byte raw clipboard and accepts legacy text;
- bounded MSX2 shell discovery and synchronous open/activate/close/quit
  messaging, with File Manager reusing a clean live Notepad instead of opening
  a duplicate;
- a generated, fixed-capacity MSX2 Desk menu whose Clock and Calculator launch
  on demand, reactivate by exact stable ID, and release their mapper page on
  close;
- an app-linked VDI-lite drawing context with semantic pens, bounded clipping,
  packed raster and aligned-text profiles, plus a compact base profile used by
  the MSX2 Settings colour editor;
- opt-in GBR ICON/IMAGE rendering through explicit caller-owned raster
  bindings, without storing pointers or pixel payloads in GBR1;
- a measured MSX2 auxiliary-resource prototype and resident-renderer fit probe,
  with the smaller embedded/app-linked placement retained for GBR v1;
- explicitly versioned MSX2 window kinds with kernel-owned furniture, move,
  resize, and maximise/restore gestures, demonstrated by File Manager;
- a bounded generation-safe deferred application-message FIFO, with Desk
  accessory activation as its first production client;
- owner-aggregated MSX2 visibility scheduling that prioritizes focused and
  visible application workers and parks fully covered visual workers;
- four owner-safe MSX2 filesystem contexts with independent drive, path,
  directory enumeration, and sequential offset state, first used by File
  Manager and advanced in bounded 512-byte calls;
- a machine-checked `GEMBENCH-1` compatibility freeze for the GBR1 and
  managed-window ABIs;
- committed golden data and corruption tests; and
- the canonical GEOBENCH blue, white, black, and red Screen 6/7 identity.

The first resource and managed-window ABI is frozen. New incompatible resource
or window work must cross an explicit version boundary.

## Current build target

- Omega MSX2 at approximately 3.58 MHz
- 512 KiB mapper RAM
- V9938 or V9958 with 128 KiB VRAM
- Screen 7 at 512 x 212 with sixteen colours
- MSX-DOS2 or Nextor
- RainBIOS as a supported validation environment

MSX2 remains the main behavior reference; v1.0 completion targets both MSX2 and
CPC. The experimental **CPC M4 Desktop** is
now available through [Sprint 3](docs/CPC-RESTART-SPRINT3.md), using the same
Desktop/File Manager sources, window manager and portable Clock/Calculator apps:

```sh
make cpc
bash tools/run_cpc.sh
```

Use the project SDCC/RASM toolchain; the sprint document includes this workspace's
distrobox commands. Output is `QA/CPC-Desktop/` (CARD, M4 image and 1984 config),
separate from parked `QA/CPC/` and diagnostics. Arrow keys move the pointer,
Space clicks/drags. Double-click **Disk C**, enter **GBENCH**, then open
**CLOCK.APP** or **CALC.APP**. File Manager's View menu offers Icons/List and
Fullscreen; double-click `..` to go up. `FILEMGR.BIN` is a build-matched native
component, not a portable APP. Data-file associations and file copy/delete are
not yet available. PCW, Albireo and a hardware mouse driver are not yet qualified. Rebuilding
resets generated media; keep personal data on separate copies.

### Earlier CPC diagnostic checkpoints

The last multi-platform tree is preserved on `archive/cpc-pcw-targets`. The first
CPC ABI experiment is parked on `feature/54-reintegrate-cpc`; the
[five-step CPC restart](docs/CPC-RESTART-PLAN.md) begins from working MSX2 with
a feature reference and shared-core extraction. Its isolated
[step-3A M4 hardware probe](docs/CPC-RESTART-STEP3A.md) is available through
`make diagnostic-cpc-foundation-1984`; it does not boot a desktop.
The [3B graphics/pointer proof](docs/CPC-RESTART-STEP3B.md) runs through
`make diagnostic-cpc-graphics-1984`, also using isolated M4 media.
The [3D production-address integration](docs/CPC-RESTART-STEP3D.md) uses
`make diagnostic-cpc-production-1984` to exercise shared context switching,
banking, keyboard/ticks and M4 together. Its
[3D-B drawing/parameter integration](docs/CPC-RESTART-STEP3D-B.md) runs through
`make diagnostic-cpc-drawing-1984`, including shared ownership/parameters and
exact text/line/pointer clipping. The
[3D-C focus/stacking/damage checkpoint](docs/CPC-RESTART-STEP3D-C.md) runs
through `make diagnostic-cpc-windows-1984`, checking the shared compositor
with native fixtures and CPC clipping/pointer adapters. These diagnostics
are not a CPC desktop or loaded application build.
The [3D-D lifetime/cleanup checkpoint](docs/CPC-RESTART-STEP3D-D.md),
`make diagnostic-cpc-lifetime-1984`, adds owner-safe close/quit, message purge
and logical file-context cleanup tests.
The [3D-E registration/chrome checkpoint](docs/CPC-RESTART-STEP3D-E.md),
`make diagnostic-cpc-registration-1984`, uses the same native registration,
window-kind and plain furniture code as MSX, with bounded CPC drawing leaves.
It tests mixed-kind background painting, slot exhaustion/reuse and cleanup;
it does not yet load applications or provide an interactive desktop.
The [3D-F message/timer checkpoint](docs/CPC-RESTART-STEP3D-F.md),
`make diagnostic-cpc-services-1984`, connects the same deferred FIFO,
post-input dispatch phase and app-linked timer collector. Sixteen M4
checkpoints check replies, activation, worker publication and hidden damage.
The [3D-G input/root-loop checkpoint](docs/CPC-RESTART-STEP3D-G.md),
`make diagnostic-cpc-routing-1984`, drives the shared MSX loop and native
focus/menu/move/resize/maximise router through real CPC keyboard input on M4.
It uses fixture windows and a plain bar, not the loaded Desktop applications.
The [3D-H M4 loading checkpoint](docs/CPC-RESTART-STEP3D-H.md),
`make diagnostic-cpc-loading-1984`, tests the shared MSX launch/admission
transaction, file-loaded native registration, corrupt-package rejection and
owner/page rollback.
The [3D-I read-only filesystem-context checkpoint](docs/CPC-RESTART-STEP3D-I.md),
`make diagnostic-cpc-fsctx-1984`, loads the unchanged shared context policy
from M4 and tests independent paths/reads, owner identity, launch handoff and
cleanup. The [3D-J directory checkpoint](docs/CPC-RESTART-STEP3D-J.md),
`make diagnostic-cpc-fsdir-1984`, adds independent enumeration, canonical short
aliases, full-size metadata and batches behind that shared policy. It requires
the 1984 M4 fix merged in PR #290; both the unchanged protocol
probe and the 44-checkpoint directory test pass with that rebuilt emulator.
The [3D-K write/free checkpoint](docs/CPC-RESTART-STEP3D-K.md),
`make diagnostic-cpc-fswrite-1984`, tests shared truncate/append semantics,
interleaved owner readback and independently verified M4 free space.
Those historical fixtures do not yet bind public filesystem/SDK execution;
they are bounded private diagnostics, not a CPC desktop.
The subsequent [3D-L/M/N unified runtime](docs/CPC-RESTART-STEP3D-N.md) now loads
universal APPs, binds portable filesystem contexts and reuses the actual Desktop
bar/application menus on private M4 media. Build it with
`make diagnostic-cpc-runtime`; `make diagnostic-cpc-menus-1984` checks focus and
dropdown restoration. This is still a test launcher, not the full CPC Desktop.
[3D-O](docs/CPC-RESTART-STEP3D-O.md) adds the unchanged MSX Calculator and shared
accessory activation: press **F7** in that M4 runtime, or run
`make diagnostic-cpc-accessories-1984`.
[3D-P](docs/CPC-RESTART-STEP3D-P.md) connects Clock's real worker and shared
timer collector: **F2** opens Clock, **S** toggles seconds, and
`make diagnostic-cpc-clock-1984` checks background updates, occlusion and
pointer save-under. The same updated Clock binary is tested on CPC and MSX2;
the complete Desktop and File Manager remain pending.
[3D-Q](docs/CPC-RESTART-STEP3D-Q.md) adds the real shared **Desk** menu on a
bounded root page: close ABI Probe with **Escape** or click the background,
then choose **Desk → Clock / Calculator**. Run `make diagnostic-cpc-desk-1984`
for its M4 regression. System/Settings, assets and File Manager remain gated;
this is not yet the full CPC Desktop.
[3D-R](docs/CPC-RESTART-STEP3D-R.md) binds shared configuration parsing and basic
native dialogs in a reserved system bank. With the background focused, **U/P/N/I**
exercise popup/prompt/size/About; **R** reparses configuration. Run
`make diagnostic-cpc-native-1984`. [3D-S](docs/CPC-RESTART-STEP3D-S.md) now applies
configured 6x8 fonts, palette/border and contrasting window frames. **R** does
not repaint for an unchanged configuration. Run `make diagnostic-cpc-assets-1984`
for custom-font/theme and reload checks on a copied M4 image.
The [Clock/cursor responsiveness follow-up](docs/CPC-CLOCK-RESPONSIVENESS.md)
adds `make diagnostic-cpc-latency-1984` for video-timed movement and save-under checks.
[3D-T](docs/CPC-RESTART-STEP3D-T.md) connects configured icon packs (REFINED by
default), the CPC cursor sprite and backdrop tiles. With the background focused,
**A** toggles the diagnostic icon gallery and **V** checks cursor pixel phases.
Run `make diagnostic-cpc-bitmaps-1984` for custom artwork and clipped exposure
checks on a private M4 copy. [3D-U](docs/CPC-RESTART-STEP3D-U.md) now connects
configured titlebar/gadget assets through the shared native furniture and a
bounded paged renderer. Run `make diagnostic-cpc-chrome-1984` for custom themes,
focus, dragging and gadget checks. [3D-V](docs/CPC-RESTART-STEP3D-V.md) adds the
shared native file/destination chooser with temporary owned filesystem contexts.
With the background focused, **O/D** exercise it; run
`make diagnostic-cpc-picker-1984` for navigation, readback and restoration checks.
[3D-W1](docs/CPC-RESTART-STEP3D-W.md) reuses Settings' configuration editing with
verified M4 persistence and live reload. On the focused background, **W/E**
save/apply WEAVE/ORIGINAL titlebars; the choice survives restarting the emulator.
Run `make diagnostic-cpc-config-edit-1984` for private-image save/reload/reboot
checks. These keys write the diagnostic image only. The actual Settings window,
System menu, full Desktop/File Manager and native implicit filesystem/reload
contracts remain later integrations.
[W2-A](docs/CPC-RESTART-STEP3D-W2-A.md) isolates the actual Settings platform
bindings and audits its unresolved CPC services/data layout. Run
`make diagnostic-cpc-settings-audit`; it produces no executable or new media.
The [desktop-first delivery plan](docs/CPC-RESTART-PLAN.md#desktop-first-delivery-update--2026-09-07)
groups delivery into four sprints: native services/memory, real
Desktop, File Manager, and stabilization. Sprints 1 and 2 are complete;
[sprint 3](docs/CPC-RESTART-SPRINT3.md) now delivers the usable browsing/launch
workflow, with automated acceptance passed and the manual image rebuilt.
[Sprint 4](docs/CPC-RESTART-SPRINT4.md) is automatically qualified and manually
accepted, completing the desktop-first delivery. Run the rebuilt M4 image with
`distrobox enter my-distrobox -- bash tools/run_cpc.sh`.
Delivered-window, Clock visibility and cursor-cadence regressions start with
`make cpc-stability-1984`.
The combined gate is `make cpc-delivery-1984` (`CPC_TEST_JOBS=4` optionally runs
independent disposable M4 scenarios in parallel). See the sprint document for
results: all 20 scenarios pass, alongside 269 Python tests and MSX regressions.
The desktop-first checkpoint is merged in PR #78. [Settings integration](docs/CPC-SETTINGS-INTEGRATION.md)
is tracked under #79: `make cpc` now includes **System > Settings** in the normal
M4 image (font, icons, cursor, title bar, gadgets and backdrop). Private
storage-fault/stress qualification passed 20 scenarios / 316 pixel checkpoints;
the expanded delivery gate passed all 28 scenarios / 323 pixel checkpoints,
plus 285 host tests and openMSX Screen 6/7 accessory checks. The user accepted
the manual image on 2026-09-08.
Launch the already-rebuilt image with the command above. Escape cancels a selector
or closes Settings; changes persist in the image's `GEOBENCH.CFG`. Rebuilding
resets generated configuration, so copy the image first to preserve preferences.
Palette, wallpaper, savers and reset are not yet part of CPC Settings.
Broader application parity follows separately.
PCW follows as a separate port.
See the [current target state](docs/MSX2-ONLY.md) and the
[universal ABI experiment](docs/UNIVERSAL-APPLICATION-ABI.md).

## Build and check

Run the host checks, including the GBR compiler suite and example build:

```sh
make check
```

Build the fixed-target MSX distribution:

```sh
make geobench-msx
```

To exercise the object runtime, open the first desktop drive and double-click
`HELLO.GBR` in its root. File Manager launches `GBRDEMO.APP`, which validates
the external resource, draws its `HELLO` tree, and toggles the button's selected
state when it is clicked.

Build and automatically exercise the embedded FormRef resource in openMSX:

```sh
make formref
tools/test_formref_openmsx.sh
```

Exercise File Manager's GEM-style window kind, including kernel-owned
maximise/restore, move, resize, and geometry messages:

```sh
tools/test_window_kinds_openmsx.sh
```

Exercise Clock's combined keyboard, pointer, timer, and window subscription,
then prove partially covered component damage cannot alter the foreground and
a fully covered Clock receives no worker CPU or repaint callbacks:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_multi_event_openmsx.sh
```

The equivalent build-and-test target is `make gembench-m8-timer-openmsx`.

Exercise the global visibility compositor through both the Clock occlusion and
multi-window PAINT move/focus workflows:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  tools/test_visible_regions_openmsx.sh
```

Exercise typed copy, atomic type rejection, and accepted text paste through two
real Notepad windows:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_typed_scrap_openmsx.sh
```

Exercise File Manager's launch fallback and live-Notepad reuse through two real
text-document opens:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_shell_service_openmsx.sh
```

Exercise Desk launch, exact Clock/Calculator activation, close-page release,
and relaunch:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_desk_accessories_openmsx.sh
```

Exercise the migrated Settings colour editor and require its VDI calls, managed
editor state, live page, focus, z-order, and final Screen 7 capture:

```sh
make geobench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  tools/test_settings_vdi_openmsx.sh
```

Capture the reproducible pre-GBR baseline under the sibling `1983`
emulator checkout:

```sh
make gembench-baseline-1983
```

Add diagnostic-only scheduler stack and repaint measurements with:

```sh
make gembench-baseline-probes-1983
```

The probe target preserves release artifact measurements in the report and
does not add instrumentation to normal GEOBENCH builds.

Complete the baseline with input-response measurements under three runnable
tasks, using openMSX for the reference pointer result:

```sh
make gembench-baseline-input-1983
make gembench-baseline-input-openmsx
```

The inherited GeoBench build requires RASM, SDCC, mtools, dosfstools, and the
documented MSX dependencies. See [Building and running](docs/BUILDING.md) and
[the MSX2 target](docs/MSX2.md) for setup, deployment, and emulator commands.

Compile a resource directly with:

```sh
python3 tools/gbrc.py examples/hello-dialog.json \
    --output build/examples/hello-dialog.gbr
```

## Documentation

- [Design and estimate](DESIGN-ESTIMATE.md)
- [Approved implementation plan](docs/gembench/IMPLEMENTATION-PLAN.md)
- [Bootstrap validation results](docs/gembench/BOOTSTRAP-RESULTS.md)
- [Current MSX2 baseline](docs/gembench/BASELINE.md)
- [Milestone 7 banking decision](docs/gembench/M7-BANKING-DECISION.md)
- [Architecture Milestone 7 shared services](docs/gembench/ARCHITECTURE-M7-MSX.md)
- [Architecture Milestone 9 visibility-aware compositor and scheduling](docs/gembench/ARCHITECTURE-M9-MSX.md)
- [Frozen GEMBENCH-1 ABI](docs/gembench/ABI-V1.md)
- [openMSX reference validation](docs/gembench/OPENMSX-VALIDATION.md)
- [Baseline measurement workflow](docs/gembench/DEVELOPMENT.md)
- [Visual direction and base palette](docs/gembench/VISUAL-DIRECTION.md)
- [GEOBENCH architecture](docs/gembench/ARCHITECTURE.md)
- [GBR version 1](docs/GBR-V1.md)
- [GeoBench foundation architecture](docs/ARCHITECTURE.md)
- [Development workflow](docs/DEVELOPMENT.md)

## Upstream

GeoBench history is retained in this repository. Developers can configure the
upstream remote with:

```sh
git remote add upstream git@github.com:salvogendut/geobench.git
git fetch upstream
```

The exact bootstrap base and reproduction procedure are recorded in
[the upstream baseline](docs/gembench/UPSTREAM.md).

## Licensing

GEOBENCH is released under the [BSD 3-Clause License](LICENSE). OpenGEM and
FreeGEM remain GPL-licensed references: GEOBENCH behaviour,
code, artwork, and resources must be independently implemented unless separately
reviewed compatible material carries a clear provenance record.
