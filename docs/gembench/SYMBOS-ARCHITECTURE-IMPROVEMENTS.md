# SymbOS-inspired architecture improvements

Status: **implemented roadmap on MSX2**. Improvements 1-5 are implemented;
Milestone 5 implements the uncompressed-primary slice of improvement 6;
improvement 7 is implemented in Milestone 6; and the first bounded control-plane
slice of improvement 8 is implemented in Milestone 7. CPC and PCW
parity remains governed by `CPC-PCW-BACKPORT-PLAN.md`.

This document records the highest-value architectural improvements identified
while comparing GEMBENCH with SymbOS. The intent is to borrow useful separation
of ownership, services, memory, and application lifecycle without turning
GEMBENCH into a SymbOS clone or abandoning its compact 16 KiB application
model.

The assumed targets are MSX2, Amstrad CPC, and Amstrad PCW systems with at least
512 KiB RAM. Changes must preserve the frozen GEMBENCH-1 contracts or introduce
an explicitly versioned replacement.

## 1. Platform-neutral capability query

Add a stable `GB_SYSINFO` service reporting runtime ABI, screen geometry and
packing, physical and free pages, and supported window, event, filesystem,
shell, network, resource, application, and service features. Applications
should select policy from capabilities instead of assuming a compile-time
target; hardware backends may remain target-specific.

Acceptance requires a versioned fixed prefix, compatibility with older apps,
detectable unsupported operations, correct geometry/feature bits on every
backend, and use by the CPC/PCW parity work.

Estimated difficulty: **low-medium**. MSX2 status: **implemented in Milestone
1 and extended through sysinfo v3 in Milestone 3**.

## 2. General page allocator independent of windows

Separate mapper/expansion capacity from the eight-window compositor limit.
Opaque 16 KiB page handles carry owner, purpose, native-page metadata, state,
and a reuse generation. Purposes include application code, resources,
documents, caches, scrap, and temporary storage.

Acceptance requires access to pages beyond window capacity; rejection of
double-free, foreign, and stale handles; automatic owner cleanup; compatibility
with the legacy first-eight-page mirror; and passing Desktop, Viewer, Paint,
Icon Editor, and GBR bank tests.

Estimated difficulty: **medium-high**. MSX2 status: **implemented in Milestone
1**.

## 3. Separate application records from window records

An application record owns its generation-tagged identity, primary code page,
zero or more windows, resource/data pages, workers, timers, queued messages,
and acquired/provided services. Window records retain compositor geometry,
z-order, callbacks, kind, state, and launch metadata and point to an
application.

Acceptance requires several windows per code page, a windowless published
application, independent window close, atomic application termination, and
deterministic focus/repaint/shell/accessory/scheduler lifecycle.

Estimated difficulty: **high**. MSX2 status: **minimum identity implemented in
Milestone 1; useful multi-window ownership and application lifecycle implemented
in Milestone 2**. Further worker/timer/service ownership is incremental.

## 4. Small deferred-message layer

Add bounded asynchronous control messages driven by the root task. A message
has generation-tagged sender and receiver endpoints, a type, a small fixed
inline payload, and eventually an optional page/transfer handle for bulk data.
Start with eight records of 8-12 bytes. Repaint and pointer events keep their
existing coalescing rather than consuming this control queue.

Acceptance requires no nested recipient callback during send, deterministic
exhaustion, generation-safe delivery, teardown cancellation, root-only bounded
dispatch, and deferred equivalents for real synchronous shell interactions
before that older API is retired.

Estimated difficulty: **medium-high**. MSX2 status: **implemented in Milestone
3 with eight eight-byte records and four inline bytes**. Bulk handles and
delivery acknowledgements remain deferred.

## 5. Explicit filesystem handles and contexts

Replace reliance on one shared current drive, directory, entry, and launch name
with a small handle-based filesystem service. Hardware access may stay
serialized and atomic, but each client retains explicit state.

The first contract needs open/create by drive/path/name, offset read/write,
caller-owned directory enumeration, size/type/free-space query, close/cancel,
and bounded root-task transfer advancement.

Acceptance requires at least two independent contexts; File Manager scans that
cannot redirect another load; cancellable Notepad/Browser jobs; termination
cleanup; and one public contract exercised by CPC Albireo/M4/floppy, MSX
Nextor, and PCW floppy tests.

Estimated difficulty: **high**. MSX2 status: **first explicit-context slice
implemented in Milestone 4**, including independent File Manager enumeration,
bounded sequential transfer, launch handoff, and owner teardown. Notepad,
Browser, arbitrary seek/query operations, and CPC/PCW providers remain later
adopters.

## 6. GBAP v3 application manifest

Extend the executable preamble while preserving headerless, v1, and v2 apps.
Candidate v3 fields are minimum ABI and capabilities, stable application and
service identity, code size/entry, resource/data/secondary-code descriptors,
minimum/preferred page counts, compressed/uncompressed sizes, and lifecycle
flags.

Optional ZX0 decompression should be an on-demand measured component rather
than permanent kernel growth. Applications remain fixed-origin unless a future
format explicitly introduces relocation.

Acceptance requires pre-allocation compatibility rejection, all-segment
validation before publication, rollback on any failed load, and identical
runtime segments from compressed and uncompressed packages.

Estimated difficulty: **medium-high**. MSX2 status: **first slice implemented
in Milestone 5** with a platform-neutral manifest, strict deterministic tooling,
a guarded fixed-origin primary segment, and transactional pre-publication
rollback. Inspecting the manifest currently consumes the primary allocation;
storage-side pre-allocation scanning, compression, and additional runtime
segments remain deferred.

## 7. Application-owned secondary-code call gate

Allow optional application code in additional 16 KiB pages without adopting a
relocatable 63 KiB model. The resident gate validates an owned code-page handle
and entry offset, saves/maps/calls/restores, rejects unsafe re-entry, and uses a
fixed transfer record or registers rather than live pointers into a replaced
page.

Initial calls are root-only. Acceptance covers exact bank/stack restoration;
bad owner/entry/stale/nested/close-during-call paths; one common convention on
CPC/MSX2/PCW; and moving one real component out of its primary bank with
measurable recovered headroom.

Estimated difficulty: **high**.

MSX2 status: **implemented in Milestone 6** with one optional uncompressed
secondary image, a root-only app-linked fixed-RAM gate, explicit rejection of
bad owner/generation/entry/nesting/teardown, exact owner cleanup, and a real
FormRef renderer moved out of its primary bank. CPC/PCW providers and
storage-side segmented loading remain deferred.

## 8. Shared-service manager

Generalize shell discovery and on-demand modules into a platform-neutral
service lifecycle: find/acquire by functional ID, select a platform provider,
start on first acquisition, send bounded deferred requests, release a client
reference, and unload after the final release and completed work.

Networking is the best first provider because Browser and Telnet already have
different MSX UNAPI, CPC M4/Albireo, and PCW PerryNet implementations. Sound
and printing remain later optional services.

Acceptance requires deterministic reference counts, capability-driven
selection, safe multi-client sharing, rollback on provider failure, complete
unload cleanup, and no nested synchronous callbacks.

Estimated difficulty: **high after improvements 1-5**.

MSX2 status: **implemented in Milestone 7** with two windowless provider slots,
three generation-tagged client leases, first-acquire launch and rollback,
deferred request/reply/lifecycle messages, Desktop stale-owner collection, and
final unload. `NETSVC.APP` plus Telnet exercise the real UNAPI control plane.
Socket/bulk-session sharing, Browser adoption, and CPC/PCW providers remain
later work.

## Recommended dependency order

```text
Capability query
      |
General page allocator
      |
Application/window ownership split
      |
Deferred messages
      |
Filesystem handles --------+
      |                     |
GBAP v3 + code call gate    |
      |                     |
      +---- Shared-service manager
```

## Explicit non-goals

- Reimplementing SymbOS or providing SymbOS binary compatibility.
- General preemption through non-reentrant drawing, firmware, storage, or
  paged-module calls.
- A 32-window target or an unbounded queue.
- A fine-grained malloc heap in the first page allocator.
- Relocatable 63 KiB applications in GBAP v3.
- Moving all GBR, form, VDI, and window policy into the resident kernel.

The desired result is a more explicit and scalable GEMBENCH architecture that
still uses fixed capacities, deterministic failure, compact Z80 code, native
target backends, and the existing bank-safe application model.

## Reference material

- SymbOS facts and architecture: <https://symbos.org/facts.htm>
- SymbOS developer documentation: <https://github.com/Prodatron/symdoc-developer>
- Current GEMBENCH architecture: `ARCHITECTURE.md`
- Current runtime architecture: `../ARCHITECTURE.md`
- Current scheduler contract: `../PREEMPTIVE_MULTITASKING.md`
- CPC/PCW parity plan: `CPC-PCW-BACKPORT-PLAN.md`
