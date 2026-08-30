# Architecture Milestone 1: MSX2 foundations

Status: **implemented on the MSX2 target in issue
[#31](https://github.com/salvogendut/GEMBENCH/issues/31)**.

This milestone implements the first two items from the SymbOS-inspired
architecture review: a runtime capability query and a general 16 KiB page
allocator. It also supplies the minimum generation-tagged application identity
needed to own and reclaim those pages. CPC and PCW do not implement or advertise
these services yet.

## Runtime capability record

`GB_SYSINFO` at `0x80C3` returns `DE` pointing to a resident, read-only
`gb_sysinfo_t`. The first byte is the record size and the second is the record
version. Milestones 2 and 3 append fields without changing this 20-byte v1
prefix; the current kernel returns the v3 record documented in
[ARCHITECTURE-M3-MSX.md](ARCHITECTURE-M3-MSX.md).

| Offset | Bytes | v1 field |
| ---: | ---: | --- |
| 0 | 1 | record size (`20` for v1; currently `28`) |
| 1 | 1 | record version (`1`; currently `3`) |
| 2 | 2 | GEMBENCH ABI major/minor (`1.0`) |
| 4 | 1 | platform (`GB_PLATFORM_MSX2`) |
| 5 | 1 | native video mode (`6` or `7`) |
| 6 | 4 | pixel width and height (`512 x 212`) |
| 10 | 2 | packing and colour count |
| 12 | 4 | physical, retained, free 16 KiB pages and maximum windows |
| 16 | 2 | `GB_CAP_*` capability bits |
| 18 | 2 | reserved, zero in v1 |

The page count and the window limit are deliberately separate. On the 512 KiB
Omega/openMSX configuration used for validation, DOS and `PAGE_DATA` leave 25
complete pages in the general pool while the compositor remains bounded to
eight windows. The precise retained count is runtime data and can differ with
the DOS, mapper, TSRs, and machine configuration.

`GB_CAP_NETWORK` currently means that the MSX build contains the compatible
network client/service class. Provider presence is still discovered by the
existing transport at runtime; a live UNAPI provider is not implied. Provider
selection becomes a separate contract in the later shared-service milestone.

## Owner identity

`GB_OWNER` at `0x80C6` returns a 16-bit opaque owner handle. Its low byte is an
internal slot plus one and its high byte is a nonzero generation. Applications
must compare or pass the whole value and must not decode either byte.

The loader creates an owner before loading an application page. Registration
binds that pending owner to the existing managed-window slot without changing
the frozen window record. During a callback, the mapped application page is the
authoritative owner; focus is only a fallback. Closing the application's current
window releases every page with that owner and advances the generation before
the owner slot can be reused.

This was the minimum identity required by Milestone 1. Milestone 2 promotes it
to an independent application record and permits multiple windows per code
page. Queues, process hierarchies, priorities, and multiple workers remain
later work; see [ARCHITECTURE-M2-MSX.md](ARCHITECTURE-M2-MSX.md).

## General page allocator

`GB_PAGE` at `0x80C9` implements three operations. The opt-in C bindings expose
them as:

```c
gb_page_t gb_page_alloc(unsigned char purpose);
unsigned char gb_page_free(gb_page_t page);
unsigned char gb_page_check(gb_page_t page);
```

A page handle is also 16 bits: internal slot plus one in the low byte and a
nonzero allocation generation in the high byte. The native mapper segment is
private kernel metadata and is never returned by the public C interface.
Purposes distinguish application code, resources, documents, caches, scrap,
and temporary storage. They are ownership metadata in this milestone; a later
transfer or call-gate service will consume the opaque handle.

Allocation validates the current owner, skips both general allocations and old
eight-page compatibility reservations, and returns zero on failure. Check and
free distinguish stale, foreign-owner, already-free, and invalid handles.
Reallocation advances the page generation, so a freed handle cannot operate on
the next occupant. Generations are eight bits and handles are short-lived
runtime identities, not persistent file or inter-process identifiers.

The old `APP_PAGES`/`APP_BUSY` table remains an eight-entry compatibility view
for existing picture clients. General allocations in those entries update both
views. A legacy reservation is counted and skipped by the general allocator;
its first `GB_PICEDIT` transfer adopts it into the current owner so normal owner
teardown can reclaim it. Pages 8 through 31 exist only in the new allocator.

## Resident metadata

The original MSX page-3 RAM allocation from `0xC200` through `0xC307` holds the
private page/owner tables and the current public capability record:

- 32 native segment, state, owner, owner-generation, page-generation, and
  purpose bytes;
- eight active owner/generation pairs and eight parallel window-owner pairs;
- loader/close/allocator scratch and pool totals; and
- the stable 20-byte `GB_SYSINFO` v1 prefix plus the four-byte v2 suffix.

Milestone 3 extends sysinfo through `0xC30B`, moves the private application/
window block to `0xC30C-0xC361`, and appends deferred-message metadata through
`0xC3C5`.

This storage is outside the application page and does not consume another
mapper segment. Native segment values and table addresses are implementation
details. The diagnostic may inspect them to prove foreign-owner rejection, but
ordinary applications must not.

## Building and validation

The public bindings are opt-in to preserve the byte layout and headroom of
applications that do not use them:

```sh
SYS=1 APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/sysinfo build/msx/SYSINFO.RAW
```

The development diagnostic is not staged in the release image by default.
Build and exercise it with:

```sh
make gembench-m1-sysinfo
make gembench-m1-openmsx
make gembench-m2-openmsx
python3 debug/gembench_baseline_1983.py --output-dir build/m1-1983
```

The openMSX lifecycle test opens the diagnostic twice and verifies capability
fields, allocation/check/free, exhaustion, legacy-mirror isolation, foreign and
double-free rejection, page generation invalidation, owner generation reuse,
multi-window attach/close, and bulk cleanup of a deliberately retained cache
page. The complementary 1983 run verifies boot, mapper discovery, the 25-page
pool on the reference 512 KiB configuration, and the resident versioned record.

## Target boundary

Only the `PLATFORM_MSX` kernel includes `kernel/msx_page_pool.asm`, and `SYS=1`
rejects non-MSX application builds. The public C types and operation names are
kept target-neutral so later CPC/PCW backends can implement the same contract,
but those targets must not claim `GB_CAP_PAGE_ALLOC`, `GB_CAP_OWNER_ID`,
`GB_CAP_APPLICATIONS`, `GB_CAP_MULTI_WINDOW`, or the new jump-table calls until
their own implementations and tests exist.
