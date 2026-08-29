# GEMBENCH-1 ABI freeze

Status: **frozen 2026-08-29**.

GEMBENCH-1 freezes the first resource and managed-window contracts after the
Milestone 7 placement measurements. The machine-readable authority is
[`abi/gembench-v1.json`](../../abi/gembench-v1.json); `make
gembench-abi-check` verifies its constants, Z80 layouts, kernel slot, and
registration selectors against the implementation.

## What is frozen

### GBR1 resources

The complete GBR v1 binary grammar is frozen:

- the 24-byte header, four-byte tree record, and 16-byte object record;
- little-endian absolute offsets, canonical packed section order, and additive
  checksum;
- the 16 KiB file limit and `255`/`65535` null sentinels;
- object type values `0..9`, flag and state bit assignments, and reader result
  values; and
- strict rejection of unknown bits, non-zero reserved fields, non-canonical
  section layouts, invalid strings, and invalid tree links.

Box, text, string, button, field, checkbox, and radio are rendered GEMBENCH-1
types. Icon, image, and user keep their frozen numeric identities but remain
format-only reservations: a visible instance is rejected by the current
renderer before any partial tree draw. Future code may implement their stated
meaning without changing the record layout; it may not reinterpret their
numeric values.

`selectable` and `hidden`, plus `disabled`, `selected`, `checked`, and `outlined`,
have generic runtime behavior. The opt-in form engine implements the frozen
`default`, `exit`, and `radio` meanings without changing their values: Enter
selects the enabled default, Escape selects a non-default exit, and radio
activation is exclusive among radio siblings. `shadowed` remains declared
metadata without implicit drawing behavior. Applications not linking the form
engine may continue to interpret the same metadata explicitly.

The C runtime descriptor, embedded-versus-mapper storage, renderer placement,
generated source identifiers, source-only shortcuts, and generated `GBRM` menu
descriptors are not bytes in the GBR1 file ABI. Milestone
7 selected embedded resources and app-linked rendering for small resources;
the opt-in mapper transport remains an implementation experiment.

### Managed windows

The legacy `gb_mwin_t` target layout remains exactly 12 bytes. Its existing
registration call, `gb_wm_managed()`, explicitly selects the legacy contract
and the kernel never reads beyond byte 11.

The MSX2 extension is a 13-byte `gb_mwin_kind_t`: the unchanged 12-byte base
followed by one `kind` byte at offset 12. It must be registered with
`gb_wm_managed_kind()`. The distinct libgb entry point passes the v1 selector
through the existing `GB_WMMANAGED` jump-table slot, so no new resident ABI slot
or public low-RAM cell is required. The kernel records that selection in the
owning window-table entry before it ever reads the appended byte.

This explicit registration deliberately replaces the Milestone 6 prototype's
14-byte kind/tag tail. That prototype made the kernel inspect bytes 12 and 13
for every legacy descriptor; unrelated adjacent application data could
accidentally match the tag. It was revised before the freeze. Applications
built against the prototype must be rebuilt; the legacy 12-byte contract and
kernel jump-table address did not change.

The five kind bits and the `GB_MSG_MOVED`, `GB_MSG_SIZED`, and
`GB_MSG_MAXIMIZED` values and payloads are frozen. Unknown kind bits are masked
off. CPC and PCW expose only the legacy registration contract and keep their
existing app-owned geometry behavior.

### App-linked event aggregation

Milestone 11 does not extend the frozen binary ABI. `gbevent` is an optional
application-linked source API over the existing input accessors and
`gb_msg_t` callback. It adds no resource bytes, managed-window tail, kernel
jump-table slot, public low-RAM cell, or resident state. Applications using it
must be rebuilt with the implementation and must not treat its C structure
layout as a cross-version binary exchange format.

The current implementation nevertheless machine-checks its bounded footprint:
the caller owns a six-byte subscription and nine-byte output record, unknown
class bits are rejected atomically, and a timer class requires a non-zero
period. Legacy callbacks, message values, and registration entry points retain
their frozen meanings.

### App-linked visible regions

Milestone 12 also leaves GEMBENCH-1 unchanged. `gbregion` is an optional
application-linked source API over the existing damage clip and window table.
Its four-rectangle capacity, 40-byte caller-owned state, and C structure layout
are implementation details, not a cross-version binary exchange format. It
adds no resource bytes, managed-window tail, message value, kernel jump-table
slot, resident state, or public low-RAM allocation.

Legacy repaint callbacks retain their one-call behavior. The MSX2 Desktop opts
in at build time; CPC, PCW, and all other release applications retain the
original single damage rectangle. Capacity exhaustion or an ambiguous window
identity deterministically performs one legacy-clipped iteration, so frozen
window registration and callback meanings do not change.

### App-linked typed scrap

Milestone 13 does not change GEMBENCH-1. The MSX2 `gbscrap` header is an
application-linked source API over the existing resident `gb_clip_*` calls.
The raw length remains at `0x3E00`, the raw payload remains exactly 510 bytes at
`0x3E02-0x3FFF`, and the three existing clipboard jump-table entries do not
move or change meaning. No GBR byte, managed-window descriptor, callback,
message value, or registration selector is added.

The implementation owns one private MSX low-RAM byte at `0x133D`. It is mapped
and overlap-checked with the other implementation cells, but it is not a public
address or a frozen application ABI. Raw `gb_clip_set()` clears the metadata;
therefore an old writer is observed as `GB_SCRAP_UNTYPED`, never as stale typed
data. A typed writer publishes its tag after the raw payload is complete.
Unknown tags also normalize to untyped.

Text, bitmap, icon, and file-list identities plus the bounded status values are
source-contract constants. Applications using them must be rebuilt with the
implementation and must not exchange `gb_scrap_info_t` as a persistent binary
record. The compact Notepad adapter exports only `gb_scrap_set()` and
`gb_scrap_type()`; clients needing query/get/clear link the complete runtime.

## Compatibility rules

For GEMBENCH-1:

1. Existing constants, record offsets, message values, and target structure
   offsets may not move or change meaning.
2. Reserved bytes must remain zero and readers must reject unknown flag/state
   bits; they are not silent extension points.
3. Incompatible resource changes require a new magic/version and a separate
   reader path. A v2 reader must not weaken v1 validation.
4. Window additions require a new explicit registration selector or a new
   jump-table entry. The kernel must never infer descriptor length by probing
   beyond a legacy object.
5. New callbacks and message kinds are append-only. Existing callbacks may
   ignore messages they do not handle.
6. Host compiler, target headers, assembly constants, docs, manifest, and
   compatibility tests change together.

## Verification

```sh
make gembench-abi-check
make check
make gembench-msx
tools/test_formref_openmsx.sh
tools/test_window_kinds_openmsx.sh
tools/test_multi_event_openmsx.sh
tools/test_visible_regions_openmsx.sh
tools/test_typed_scrap_openmsx.sh
```

The resource placement evidence is in
[M7-BANKING-DECISION.md](M7-BANKING-DECISION.md). The openMSX tests remain the
authoritative interaction checks; 1983 remains the complementary boot, mapper,
and image-layout integration check.
