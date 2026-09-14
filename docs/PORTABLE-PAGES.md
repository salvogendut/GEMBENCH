# Portable owned pages and secondary code — Notepad prerequisite

Issue #84, `feature/84-unified-notepad`, 2026-09-09. The user approved bringing
this dependency forward after the actual Notepad link required 28857 bytes
against the 16128-byte primary allocation. Native delivery stays unchanged.

This is a bounded extraction of roadmap milestone 2, not a second allocator,
target-specific editor, or permission to enlarge the primary/stack boundary.

## Ordered implementation

1. **Owned data pages — private qualification complete:** public caller-owned parameter binding; allocate/free
   opaque handles and copy at most 512 bytes per synchronous root call. Reuse
   the shared owner/page policy and teardown on both targets. Qualify this
   independently before using it to store editor/staging bytes.
2. **Packaged code and call gate — shared stream core fixture-qualified:**
   see [secondary-code contract/progress](PORTABLE-SECONDARY-CODE.md). Receiver
   bindings and the sealed call gate are still pending. Validate/load common secondary segments,
   seal their executable identity, and enter/return through a kernel-owned
   gate with copied arguments/results and exact context restoration. No native
   bank numbers, app-installed trampolines or direct cross-page pointers.
3. **Actual Notepad partition:** editor/UI/document code and storage use the
   qualified services; complete shell/configuration bindings and cross-target
   document/repaint/input/fault acceptance before replacing native delivery.

Data-page support alone does not solve Notepad's code-size overflow. Existing
native `gbsecondary` is not a portable binding and must not be linked into the
universal candidate. PCW remains future receiver work; no PCW test claim.

## Data-page contract (first implementation slice)

Append optional `portable-data-pages` capability `0x02000000` and GB_PARAMS
operation 10 to ABI 2.1. Do not alter inherited slot addresses, operations or
the primary/stack boundaries. The SDK requires both caller-parameters and the
new capability. An old receiver rejects a package requiring it before entry.

The outer parameter record carries two little-endian words: header pointer
and size 16. Remaining outer data bytes are reserved: callers zero them;
receivers ignore them, as with the existing parameter bindings. The whole
header lies in primary app RAM below `0x7F00`.

| Header offset | Field |
| --- | --- |
| 0 | Action: allocate 0, release 1, read 2, write 3 |
| 1 | Result status (input ignored) |
| 2 | u16 generation-tagged page handle; zero on allocate input |
| 4 | u16 offset within the 16 KiB page |
| 6 | u16 primary buffer pointer |
| 8 | u16 length, at most 512 |
| 10–15 | Reserved zero |

Allocate/release require zero offset/buffer/length. All operations require a
mapped primary root caller and a live, non-terminating owner. Allocations have
the existing DOCUMENT purpose; release/read/write accept only that purpose,
never application, cache/resource or executable pages. Handle validation uses
the shared live-generation and owner checks. Owner teardown reclaims allocations
without requiring an APP to release them explicitly. Generation rollover retains
the existing eight-bit policy; this does not claim protection against ABA after
256 reuse cycles.

Read copies page bytes into the primary buffer; write copies primary bytes into
the page. Validate the complete interval before any data mutation: no arithmetic
wrap, offset+length <=16384, nonempty primary span below `0x7F00`, and no overlap
with the header. Empty transfers validate the handle and offset (16384 is
permitted), ignore the pointer and perform no mapping/copy. No pointer survives
the call. Invalid requests do not change page data or the destination buffer.
The copied header publishes status after restoring the caller mapping.

Statuses reuse the page namespace: OK 0, unsupported 1, stale 2, owner 3,
already-free 4, no-memory 5, bad-argument/purpose 6; append context 7.
GB_PARAMS transport status remains separate from header status. SDK allocation
failure returns a zero handle. Freshly allocated contents are unspecified,
like the existing allocator: initialize before consuming them. This slice does
not promise zero-fill, executable memory, page sharing, asynchronous I/O,
atomic multi-chunk transfer or protection from a malicious native application.

Implementation split: the shared parameter front end validates the caller header;
a shared resident data-page service validates ownership/ranges and performs
policy. Target adapters supply only fixed scratch addresses, bank switching,
entry serialization and system-info publication. MSX uses an opt-in boot-loaded
fixed module in reserved `D100..D3FF`, calling the existing resident GB_PAGE
operations internally without extending their interface. It also validates
direct-entry arguments and restores IX, scheduler lock, IFF and mapping.
CPC need not advertise the old
native GB_PAGE API merely to provide the portable parameter operation.

Acceptance: same APP bytes on MSX Screen 6/7 (openMSX and 1983) and CPC M4/1984;
full-page roundtrips through 512-byte chunks; boundary/empty/invalid-span tests;
foreign/stale/free/purpose/worker rejection; exhaustion and close/relaunch cleanup;
mapper/SP/IFF/lock/code guards and no normal-media mutation. Capability publication
must follow passing receiver evidence, not merely the presence of source.

## Checkpoint 2d evidence — 2026-09-09

`UNIVERSAL_DATA_PAGES=1` links the public SDK (283 code + 16 data bytes), with
manifest capability enforcement and the normal source/generated-object audit.
Both receivers include the same `kernel/core/data_pages.asm`; CPC maps through
its existing bank adapter, MSX through its mapper adapter and existing allocator.
There is no application-local bank switch or second allocation policy.

This is **opt-in qualification**, not normal delivery: receiver builds require
`PORTABLE_DATA_PAGES=1`. Default builds keep the capability clear and reject a
package requiring it. The CPC build/test helpers expose only the private
`--data-pages` runtime profile; normal Desktop/Settings staging is unchanged.
MSX private staging adds the size/signature/version-checked `GBDPAGE.MOD`.

| Receiver allocation | Measured bytes | Bound |
| --- | ---: | ---: |
| MSX data module at `D100` | 492 | 768, ends before `D400` |
| MSX admission/parameters module at `0400` | 2931 | Ends before private legacy sysinfo at `0FD0` |
| MSX Screen 6 child COM | 14379 | 16128 |
| MSX Screen 7 child COM | 15957 | 16128 |
| CPC private runtime support | 2644 | 3072 |
| CPC private runtime kernel | 15505 | 16384 |

An initial resident implementation exceeded the child-COM window. The final
module uses existing fixed RAM; its boot loader is emitted after the aligned
VDP tables, following the existing deferred-service layout pattern. No loader,
primary, legacy fixed-RAM or stack limit was relaxed. Normal MSX admission
module size remains 2889 bytes. Do not infer full CPC Desktop fit from the
private runtime profile; normal delivery integration remains a later gate.

Identical `PAGEPRB.APP`: **5004 bytes**, SHA-256
`bf08c4164500a05470214213b9189eb9146787d545ca643fccb5be88612ff97b`.
Each target runs three actual launch/focus/close cycles, 16 KiB roundtrips in
512-byte chunks, independent pages, boundaries/overlaps, exhaustion, free/stale
handles and a deliberately live data page reclaimed on owner teardown. A
clipboard token checks the previous lifetime's handle on relaunch.

Evidence under `build/notepad-84/evidence/`:

- openMSX: `pages-msx{6,7}-final-qualified.log`, **448 APP checks and 407
  parameter return checks per mode**; exact mapper/slot/shadow, SP, IFF, lock,
  `7F00` snapshot and VRAM preservation; exact pre-launch pool restored.
  Final private images are in `build/notepad-84/build/msx/`
  `portable-data-pages-6-4d3a3x91/filesystem.img` and
  `portable-data-pages-7-oi0src_b/filesystem.img`.
- 1983 with corrected RainBIOS: `pages-1983-{6,7}-final/result.json`, the
  same 448 APP checks per mode, 37/46 driver checks, unchanged code, borders,
  fresh owner generations, exact pool recovery and unchanged private images.
  These are read-only-core bridge tests, not SDL mouse-smoothness acceptance.
- CPC M4/1984: `pages-cpc-final.log` and
  `pages-cpc-final-artifacts/result.json`; **454 APP checks**, exact full-pool
  recovery, independent close-exposure pixel checks, unchanged APP/disk bytes.
  Observed stack maxima: main 93, IRQ 4, temporary 0.
- `pages-regressions-final.log`: **29 focused tests pass**, no skips. Actual
  shared-policy execution at two fixed layouts makes 113 calls/134 bank maps
  each, including foreign-owner, code-purpose, worker, terminating-owner,
  non-primary, malformed and range rejection; rejected transfers preserve all
  page/destination bytes outside the output header. These extra negative cases
  are instruction-fixture evidence, not claims about the emulator APP workload.
- The tests execute both assembled admission variants (required capability
  off/on), default operation-10 unsupported dispatch and nine boot-validator
  cases. Boot storage is stubbed at `fs_load_sys`: this is **not** a new
  filesystem/media-fault matrix. Existing ABI and button-capture checks pass.
- `pages-editor-regressions.log`: nine additional existing editor/document-I/O/
  chooser tests pass. Editor checks still use mocked public services, not a
  runnable Notepad package.

Keep failed logs too: initial loader-budget failures, a close observation that
read temporarily mapped BIOS ROM, and a bridge read exceeding its 4096-byte
command limit. Final observers wait for the known low-RAM slot and split host
reads; they do not inject guest writes or waive cleanup checks. The desktop
already owns more than one pool entry; compare its actual baseline, not an
assumed `total-1` free count.

Normal MSX, CPC Desktop and CPC runtime images retain their previously recorded
hashes. Notepad itself still has no runnable universal package. **Next: specify
and implement validated secondary-package loading and the root call/return gate**,
then partition the real editor and qualify actual document workflows.

Progress recorded on [issue #84](https://github.com/salvogendut/GEMBENCH/issues/84#issuecomment-5600256058).
This checkpoint is local and uncommitted; no push, PR or merge was performed.

## Secondary-code design constraints (not implemented by data-page support)

Review the exact segment/entry ABI before enabling a capability. Primary-only
admission currently rejects external segments: the packager's ability to describe
them is not proof the target loader can stream them safely. The loader must
reserve/own required pages transactionally, validate every file range/entry and
reject malformed/unsupported segments before application publication.

Executable pages cannot be made by calling data-page write on a primary or
secondary code handle. Code loading/sealing belongs to the loader. Calls are
root-only, non-nested, and retain primary owner identity while secondary code
runs. Copy bounded parameters/results across the bank boundary; raw primary
pointers and return addresses cannot become secondary pointers. Define allowed
leaf services and reject retained callbacks/worker registration from secondary
code. Restore the caller's mapping/shadow, stack and interrupt/lock state even
when admission/entry validation fails. Reuse the shared ownership and teardown
policy rather than the old app-installed MSX stub.
