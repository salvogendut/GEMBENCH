# GEOBENCH-2 universal application ABI

Status: proposed for issue #55. The machine-readable authority is
[`abi/geobench-v2.json`](../abi/geobench-v2.json). Nothing in this document is
advertised by a released kernel until the implementation gates in the migration
plan have passed.

## Decision

GEOBENCH-2 applications are native Z80 programs compiled once into one `GBAP
v4` `.APP` file. That exact file is copied, without relinking or rewriting, to
MSX2, CPC, and PCW media. Each machine keeps its own kernel, memory driver,
graphics renderer, input driver, and filesystem backend.

This is a native ABI, not a virtual machine and not a promise that arbitrary
CP/M or hardware-specific Z80 code is portable:

```text
                         one byte-identical APP
                                  |
                 GBAP v4 validation and capability gate
                                  |
             +--------------------+--------------------+
             |                    |                    |
        MSX2 kernel           CPC kernel           PCW kernel
        VDP / mapper       Gate Array / banks     roller RAM / banks
             +--------------------+--------------------+
                                  |
               fixed GEOBENCH calls and semantic data
```

Application code sees runtime geometry, four semantic UI pens, opaque resource
handles, opaque 16 KiB page handles, and a fixed kernel call table. It never sees
a VDP command, Gate Array value, PCW roller address, firmware entry point, I/O
port, native bank number, or physical framebuffer address.

The existing frozen `GEMBENCH-1` resource and managed-window ABI remains valid.
`GEOBENCH-2` inherits it append-only; the name records the restored project
identity rather than pretending the earlier authority never existed.

## What “compile once” guarantees

A conforming universal application has all of these properties:

- one primary Z80 code image is used on all three platforms;
- all executable secondary images are also common to all three platforms;
- the complete `.APP`, not merely its code segment, has the same hash on all
  three distribution images;
- geometry and capabilities are read at runtime;
- platform-specific resources may coexist in the package, but selection is by
  presentation codec and they cannot contain executable code;
- missing required capabilities cause an atomic loader rejection before C
  initialisation; optional capabilities select a fallback path;
- no build defines `GB_MSX2`, `GB_PCW`, `PLATFORM_MSX`, `PLATFORM_CPC`, or
  `PLATFORM_PCW` while compiling the universal artifact.

The guarantee does not make every device service universal. For example, an
application that declares networking as required cannot start on a kernel with
no network provider. Ordinary desktop applications should treat such services
as optional and remain usable without them.

## Execution and memory contract

All three kernels present the same process view:

| Range | Contract |
|---|---|
| `#0000-#3FFF` | resident kernel/ABI state; applications use only documented libgb accessors |
| `#4000-#7EFF` | current application's primary image, at most 16,128 bytes |
| `#7F00-#7FFF` | reserved task/guard area; never part of an application image |
| `#8000...` | resident kernel jump table, three-byte `JP` entries |

The application base is `#4000`, the kernel base is `#8000`, pointers and
integers are 16-bit little-endian, and a page is 16 KiB. The common contract uses
the strictest current load ceiling (`#3F00` bytes) instead of the old PCW-only
`#3F80` exception.

The kernel owns the stack, interrupts, native memory banks, and scheduling. A
synchronous service may temporarily replace the application page, but must map
the caller back before returning and restore `SP`. A kernel service that retains
an application descriptor must copy it before returning. Applications cannot
retain native page numbers or pass an application pointer to asynchronous work.

Extra memory is obtained only as an opaque `gb_page_t`. The manifest states the
minimum and preferred total page count, including the primary page. A secondary
code page begins at `#4000` too, is entered through a validated kernel gate, and
obeys the same universal-code rule.

### C and assembly boundary

Universal builds define only `GB_UNIVERSAL`. The supplied universal libgb owns
the assembly trampolines between SDCC `__sdcccall(1)` and the fixed register
contracts already documented in `lib/gbapp.inc`. This keeps the public kernel
boundary independent of C compiler stack layout.

Kernel-to-application callbacks are near `void(void)` entry points. The owning
page is mapped for the entire callback and the event is read through libgb.
Applications assume all general registers are volatile across a service or
callback, except for the documented result, and return promptly from callbacks.

An alternative compiler may be used only if its libgb trampolines, structure
layout, startup, and callback stubs pass the same conformance tests. It does not
create a new kernel ABI.

## Kernel jump table

The 71 inherited slots from `GB_INIT` at `#8000` through `GB_FSCTX` at `#80D2`
keep their addresses and order. The full list is in the authority file and is
checked against both `lib/gbapp.inc` and `kernel/api_table.inc`.

Every GEOBENCH-2 kernel must physically provide every slot. An optional service
may be a typed unsupported stub, but its capability bit must then be clear. A
universal application calls an optional service only when its manifest and live
capability checks allow it. New calls are appended after `#80D2`; no old slot is
repurposed again.

Some inherited calls expose target-era behaviour and are excluded from
universal source even though their addresses stay compatible:

- `GB_SETINK`: changes native palette hardware;
- `GB_PICOPEN`, `GB_PICEDIT`, `GB_PICBLIT`, and `GB_PICCLOSE`: expose the old
  banked native-picture path;
- `GB_EXIT`: returns to a platform-specific host environment;
- `GB_INIT`: is a kernel entry, never an application service.

Their portable replacements are semantic theme/rendering, package resources,
document services, and normal application lifecycle calls. Legacy applications
may continue using the old entries on the targets for which they were built.

## Runtime system information v6

`GB_SYSINFO` remains at `#80C3`. Version 6 is 48 bytes and preserves the entire
32-byte v5 prefix byte-for-byte. Old applications therefore keep reading the
same fields. The appended suffix is:

| Offset | Size | Field |
|---:|---:|---|
| 32 | 2 | high word of the 32-bit capability mask |
| 34 | 1 | screen width in four-pixel columns |
| 35 | 1 | screen height in lines |
| 36 | 1 | pixels per logical column, initially `4` |
| 37 | 1 | semantic pen count, initially `4` |
| 38 | 2 | application base, `#4000` |
| 40 | 2 | exclusive application limit, `#7F00` |
| 42 | 2 | kernel table base, `#8000` |
| 44 | 1 | universal ABI major, `2` |
| 45 | 1 | universal ABI minor, initially `0` |
| 46 | 1 | universal execution profile |
| 47 | 1 | reserved, zero |

The pointer returned by `GB_SYSINFO` addresses read-only resident memory and is
valid for the process lifetime. A consumer checks `size` before every suffix it
uses. The existing low-word capability assignments remain unchanged; v2 adds:

| Bit | Capability |
|---:|---|
| `0x00010000` | GBAP v4 universal loader |
| `0x00020000` | runtime geometry contract |
| `0x00040000` | portable semantic drawing |
| `0x00080000` | normalised portable input |
| `0x00100000` | portable filesystem semantics |
| `0x00200000` | typed package resources |

A kernel must not advertise one of these bits until its implementation passes
the corresponding cross-platform tests. The old 16-bit `capabilities` field is
the low word; the v6 suffix supplies the high word without changing the prefix.

## Geometry and graphics

The common low-level coordinate remains a four-pixel horizontal column. This is
already the natural byte column for CPC Mode 1 and MSX Screen 6, fits all three
screens in an eight-bit value, and avoids making every existing window and draw
descriptor larger. Pixel-accurate X coordinates use 16 bits.

At startup and when laying out a window, a universal application reads
`screen_columns`, `screen_lines`, `width_pixels`, and `height_pixels`. It does
not compile `GB_COLS`, `GB_LINES`, or `GB_XPIX` into the code. Layout helpers
anchor, centre, clamp, or scale rectangles using these live values. GBR1's
pixel-coordinate fields are resolved and clipped against the same live
geometry.

Drawing uses four logical pens:

| Pen | Meaning |
|---:|---|
| 0 | canvas/background |
| 1 | surface/foreground |
| 2 | edge/text |
| 3 | accent/focus |

The active theme chooses physical colours. MSX2 and CPC normally map them to
four colours; PCW maps them to black, white, and stable dither patterns. Apps
must not infer RGB values or native packed bits from a pen number.

`GB_SAVERECT` and `GB_RESTORERECT` use canonical two-bit semantic-pen packing,
four pixels per byte, on every target. A PCW kernel translates that format at
the boundary instead of exposing its one-bit framebuffer. This preserves the
existing `w * h` buffer-size rule and makes save-under buffers portable.

Input uses the same logical coordinates. `gb_mx()`/`gb_my()` return column and
line, while `gb_mxp()` returns the full 16-bit pixel X in the range reported by
sysinfo. Key input is normalised to the documented character/control set;
machine-specific keys are optional events.

## Resident mailbox

Some current libgb operations are implemented with fixed resident cells rather
than a kernel call. Their small common layout is therefore acknowledged by v2:
time, the four-byte callback message, the last poll result, boot drive, drag
name/claim, and the live managed-window rectangle. Exact ranges are in the
authority file.

Only universal libgb may encode those addresses. Application source uses
accessors, and callback-scoped values may not be cached after the callback. All
other low-RAM and page-3 addresses are private kernel implementation details.
Existing diagnostic apps that inspect mapper tables or kernel scratch are
target-specific by definition.

## GBAP v4 package

GBAP v4 preserves the initial three-byte `JP`, `GBAP` magic, 16-byte outer
header, and v2 icon directory. This lets file managers identify and display a
portable icon without understanding the executable. Header bytes 14-15 point
to a 64-byte `GBM4` manifest.

The v4 manifest carries:

- profile `3` (`universal-z80`) and platform mask `0x07`;
- minimum ABI and sysinfo version/size;
- 32-bit required and optional capability masks;
- eight-byte application identity, service/lifecycle, and page policy;
- a typed segment directory and primary entry/image bounds;
- the eight-byte ABI identity `GEOBNCH2`;
- 32-bit package size and CRC-32.

The exact offsets are authoritative in `abi/geobench-v2.json`. The CRC is
CRC-32/ISO-HDLC over the declared package bytes with the manifest CRC field
treated as zero.

V4 segment entries are 20 bytes and use 32-bit file offsets and lengths:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 1 | type: primary code, secondary code, resource, or data |
| 1 | 1 | selector: common, presentation codec, or platform mask |
| 2 | 1 | required/executable/read-only flags |
| 3 | 1 | compression; `0` is the mandatory uncompressed codec |
| 4 | 2 | selector value |
| 6 | 2 | fixed load address, or zero for an allocated resource |
| 8 | 4 | file offset |
| 12 | 4 | stored length |
| 16 | 4 | unpacked length |

There is exactly one required, executable, uncompressed, common primary
segment. It starts at file offset zero, loads at `#4000`, includes the guarded
startup, and ends by `#7F00`. All executable secondary segments are common too.
A platform-selected segment is never executable.

The required icon and other baseline resources use portable codecs. Optional
variants select a presentation codec (for example a native MSX 16-colour icon),
not a platform code path. The package still has one byte sequence on every
machine; a loader simply selects the best resource it can render.

### Loader transaction

A conforming loader performs these steps without publishing a partial app:

1. read the outer header and complete manifest with checked arithmetic;
2. validate magic, versions, profile, `GEOBNCH2`, size, CRC, segment ranges,
   non-overlap, entry range, and universal-code rules;
3. check that the local platform bit is present and sysinfo meets the declared
   ABI, size, capability, and page requirements;
4. allocate the owner and all required pages;
5. load and, where permitted, decompress the primary and required resources;
6. map the primary and enter its universal startup guard;
7. publish windows/services only after successful initialisation.

Any failure releases every page, handle, filesystem context, and pending owner,
then returns a typed error to File Manager. The startup guard repeats the ABI
and capability checks before C initialisation, so a v4 file cannot accidentally
run as an unguarded legacy binary.

## Compatibility

- Headerless, GBAP v1, v2, and v3 applications retain their existing
  target-specific loader path.
- `portable-z80` in GBAP v3 remains a packaging promise; only GBAP v4 profile 3
  claims this enforceable universal contract.
- GEMBENCH-1 GBR1 files and managed-window descriptors do not change.
- The v5 sysinfo prefix and every existing jump-table address remain fixed.
- A v4 application never starts on a kernel that lacks the universal-loader
  capability, even if its outer `JP` looks executable to an old loader.
- Old target-specific applications may use native services and build defines;
  they simply cannot be labelled `universal-z80`.

## Conformance

The ABI design checker is:

```sh
python3 tools/check_geobench_v2_abi.py
```

It verifies the frozen inheritance, scalar/page arithmetic, platform masks,
contiguous record layouts, capability bits, the v5 sysinfo prefix, all 71
current slots, GBAP v4 records, and current SDCC structure offsets. The
implementation phase adds a package validator, a forbidden-dependency audit,
and emulator tests before any kernel advertises the new capability bits.
