# GEOBENCH-2 Gate 2: MSX2 reference runtime

Issue #58 turns the Gate-1 compile-once package into an admitted MSX2
application without changing the inherited GEMBENCH-1 jump table or legacy
application path.

## System record and fixed memory

`GB_SYSINFO` now returns a contiguous 48-byte v6 record at `0xCF00`. Its first
32 bytes are byte-for-byte the v5 layout; the former `0xC2F0` cell remains an
unpublished v5 shadow for old diagnostic tools. The suffix reports:

- capability high word `0x004F`: universal loader, runtime geometry, portable
  semantic drawing/input, and generation-safe background visual timers;
- 128 columns by 212 lines, four pixels per column and four semantic pens;
- application range `0x4000..0x7EFF`, kernel table `0x8000`;
- universal ABI 2.0, profile 3 (`universal-z80`).

Screen 6 already stores four logical pens directly. Screen 7 may use sixteen
physical colours internally, but its rectangle save/restore boundary converts
to the same canonical two-bit, four-pen byte stream. The v5 `colours` field
continues to describe physical mode capacity; v6 `semantic_pens` describes the
portable drawing contract.

The strict validator occupies `0xCF30..0xD3FF`, so
`MSX_APP_FIXED_BOTTOM` is now `0xD400`. This area is below the MSX-DOS TPA
ceiling and remains visible while page 1 is switched.

## Loader transaction

The resident launch path performs the existing owner and primary-page
allocation, maps the page, and loads the bounded file. Before calling the outer
`JP`, it invokes the project-owned `GBAPV4.MOD` gate loaded at boot. Boot checks
the module signature and stops safely if it is absent or truncated.

Headerless and GBAP v1-v3 applications retain their old path. A file claiming
GBAP v4 is rejected unless the gate validates checked header/manifest bounds,
profile and ABI identity, capability and page policy, application identity,
lifecycle, canonical icon directory, common primary segment, entry and image
limits, complete package size, reserved fields, and CRC-32/ISO-HDLC. Rejection
returns to the common `wmo_fail` path, which restores the previous bank and
releases the pending owner and all its pages before anything is published.

Gate 2 intentionally admits the mandatory primary-only package profile. It
does not advertise portable filesystem or package-resource capabilities, and
rejects external v4 segments until their allocation/selection transaction is
implemented. The exact one-segment `ABIPROBE.APP` produced by Gate 1 is staged
unchanged in `GBENCH/` and is displayed using its v4-owned icon.

## Verification

The host gate checks the v6 layout, fixed region, module signature/size,
pre-entry rollback ordering, package CRC/manifest, capability floor, and exact
staged application bytes:

```sh
make geobench-v2-msx-gate-check
```

The target workflow builds a private image, opens the good package, then
corrupts one package byte and proves CRC rejection occurs before `_start` with unchanged
owner, page, and window counts:

```sh
make geobench-v2-msx-openmsx
```

For a manual check, build and boot normally, open Disk A, then launch
`ABIPROBE.APP`. It should open the centred “Universal ABI” managed window:

```sh
make geobench-msx
MSX_UNAPI=0 tools/run_msx.sh QA/MSX/GBMSX.IMG
```
