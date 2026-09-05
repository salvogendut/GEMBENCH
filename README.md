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

GEOBENCH currently has no active CPC or PCW build, media, or release target. The
last multi-platform tree is preserved on `archive/cpc-pcw-targets`. The first
CPC ABI experiment is parked on `feature/54-reintegrate-cpc`; the
[five-step CPC restart](docs/CPC-RESTART-PLAN.md) begins from working MSX2 with
a feature reference and shared-core extraction. PCW follows as a separate port.
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
