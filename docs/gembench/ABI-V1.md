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
off.

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

The historical library remains buildable and keeps its deterministic fallback,
so its source contract does not change. Architecture Milestone 9 no longer
links it into the release Desktop: visibility is now a global kernel policy
and a callback may be invoked once per exact visible fragment, or not at all
when fully covered. This changes scheduling/compositing policy without changing
the frozen descriptor, callback address, message values, or registration ABI.

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

### Append-only shell services

Milestone 14 is a compatible extension around GEMBENCH-1, not a revision of its
frozen records. MSX2 appends `GB_MSG_SHELL` as message value 11 and appends the
`GB_SHELL` register/find/send jump at `0x80C0`. No older message value or kernel
jump address moves. An existing window procedure may ignore the new message in
the same way it ignores any callback it did not subscribe to.

Service identity is private window-manager metadata, not a descriptor tail. A
provider registers one encoded class in unused window-entry flag bits 5-7 only
after its ordinary 12- or 13-byte registration has completed. The kernel never
reads beyond either frozen descriptor. Discovery returns an opaque short-lived
handle; delivery validates it against the current fixed-capacity live table and
callback before use.

Open, activate, close, and quit are bounded synchronous requests with explicit
success, absence, stale, busy, invalid, no-handler, and rejected results. Open
uses an 11-byte 8.3 argument valid only during the callback. One private MSX
low-RAM byte at `0x133E` rejects nested delivery; there is no queue, retained
payload, new mapper owner, or process record. Applications using `gbshell.h`
must be rebuilt and must not persist or exchange handles.

Milestone 15 appends exact Desk-accessory operations 3 and 4 to that same jump;
all existing operations and addresses keep their meanings. An exact accessory
retains the `0xA0` coarse class and stores its nonzero build-time ID in byte 10
of the existing private per-window launch argument after startup has consumed
it. This is not a descriptor extension, and ordinary class registration neither
reads nor modifies any argument byte. Exact handles remain short-lived and use
the unchanged guarded send operation.

### App-linked VDI-lite and resource graphics

Milestone 16 is an additive source/runtime profile around GEMBENCH-1. It adds no
resident jump, low-RAM cell, descriptor field, message, or binary record. The
VDI context, pen map, raster descriptor, raster bytes, and GBR binding table are
all caller-owned application data.

ICON and IMAGE retain their frozen type numbers and the existing validation of
the 16-bit type-specific `spec` field. The opt-in renderer uses that value only
to resolve an application-owned binding. No pointer or payload is placed in the
resource, and an older or non-graphics renderer may continue to reject the
object. A future on-disk raster payload, palette record, pointer encoding, or
different object layout would require a new resource version.

### Append-only architecture foundation

Architecture Milestone 1 ([#31](https://github.com/salvogendut/GEMBENCH/issues/31))
appends three jumps after `GB_SHELL`: `GB_SYSINFO` at `0x80C3`, `GB_OWNER`
at `0x80C6`, and `GB_PAGE` at `0x80C9`. No existing jump, message, GBR record,
or managed-window byte moves.

Architecture Milestone 2 ([#32](https://github.com/salvogendut/GEMBENCH/issues/32))
appends `GB_APP` at `0x80CC`. The existing owner becomes an independent
application identity, while generation-tagged window handles allow several
frozen compositor records to share one application/code page. The complete
20-byte sysinfo v1 prefix is unchanged; its v2 record appends four
application-capacity bytes and advertises application/multi-window capability.
Milestones 3, 4, and 7 retain that prefix in the current v5 record.

`GB_SYSINFO` has a stable, versioned 20-byte minimum prefix. Owner, page, and
window values are opaque, generation-tagged 16-bit runtime handles; none is a
persistent identifier or a native mapper segment. Applications opt into the C
bindings with `SYS=1`, so existing application binaries and non-users retain
their prior layout. The exact MSX contracts are documented in
[ARCHITECTURE-M1-MSX.md](ARCHITECTURE-M1-MSX.md) and
[ARCHITECTURE-M2-MSX.md](ARCHITECTURE-M2-MSX.md).

Architecture Milestone 3 ([#35](https://github.com/salvogendut/GEMBENCH/issues/35))
appends `GB_DEFER` at `0x80CF`, `GB_MSG_DEFER` as value 12, and the four-byte
sysinfo v3 suffix. Existing jump addresses, messages, window/resource records,
and the complete v1/v2 sysinfo prefixes do not move. The new six-byte send and
eight-byte delivery records are source API values, not persistent file
formats. Endpoints are the existing generation-tagged application owners.

Delivery is root-loop-only, bounded to one of eight FIFO entries per turn, and
never occurs inside the send call. Preemptible compute workers cannot publish,
send, or cancel. Full/stale/no-handler/context errors are explicit; unregister
and owner teardown remove queued sender and receiver entries. The exact MSX2
contract is documented in
[ARCHITECTURE-M3-MSX.md](ARCHITECTURE-M3-MSX.md).

Architecture Milestone 4 ([#37](https://github.com/salvogendut/GEMBENCH/issues/37))
appends `GB_FSCTX` at `0x80D2` and the four-byte sysinfo v4 suffix. Existing
jump addresses, messages, window/resource records, and the complete v1-v3
sysinfo prefixes do not move. Context and directory-entry structures are
source API values, not persistent formats.

The MSX2 implementation provides four opaque generation-tagged contexts with
explicit owner, drive, path, raw 8.3 name, sequential offset, and directory FIB
state. Native DOS calls remain serialized and each transfer advances at most
512 bytes on the root task. Stale and foreign handles are rejected; owner
teardown invalidates every matching context. The exact contract is documented
in [ARCHITECTURE-M4-MSX.md](ARCHITECTURE-M4-MSX.md).

Architecture Milestone 7 ([#43](https://github.com/salvogendut/GEMBENCH/issues/43))
adds `GB_CAP_SERVICE_MANAGER` and advances the unchanged 32-byte sysinfo record
to v5. Both legacy reserved bytes remain zero. Service capacities, message
operations, and errors are source-level constants in `gbservice.h`; no frozen
jump-table entry, window record, persistent format, or existing deferred type
moves. Deferred type 2 is now reserved for service lifecycle/request/reply
traffic.

Service and lease handles are runtime generation-tagged ownership values. A
client may not transfer its lease to another owner or persist it. Provider
selection, first-client launch, rollback, reference release, stale-owner
collection, and final stop are observable policy; the current fixed MSX table
addresses are private implementation details. The exact contract is documented
in [ARCHITECTURE-M7-MSX.md](ARCHITECTURE-M7-MSX.md).

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
make geobench-msx
make gbdefer-check
make gbfsctx-check
make gembench-m4-openmsx
tools/test_formref_openmsx.sh
tools/test_window_kinds_openmsx.sh
tools/test_multi_event_openmsx.sh
tools/test_visible_regions_openmsx.sh
tools/test_typed_scrap_openmsx.sh
tools/test_shell_service_openmsx.sh
tools/test_desk_accessories_openmsx.sh
tools/test_settings_vdi_openmsx.sh
```

The resource placement evidence is in
[M7-BANKING-DECISION.md](M7-BANKING-DECISION.md). The openMSX tests remain the
authoritative interaction checks; 1983 remains the complementary boot, mapper,
and image-layout integration check.
