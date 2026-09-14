# v1.0 milestone 2 — portable resources and forms

Started 2026-09-14 in issue
[#88](https://github.com/salvogendut/GEMBENCH/issues/88), branch
`feature/88-portable-resources-forms`, from main `b190ac4`.

The finish line is one byte-identical `GBRDEMO.APP` and one byte-identical
`FORMREF.APP` in the MSX2 and CPC distributions. Both must exercise their real
resource/form behavior and cleanly reclaim every owned page and secondary-code
record. This is not permission to migrate Settings/File Manager or advertise an
unimplemented package-resource capability.

## Four sprints

1. **Baseline and contract.** Inventory the native applications, freeze the
   common data/service boundary and record private acceptance fixtures and
   budgets. Normal distribution delivery remains unchanged.
2. **GBRDEMO vertical slice.** Make the existing bounded GBR1 reader/object
   runtime compile in the universal profile, load the real external
   `HELLO.GBR` through the portable filesystem, and qualify drawing, hit/state,
   clipping, malformed resources, lifecycle and cleanup on both targets.
3. **FormRef vertical slice.** Embed the same generated `FORMREF.GBR` bytes in
   the common primary image and migrate the complete field, checkbox, radio,
   disabled, default/cancel, pointer and keyboard-focus workflow.
4. **Secondary-code closure and delivery.** Convert FormRef's secondary work to
   the already-sealed portable computation contract, qualify all call/ownership
   rejection and restoration cases, then stage identical APPs only after the
   private cross-target gate passes.

## Baseline inventory

| Item | Current state | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| MSX `GBRDEMO.RAW` | Native external-resource demo | 11214 | `482c32bceb4a336f7058b4a4a22086179123418fb80fb0047be2215f37f28df2` |
| `HELLO.GBR` | Frozen external GBR1 fixture | 111 | `49b42e9268ad4f4208d70f591f9d3f6b6ad7bee2dcf6f008a773ece968febf12` |
| MSX `FORMREF.RAW` | Native GBAP v3, MSX-only | 16026 | `c6650c86348b97db50102d839b3d8b5f08a16bd6fb41b045b9a2c02b9d838e46` |
| `FORMREF.GBR` | Embedded generated GBR1 tree | 231 | `a5f473f4665e5f119bf809819e8e191d509f41bda3cd0111320e54f3750bdfc8` |
| `FORMREF.SEC` | Native GBS3 MSX drawing bank | 227 | `5d612267def78d76a49d1df41fc9e53eda123512e2d1f0a41ab57507c0a5fd6b` |

Current source is not a shared build:

- GBRDEMO calls the native implicit-file `gb_fs_load` and compiles visible
  geometry around the MSX target.
- FormRef selects two different implementations with `GB_MSX2`. Its manifest
  is `target-z80`, names only MSX2 and requires a native GBS3 secondary.
- The GBR object and VDI libraries use compile-time `GB_XPIX`, `GB_COLS` and
  `GB_LINES`; a universal build deliberately removes those constants.
- The universal builder has no resource/form link profile yet.
- GBAP v4 describes resource segments, but production receivers deliberately
  do not advertise `package-resources`. The existing portable secondary service
  accepts one sealed common GBS4 computation bank and does not allow secondary
  code to call target drawing entries.

These are migration inputs, not defects to hide with target defines or separate
APPs.

## Contract decisions

### Keep GBR1 frozen

No GBR2 fork is required. The canonical GBR1 bytes, state bits, object types,
tree linkage and generated identifiers remain unchanged. Mutable state and text
or raster bindings remain caller-owned. The existing reader must reject a bad
magic/checksum, overlapping or truncated sections, invalid links/types/text and
unsupported visible objects before partial publication or drawing.

### Use runtime geometry in app-linked code

The universal resource/form/VDI runtime will be linked into each APP. Under
`GB_UNIVERSAL` it obtains columns, lines and pixel width from the v6 sysinfo
accessors and uses only the four semantic pens. Native builds retain their
existing compile-time profile. This is an internal source-profile change, not a
new kernel jump-table contract.

### Do not invent package-resource support for these small fixtures

GBRDEMO keeps its actual external-document behavior, but reads the selected
`HELLO.GBR` through the already-qualified portable filesystem into its bounded
primary buffer. FormRef's 231 immutable bytes are generated once and embedded
in the common primary image. Therefore neither application requires a new v4
resource segment or `package-resources` capability in this milestone. Typed
package resources remain gated for a later real consumer and may not be
advertised as a shortcut.

### Make FormRef secondary work computation-only

The native secondary currently draws through fixed resident addresses. The
portable FormRef will instead give a sealed common GBS4 bank a bounded copied
record and receive a bounded result record; primary code performs all drawing
through universal semantic calls. No code pointer, app pointer, bank number or
target entry crosses the boundary. The existing owner/generation/range/root
guards and exact map/SP/IFF restoration remain authoritative.

## Acceptance matrix

| Surface | MSX2 | CPC |
| --- | --- | --- |
| GBRDEMO | Screen 6 and 7 in openMSX and 1983; external root resource, malformed variants, click/state, move/overlap/close | 1984 with disposable M4 media; same resource bytes and workflows |
| FormRef | Screen 6 and 7; text editing, pointer and forward/reverse keyboard traversal, checkbox/radio/disabled/default/cancel | 1984/M4; same object identities, state transitions and geometry adjusted only by runtime limits |
| Secondary | Valid copied computation plus stale/foreign/nested/worker/teardown/entry/length rejection; exact cleanup/restoration | The same sealed APP/secondary bytes and rejection matrix through the CPC provider |
| Delivery | Normal-image launch/close and exact APP hashes after private acceptance | Normal M4 image only; no floppy tests |

Every emulator driver must observe published state or exported read-only
diagnostics. Guest RAM patches are not acceptance. A smaller CPC-only form,
native fallback hidden behind the universal filename, or host-only resource
test cannot close the milestone.

## Initial baseline evidence

The following pre-migration checks pass on main `b190ac4`:

- 17 GBR compiler tests;
- the complete GBR reader, object, form, graphics and menu host suites,
  including corrupt-resource and interaction semantics;
- Z80 compilation of reader/accessor/menu/object/graphics/form components;
- GBVDI core/base/raster/text contract and size checks;
- visible-region contract and Z80 build;
- 13 owner-page, data-page and sealed-secondary instruction suites, including
  1058 real Z80 bind/call/reclaim operations and 113 data-page calls.

The first code gate is now precise: add a universal resource runtime build
profile and make GBRDEMO compile without target defines, while preserving its
native implementation and normal media until its private two-target acceptance
passes.

## Sprint 2 checkpoint A — compile-once GBRDEMO

The first code gate now passes on this branch:

- `UNIVERSAL_GBR_OBJECTS=1` makes the universal builder link the bounded GBR1
  reader, object runtime and button-only widgets, and requires runtime geometry
  plus portable drawing. It deliberately does not claim the target-native
  `gbr` capability because all GBR policy is linked inside the common APP;
- the object runtime obtains pixel width and line count through v6 runtime
  geometry in a universal build, while its native source profile remains
  byte-identical;
- `apps/ugbrdemo` adopts File Manager's exact launch context, reads at most 512
  bytes through the portable filesystem, rejects an oversized or failed read,
  closes the context, validates `HELLO.GBR`, and only then publishes its managed
  window;
- move is kernel-owned, click/state changes publish bounded content damage, and
  failed/direct launch displays an inert error surface rather than retaining a
  filesystem context;
- the private APP is **13069 bytes**, SHA-256
  `4ec6f034ed396c51fcf5d573c548acfd7df53f077e9f14a718a7cd8cc762b4ff`.
  Code ends at `0x730D`; application state ends at `0x7D9C`, below the guarded
  `0x7F00` limit.

`make geobench-v1-m2-gbrdemo-check` builds the APP twice, proves byte identity,
checks its v4 identity/capabilities and reruns the universal source/assembly/map
audit. The existing universal SDK test, GBR compiler/reader/object suites and
the exact native MSX GBRDEMO rebuild all pass; the native rebuild retains SHA
`482c32bceb4a336f7058b4a4a22086179123418fb80fb0047be2215f37f28df2`.

This is build-level acceptance only. Neither normal image contains the new APP.
The next checkpoint is private receiver staging and the real MSX Screen 6/7 and
CPC/M4 external-resource workflow, including malformed resources and cleanup.
