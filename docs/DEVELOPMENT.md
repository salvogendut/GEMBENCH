# Development

The initial repository contains only dependency-free host tooling and format
contracts. Target builds will be documented here after the GeoBench integration
strategy is selected.

## Requirements

- Python 3.11 or newer
- GNU Make

No third-party Python packages are required.

## Commands

Run all current validation and build the example resource:

```sh
make check
```

Run only the unit tests:

```sh
make test
```

Rebuild only the example resource:

```sh
make example
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

Before adding the resource renderer, record:

- how GeoBench source enters this repository;
- which jump-table slots or version negotiation the extension uses;
- whether the first renderer is app-linked or resident;
- the maximum resource-segment and object-tree capacities; and
- the exact emulator and Omega/RainBIOS validation commands.
