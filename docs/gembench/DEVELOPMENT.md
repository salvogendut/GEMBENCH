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

Build the fixed-target distribution:

```sh
make gembench-msx
```

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

## Target work

Before adding the resource renderer, decide and record:

- which jump-table slots or version negotiation the extension uses;
- the maximum resource-segment and object-tree capacities; and
- the exact emulator and Omega/RainBIOS validation commands.

The first renderer is app-linked. Resident placement remains a later measured
comparison rather than an initial ABI assumption.
