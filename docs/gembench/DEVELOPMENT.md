# GEMBENCH development

The repository combines the GeoBench runtime and build system with GEMBENCH
format contracts and host tooling. GeoBench-specific toolchain and emulator
details remain authoritative in `docs/DEVELOPMENT.md` and `docs/BUILDING.md`.

## Requirements

- Python 3.11 or newer
- GNU Make
- RASM and SDCC for target builds
- mtools and dosfstools for generated MSX media

The host resource compiler requires no third-party Python packages. The full
MSX distribution also uses the sibling GB-PAINT and GB-BASIC repositories and
the dependencies documented by the inherited GeoBench build.

## Commands

Run all current validation and build the example resource:

```sh
make check
```

Run only the GBR compiler tests:

```sh
make gbr-check
```

This runs the compiler and golden-file tests, corruption checks, portable
target-reader and object-runtime tests, and SDCC Z80 compile/size checks. Verify
an individual binary with `python3 tools/gbrverify.py path/to/resource.gbr`.

Rebuild only the example resource:

```sh
make gbr-example
```

Generate the static pre-runtime size and headroom report from the staged MSX
distribution:

```sh
make gembench-baseline-report
```

Boot the generated 32 MiB IDE image through the Sunrise Nextor ROM in the
sibling `1983` checkout and add guarded mapper and VRAM boot telemetry:

```sh
make gembench-baseline-1983
```

The target first runs the normal `gembench-msx` build, then writes a
machine-readable JSON report, a Markdown report, the raw emulator log, and a
desktop screenshot under `build/baseline/`. Override `--sunrise-rom` or
`--ide-image` when invoking `debug/gembench_baseline_1983.py` directly if the
sibling checkout uses different paths. A non-zero emulator exit after the
telemetry line is tolerated because a read-only host configuration can prevent
RTC persistence after the guest has completed.

Capture the scheduler stack high-water mark and one full plus one
damage-limited repaint sample with:

```sh
make gembench-baseline-probes-1983
```

This target first records the ordinary release artifacts, then rebuilds the
desktop with `GEMBENCH_BASELINE=1` and the existing preemptive TASKDEMO stress
workers. The diagnostic timer uses the MSX2 RP-5C01 seconds-test clock at
16,384 Hz, giving a 5.27-second unambiguous measurement window. The target uses
a disposable RTC because the accelerated clock changes its visible time. The
diagnostic code and TASKDEMO apps are absent from a normal `make gembench-msx`
build.

Measure pointer and keyboard response with the same three runnable tasks:

```sh
make gembench-baseline-input-1983
make gembench-baseline-input-openmsx
```

The 1983 target injects a real keyboard-matrix event at a fixed frame and
records its visible desktop acknowledgement. Its current headless interface has
no scripted pointer-motion source. The openMSX target therefore performs two
reference runs, driving both pointer and keyboard through matrix events and
requiring visible VDP/UI changes before acknowledging either response.

Build the fixed-target distribution:

```sh
make gembench-msx
```

The MSX build stages `HELLO.GBR` in the drive root and `GBRDEMO.APP` in
`/GBENCH`. Open the first desktop drive, then double-click `HELLO.GBR` to test
the real File Manager association and external-resource path. Clicking the
resource-defined button toggles its selected state.

The same release path can be driven automatically in openMSX with
`debug/gbr_object_openmsx.tcl`; the complete command and reference result are
recorded in [OPENMSX-VALIDATION.md](OPENMSX-VALIDATION.md). Use absolute output
paths when openMSX is installed as a Flatpak.

Build and exercise the resource-driven FormRef vertical slice with:

```sh
make formref
tools/test_formref_openmsx.sh
```

The test makes a disposable IDE image whose root-level `A.APP` is byte-for-byte
identical to the built `/GBENCH/FORMREF.APP`. It launches the app through File
Manager, traverses the GBR-defined modal from Name through Autosave and the two
layout choices, and asserts the resource descriptor, keyboard focus actions,
checkbox toggle, exclusive radio selection, default Save commit, and modal
restore.
Set `MSX_HEADLESS=1` to run every logic assertion with renderer-dependent
screenshots disabled.

The release MSX2 Calculator is the first production panel migrated to GBR. Run
`make gembench-msx`, launch `CALC.APP`, and verify that pointer activation and
keyboard arithmetic agree; its twenty button labels and hit rectangles now come
from `apps/calculator/calculator.json`. CPC and PCW deliberately keep the prior
panel path as compatibility controls.

Exercise the first explicitly registered MSX2 window kind with:

```sh
make gembench-msx
tools/test_window_kinds_openmsx.sh
```

The openMSX driver opens File Manager through the real desktop, selects List
through the generated View popup, verifies `I`, `L`, and `F` shortcuts plus
checked/radio transitions, then uses MSX keyboard-matrix pointer input to
maximise and restore it, drag its title, and resize its kernel-drawn grip. It
verifies the live geometry and observes the
`GB_MSG_MOVED`, `GB_MSG_SIZED`, and `GB_MSG_MAXIMIZED` callbacks. The final
Screen 7 capture is written to `build/msx/window-kinds.png`.
`MSX_HEADLESS=1` retains the geometry and message assertions without requesting
the capture.

The menu source is `apps/filemgr/view_menu.json`. The MSX build compiles its
ordinary frozen `.GBR` for verification and a code-only `view_menu_gbr.h` for
the app-linked runtime. A malformed `GBRM` descriptor fails atomically before
registering a top-bar title. CPC and PCW retain their existing `gb_doc` menu
path because adding the MSX runtime would exceed their 16 KiB File Manager page.

Exercise the non-blocking multi-event production slice with:

```sh
make gbevent-check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_multi_event_openmsx.sh
```

The disposable-image driver launches the byte-identical built Clock through
File Manager. It verifies that timer frames continue, `S` reaches the keyboard
class and toggles seconds, pointer movement is observed, and a real pointer
click reaches Clock without losing the associated window callback.

Use 1983 as the complementary boot, mapper, and image-layout integration check:

```sh
python3 debug/gembench_baseline_1983.py \
  --ide-image QA/MSX/GBMSX.IMG \
  --output-dir "$PWD/build/window-kinds-1983" \
  --frames 6000
```

The milestone-6 build measures 12,260 bytes for the resident Screen 7 kernel
and 13,244 bytes for the migrated File Manager, leaving 2,884 bytes of loader
headroom. The kernel increase is 768 bytes; File Manager is 1,401 bytes smaller
because it no longer links the app-owned window gesture helpers.

Generated files live under `build/` and are ignored by Git.

## Resource changes

The `.GBR` binary layout is a target ABI. When changing it:

1. update `docs/GBR-V1.md` and `include/gembench/gbr.h` together;
2. update the host compiler and tests in the same change;
3. keep output deterministic for identical source input;
4. reject unsupported or lossy input with a clear diagnostic; and
5. increment the format version for incompatible binary changes.

Do not silently reinterpret an existing object type, flag, state bit, or record
field.

## Object runtime

The first renderer is deliberately app-linked and does not change the resident
kernel jump table. Its public interface is `include/gembench/gbr_object.h`:

- the validated resource bytes remain immutable;
- callers provide one `unsigned int` state slot per resource object;
- tree roots are placed by the caller in Screen 7 pixel coordinates, while
  child coordinates are relative to their parents;
- visible box, text/string, and button objects draw through existing libgb
  primitives and semantic black/white/grey/red pen roles;
- hidden ancestors suppress drawing and hit testing, while disabled ancestors
  additionally suppress hits; and
- hit testing returns the deepest selectable object, resolving equal-depth
  overlap in resource order.

`GBRDEMO.APP` currently caps its external resource at 512 bytes and eight
objects. These are demonstration-app limits, not additions to the GBR v1 ABI.
Resident placement and mapper-backed resource storage were measured in
Milestone 7.

The release MSX2 FormRef embeds its compiler-verified 231-byte `FORMREF.GBR`
through the generated `apps/formref/formref_gbr.h`. `GBR_FORMS=1` enables field,
checkbox, and radio rendering plus live text and focus helpers;
`GBR_FORM_ENGINE=1` adds shared activation and navigation policy.
`GBR_EMBEDDED=1` selects the compact access-only reader after the host build has
verified the generated blob. The form-capable object runtime compiles to 5,339
bytes, the optional form engine to 1,561 bytes, and the embedded accessor to 769
bytes with the current SDCC. External files continue through the strict reader.

Milestone 7 retained that placement after measurement. Build the experimental
mapper-backed comparison and the non-installed resident candidate with:

```sh
MSX_UNAPI_TSR= make gembench-msx-banked
tools/test_formref_openmsx.sh
make gembench-m7-resident-probe
```

The optional banked build keeps Milestone 7's original 306-byte resource fixture
for reproducible comparison. The normal `make gembench-msx` does not install the
mapper service or stage `FORMREF.GBR`. See
[M7-BANKING-DECISION.md](M7-BANKING-DECISION.md) for the size, stack,
interaction, and emulator results.

## MSX2 window kinds

The public `gb_mwin_t` prefix remains the original 12-byte descriptor. Existing
applications therefore retain the legacy close/drag callback contract. An
MSX2 application opts into kernel-owned furniture and gestures with the
explicit v1 wrapper and registration call:

```c
static gb_mwin_kind_t window = {
    { x, y, w, h, min_w, min_h, window_proc, title, 0 },
    GB_WK_STANDARD
};

gb_wm_managed_kind(&window);
```

`GB_WK_TITLE`, `GB_WK_CLOSE`, `GB_WK_MAXIMIZE`, `GB_WK_MOVE`, and
`GB_WK_RESIZE` may be combined independently. Completed kernel gestures report
their committed geometry through `GB_MSG_MOVED`, `GB_MSG_SIZED`, and
`GB_MSG_MAXIMIZED`; the application should refresh any cached rectangle from
`gb_wm_x()`, `gb_wm_y()`, `gb_wm_w()`, and `gb_wm_h()`. File Manager is the
reference implementation. This extension is deliberately MSX2-only and does
not change the resident jump table. `gb_wm_managed()` always selects the legacy
12-byte contract and never causes the kernel to read the appended kind byte.
The frozen layout and compatibility rules are in [ABI-V1.md](ABI-V1.md).

Run the machine-readable compatibility audit independently with:

```sh
make gembench-abi-check
```

## Multi-event subscriptions

MSX2 applications opt in by building with `GB_EVENTS=1`, including
`gbevent.h`, and owning both pieces of state:

```c
static gb_event_subscription_t subscription;
static gb_event_t event;

gb_event_init(&subscription, GB_EVENT_ALL, 1);

if (gb_event_collect(&subscription, &event, m) & GB_EVENT_TIMER)
    update_clock();
```

Call `gb_event_collect()` once at the start of the existing window procedure.
On `GB_MSG_FRAME`, the adapter reads at most one buffered key, samples the
already-published pointer once, and decrements the subscription timer once.
Pointer movement and timer expiry are represented at most once in that output
record. A non-frame message may combine `GB_EVENT_POINTER` and
`GB_EVENT_WINDOW`, so inspect the class bits independently and apply the
application's explicit priority. The record is cleared on every call and must
be consumed before the next callback.

The subscription is six bytes and the event record nine bytes. The current
SDCC build emits 860 bytes of code and no static data. Its deepest generated
path uses 31 stack bytes below `gb_event_collect()` entry while calling the
leaf `gb_mx()`/`gb_my()` accessors. The adapter remains application-linked and
outside the frozen GEMBENCH-1 binary ABI. Clock enables it only for MSX2; CPC
and PCW retain the original callback switch.

## Visible-region repainting

An application that benefits from repeated clipped drawing builds with
`GB_REGIONS=1`, includes `gbregion.h`, owns one persistent iterator, and loops
inside its existing repaint callback:

```c
static gb_visible_state_t regions;

if (gb_visible_begin(&regions))
    do draw_current_clip(); while (gb_visible_next(&regions));
```

Call `gb_visible_end()` only when leaving the loop early. Normal exhaustion
restores the original damage clip automatically. Do not recursively begin on
the same state. Four rectangles are available; a fifth piece, a corrupt table,
an unknown page, or two windows registered from the calling page selects the
original single damage clip. This makes overflow deterministic and prevents a
partial region set from reaching drawing code.

The release build enables this only for the MSX2 Desktop. Its inexpensive
backdrop and icons benefit from repeated clips; renderers that stream data or
repeat expensive setup retain one callback. Host geometry and the Z80 footprint
check run with:

```sh
make gbregion-check
```

After `make gembench-msx`, run the reference move/top/close workflow with:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  tools/test_visible_regions_openmsx.sh
```

Set `MSX_HEADLESS=1` to skip screenshots. A rendered run writes its trace to
`build/msx/visible-regions-openmsx.txt` and settled captures to
`build/msx/visible-regions-screens/`. The test waits for the Desktop callback
to return and then drains asynchronous V9938 commands and File Manager icon
probes before capturing visual evidence.

## Typed clipboard/scrap

MSX2 applications build the complete bounded API with `GB_SCRAP=1` and include
`gbscrap.h`:

```c
unsigned int copied;
char text[80];

if (gb_scrap_get(GB_SCRAP_TEXT, text, sizeof text, &copied) == GB_SCRAP_OK)
    consume_text(text, copied);
```

`gb_scrap_set()` accepts text, bitmap, icon, or file-list payloads. It reports
truncation above `GB_SCRAP_CAPACITY` (510) and publishes the type only after the
payload is complete. `gb_scrap_get()` copies nothing on a type mismatch and
always initializes the caller's copied count. `GB_SCRAP_ANY` accepts typed or
legacy untyped data. Use `gb_scrap_clear()` to clear both payload and metadata.

`GB_SCRAP_TEXT_ONLY=1` requires `GB_SCRAP=1` and links the 100-byte
set/type-only adapter instead of the full runtime. It is for tight clients such
as Notepad that label their own writes, call `gb_scrap_type()` before paste, and
then use the existing resident `gb_clip_len()`/`gb_clip_get()` path. This profile
does not export query/get/clear. Both flags are MSX2-only; CPC and PCW continue
to compile their raw clipboard path unchanged.

Run the host semantics and target footprint gate with:

```sh
make gbscrap-check
```

The suite covers empty, typed, raw, stale, exact-capacity, oversized,
truncated-read, invalid-argument, mismatch, clear, and corrupt-length cases.
After `make gembench-msx`, exercise two independent Notepad windows through the
real pointer and Edit menus with:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_typed_scrap_openmsx.sh
```

The driver copies `SCRAP13` as typed text, verifies a bitmap-tagged paste leaves
the destination unchanged from function entry to return, restores the text tag,
and verifies the seven-byte append. Its disposable image removes `UNAPINET.COM`
and runs with `MSX_UNAPI=0`, so the check does not require the optional
`unapinet` extension.
