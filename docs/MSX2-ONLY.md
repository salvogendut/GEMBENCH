# Current target implementation state

As of 31 August 2026, GEOBENCH builds the production MSX2 target and an
experimental CPC reference target. PCW remains absent.

The default `make` and release path remain an MSX2 with a V9938/V9958, 128 KiB
VRAM, at least 512 KiB mapper RAM, and MSX-DOS 2 or Nextor. Its scheduler,
GB-BASIC component, full application catalog, and release checks remain
MSX2-specific.

CPC and PCW were removed in issue #50. The former multi-platform tree remains
preserved on the remote branch:

```text
archive/cpc-pcw-targets
```

Gate 3 / issue 54-A now restores the CPC kernel, Mode-1 renderer, 512 KiB bank
allocator, AMSDOS floppy, and unified M4/Albireo card. `ABIPROBE.APP`,
`CLOCK.APP`, and `CALC.APP` are copied from `build/universal` without target
recompilation and are byte-identical to the MSX2 media. The CPC Desktop and File
Manager are transitional target-native boot shells, not a claim of complete
application parity.

The new direction is specified in
[UNIVERSAL-APPLICATION-ABI.md](UNIVERSAL-APPLICATION-ABI.md) and its
[migration plan](UNIVERSAL-APPLICATION-ABI-MIGRATION.md). PCW follows as Gate 5
after the CPC ABI is accepted; it must not be exposed as a working build before
then.

Some source names and formats retain historical terms such as “CPC Mode 1.”
They describe the canonical four-pen packing shared by the CPC source format
and the MSX2 transcoder. Portable algorithms and file formats remain common;
hardware drivers and kernels stay target-specific.
