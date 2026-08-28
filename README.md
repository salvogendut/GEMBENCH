# GEMBENCH

GEMBENCH is a native evolution of GeoBench for the Omega MSX2. It combines
GeoBench's Z80 kernel, banked application model, and hardware backends with the
declarative resources and consistent desktop conventions associated with
Digital Research GEM.

This is not an x86 GEM emulator, an AES compatibility layer, or a loader for
historical GEM applications. The project borrows interaction and architecture
ideas while keeping a native Z80 ABI.

## Status

The repository is in its pre-implementation phase. The first milestone is a
small, measurable proof of concept for:

- a compact, bank-safe `.GBR` resource format;
- object-tree drawing, hit testing, and state changes;
- window-kind flags and standard window-manager messages;
- one resource-driven GeoBench dialog; and
- a coherent sixteen-colour Screen 7 theme.

The detailed planning document is [DESIGN-ESTIMATE.md](DESIGN-ESTIMATE.md).

## Fixed target

- Omega MSX2 at approximately 3.58 MHz
- 512 KiB mapper RAM
- V9938 or V9958 with 128 KiB VRAM
- Screen 7 at 512 x 212 with sixteen colours
- MSX-DOS2 or Nextor
- RainBIOS as a supported validation environment

CPC and PCW compatibility are outside GEMBENCH's scope.

## Repository layout

```text
docs/                 Architecture, development, and format contracts
examples/             Source resources used for examples and smoke tests
include/gembench/     Target-visible format and ABI declarations
tests/                Dependency-free host tests
tools/                Host-side build tools
```

GeoBench is currently an external foundation and is not vendored here. The
eventual import, fork, or dependency strategy must be decided before target
runtime work begins.

## Quick start

The initial host tooling requires Python 3.11 or newer and GNU Make:

```sh
make check
```

That command runs the tests and compiles the example resource to
`build/examples/hello-dialog.gbr`.

To compile a resource directly:

```sh
python3 tools/gbrc.py examples/hello-dialog.json \
    --output build/examples/hello-dialog.gbr
```

The source format and current binary layout are documented in
[docs/GBR-V1.md](docs/GBR-V1.md).

## Licensing

No project-wide implementation licence has been selected yet. GeoBench is BSD
3-Clause, while directly translated FreeGEM code or reused FreeGEM assets may
carry GPL obligations. Keep new work independent of GPL source and assets until
the project explicitly chooses its licensing path.
