# Building, deploying, and running GEOBENCH

The default and production GEOBENCH target is MSX2. The tree also builds an
experimental CPC Gate-3 reference target against the compile-once GEOBENCH-2
ABI. PCW remains archived on `archive/cpc-pcw-targets`; see the
[current target state](MSX2-ONLY.md).

## Requirements

- RASM
- SDCC, including `sdasz80` and `makebin`
- Python 3
- dosfstools and mtools
- openMSX for reference emulation
- 1984 for automated CPC validation (expected at `../1984/1984`)

The project distrobox normally provides these tools.

Fetch the redistributable MSX dependencies once:

```sh
bash tools/fetch_msx_deps.sh
```

This stages Nextor and openMSXnet inputs under ignored `QA/MSXDEPS/` paths.

## Build

Build the complete distribution with either command:

```sh
make
make geobench-msx
```

The default release uses the preemptive app-worker scheduler. Useful variants
are:

```sh
make msx-cooperative
make msx-preemptive-diagnostic
make msx-floppies
make gb-basic
```

`make check` runs host tests, ABI/resource validators, MSX media audits, and
asset consistency checks. `make app APP=mahjong` and
`make app APP=calculator` perform registered fast MSX2 rebuilds.

Build the CPC floppy, M4/Albireo card tree, and ignored FAT image with:

```sh
make cpc
make cpc-check
```

`cpc-check` rebuilds the target, audits AMSDOS headers and both card kernels,
checks the CPC low-RAM map, and proves that Probe, Clock, and Calculator are
byte-identical on the MSX2 card, CPC card, and CPC floppy.

The bundled Paint and GB-BASIC sources are both in this repository. A complete
build therefore has no sibling-project source dependency.

## Outputs

- `QA/MSX/CARD/` — committed loose distribution with `GBMSX.COM`, mode-specific
  kernels, configuration, the `GBENCH/` system folder, diagnostics, and `PICS/`.
- `QA/MSX/GBMSX.IMG` — ignored, bootable 32 MiB FAT16 hard-disk image.
- `QA/MSX/Floppies/GEOBENCH.DSK` — bootable 720 KiB FAT12 system disk.
- `QA/MSX/Floppies/EXTRAS.DSK` — 720 KiB picture-gallery disk.
- `QA/CPC/Floppies/GEOBENCH.DSK` — CPC DATA disk with the reference runtime.
- `QA/CPC/CARD/` — shared M4/Albireo tree; `GB.BAS` selects `GBM4.BIN` or
  `GBALB.BIN` through `M4DETECT.BIN`.
- `QA/CPC/GEOBENCH.IMG` — ignored 32 MiB FAT16 image built from the CPC card.

The floppy includes Nextor and openMSXnet notices. It does not include
proprietary `MSXDOS2.SYS`; supply a Nextor kernel ROM or your own licensed DOS2
system file.

## Networking choice

The standard build stages `QA/MSXDEPS/UNAPINET.COM` when present. Override it
with:

```sh
MSX_UNAPI_TSR=/path/to/UNAPINET.COM make geobench-msx
```

Build explicitly without the guest TSR with:

```sh
MSX_UNAPI_TSR= make geobench-msx
```

## Run in openMSX

Interactive hard-disk image:

```sh
tools/run_msx.sh
```

System floppy:

```sh
tools/run_msx.sh QA/MSX/Floppies/GEOBENCH.DSK
```

If the host openMSX installation lacks the `unapinet` extension, either point
the launcher at an openMSXnet bundle or disable networking for that run:

```sh
MSX_UNAPI=0 tools/run_msx.sh QA/MSX/GBMSX.IMG
```

The launcher can use the `my-distrobox` container automatically when the
openMSXnet bundle needs libraries absent from the host.

## Deploy to hardware

Copy the contents of `QA/MSX/CARD/` onto storage mounted by MSX-DOS 2/Nextor and
run `GBMSX.COM`, or write `QA/MSX/GBMSX.IMG` to the target device. The selector
reads `MSXMODE=6|7` from `GEOBENCH.CFG` and starts the corresponding kernel.

The supported baseline is an MSX2 with V9938/V9958, 128 KiB VRAM, and at least
512 KiB mapper RAM. See [MSX2.md](MSX2.md) for the runtime design.

## Run on CPC with 1984

The automated Gate-3 workflow boots the floppy, opens File Manager, launches
the universal ABI probe, and verifies a real managed-window drag from guest
memory:

```sh
make cpc-1984
```

For an interactive run:

```sh
../1984/1984 --config=/dev/null --6128 --memory=512 \
  --disk-a=QA/CPC/Floppies/GEOBENCH.DSK --autostart=GB
```

Open Disk A and double-click `ABIPROBE.APP`. On a floppy, keep Fire held during
the first title drag while the 209-byte CPC interaction module is loaded; card
storage makes that transition much shorter.
