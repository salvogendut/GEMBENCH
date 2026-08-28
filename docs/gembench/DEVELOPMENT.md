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
Manager, captures the GBR-defined modal at Compact/Level 2, and asserts the
resource descriptor, keyboard focus actions, Save commit, and modal restore.

Exercise the first tagged MSX2 window kind with:

```sh
make gembench-msx
tools/test_window_kinds_openmsx.sh
```

The openMSX driver opens File Manager through the real desktop, then uses MSX
keyboard-matrix pointer input to maximise and restore it, drag its title, and
resize its kernel-drawn grip. It verifies the live geometry and observes the
`GB_MSG_MOVED`, `GB_MSG_SIZED`, and `GB_MSG_MAXIMIZED` callbacks. The final
Screen 7 capture is written to `build/msx/window-kinds.png`.

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
Resident placement and mapper-backed resource storage remain a later measured
comparison.

The MSX2 FormRef embeds its compiler-verified 306-byte `FORMREF.GBR` through the
generated `apps/formref/formref_gbr.h`. `GBR_FORMS=1` enables field rendering,
live text bindings, and focus traversal; `GBR_EMBEDDED=1` selects the compact
access-only reader after the host build has verified the generated blob. The
full form runtime compiles to 4,928 bytes and the embedded accessor to 795
bytes with the current SDCC. External files continue through the strict reader.

## MSX2 window kinds

The public `gb_mwin_t` prefix remains the original 12-byte descriptor. Existing
applications therefore retain the legacy close/drag callback contract. An
MSX2 application opts into kernel-owned furniture and gestures with the tagged
wrapper:

```c
static gb_mwin_kind_t window = {
    { x, y, w, h, min_w, min_h, window_proc, title, 0 },
    GB_WK_STANDARD,
    GB_WK_ABI_V1
};

gb_wm_managed(&window.window);
```

`GB_WK_TITLE`, `GB_WK_CLOSE`, `GB_WK_MAXIMIZE`, `GB_WK_MOVE`, and
`GB_WK_RESIZE` may be combined independently. Completed kernel gestures report
their committed geometry through `GB_MSG_MOVED`, `GB_MSG_SIZED`, and
`GB_MSG_MAXIMIZED`; the application should refresh any cached rectangle from
`gb_wm_x()`, `gb_wm_y()`, `gb_wm_w()`, and `gb_wm_h()`. File Manager is the
reference implementation. This extension is deliberately MSX2-only and does
not change the resident jump table.
