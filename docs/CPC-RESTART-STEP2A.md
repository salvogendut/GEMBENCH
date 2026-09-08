# Restart step 2A: shared owner/page policy

Issue: [#64](https://github.com/salvogendut/GEMBENCH/issues/64).
Branch: `feature/64-shared-owner-page-core`, based on the step-1 plan branch.
Reference runtime: `5ed8a157656848cad1db1e21c68490ef06b015cb`.
This is the first bounded extraction in [step 2](CPC-RESTART-PLAN.md), covering
the owner/page portion of R09/R10 and its teardown dependencies.

## Extracted implementation

The existing algorithms are now included from `kernel/core/` at the same
positions in `kernel/msx_page_pool.asm`:

| Unit | Shared policy |
|---|---|
| `page_count.asm` | Count free pages while respecting the legacy busy mirror. |
| `owner_identity.asm` | Reset reusable application fields; allocate and validate nonzero generation-tagged owners. |
| `page_pool.asm` | Resolve an owner by native page tag; allocate/check/free owned pages; adopt legacy reservations. |
| `owner_reclaim.asm` | Purge owner resources in the existing order, invalidate its identity/window links, and retain the privileged legacy allocation/free wrappers. |

`kernel/msx_owner_page.inc` binds state and callbacks to the current MSX2
implementation. It emits no runtime instructions except the existing inline
free-count publication sequence at its original call site. No indirect-call
overhead or extra resident data is introduced.

MSX2 still owns boot-time DOS mapper discovery, the native page list, public
sysinfo layout/initialization, mapping/current-owner resolution, full window
attachment and application lifecycle, deferred dispatch and filesystem
adapters. Those remaining units are deliberately not presented as extracted.
The shared policy itself performs no bank switch, BIOS/DOS call or device I/O.

## State and calling contract

`kernel/core/owner_page_contract.inc` defines the provider obligations and
assembly-time checks. State is selected by `CORE_*` symbols rather than MSX
addresses:

- Per-page native tag, allocation state, owner/generation, page generation and
  purpose arrays; a runtime total/free count and bounded allocator scratch.
- Per-owner active/generation and reusable application fields, including
  registered handler bytes; parallel per-window owner links.
- The legacy busy mirror and pending-loader owner handle.

The provider initializes a unique native-tag list and a nonzero runtime total
at or below its declared capacity. Tags stay private: applications use opaque
handles. Existing consumers use zero as the failure/unbound native-code value;
this extraction does not broaden that legacy convention or alter generation
wrap semantics.

The arrays retain their low-byte indexing optimization. Each indexed array
must fit in one 256-byte page; all cells and two-byte scratch handles must lie
outside the banked `0x4000..0x7FFF` aperture. The provider remains responsible
for avoiding overlap with other state, framebuffer, modules, interrupt work
and stacks. A valid array bound alone cannot prove a complete machine map.

| Provider hook | Existing contract retained |
|---|---|
| `OWNER_PAGE_CURRENT_OWNER` | Return the current owner in DE with the existing `owner_current` clobbers; mapped code-page identity and pending-load handling remain authoritative. |
| `OWNER_PAGE_PURGE_MESSAGES` | Cancel queued owner endpoints during reclamation; preserve the owner saved in `CORE_ALLOC_OWNER`. |
| `OWNER_PAGE_CLOSE_CONTEXTS` | Invalidate owned filesystem contexts without loading a module or doing I/O; preserve `CORE_ALLOC_OWNER`. |
| `OWNER_PAGE_PUBLISH_FREE` | Inline macro consuming A=count while preserving registers/flags; publish the platform's free-count snapshots. MSX2 updates both public v6 and private v5 views. |

Calls remain serialized kernel/root work. Code and stack must remain visible
while the application page is mapped; preemptible workers cannot enter these
services directly. The current owner/page policy needs native-tag lookup but
no new bank-switch service. `bank_set` and its shadow stay in the MSX2 backend
until a later extraction actually requires them.

## Baseline diagnostic correction

The first openMSX run on the unchanged reference kernel timed out because the
development `SYSINFO.APP` required exactly a 32-byte v5 record. The production
kernel already returns v6/48. Its guarded deferred registration therefore never
ran, even though the application was loaded.

Commit `64ff6f0` fixes this separately from kernel extraction: the diagnostic
accepts the compatible v5 prefix, publishes the pointer returned by
`GB_SYSINFO`, and displays the reported version. The emulator checks that actual
record, including its v6 suffix, on both launches. Boot readiness uses the
matching layout source because the normal RASM symbol output omits EQU values;
it does not read an application variable before that app is loaded.

The corrected diagnostic was run against the **unchanged** reference kernel
before using it as the after-extraction check. This correction changes only a
development diagnostic and its driver, not the release app set or kernel ABI.

## Validation

The isolated validation tree is `/tmp/geobench-cpc-restart-baseline.iKQ6w8`.
The toolchain is recorded in [the step-1 baseline](CPC-RESTART-BASELINE.md).
A full network-free reference distribution was built there once. Matching
applications, assets and loader inputs were retained for the kernel-only
before/after comparison; extracted sources and the corrected diagnostic were
then applied in that same isolated tree.

The Screen 6 and Screen 7 kernels and DOS child files compare equal with `cmp`:

| Artifact | Bytes | SHA-256, identical before/after |
|---|---:|---|
| `GBKERN6.RAW` | 14,212 | `ae25699468da8003fd2b0a5ea515832e1b10cf85dc970eaf02e7506cdbd10c11` |
| `GBKERN7.RAW` | 15,790 | `59b2a303d903d5aa5f99122cbdddf7dc20b7a23b2b03abe49ad1a23b3fe4306a` |
| `GBMSX6.COM` | 14,548 | `a94eb1e97803e97c1f1ed399cbc112f525cc1601207d4cc16ea4d11f4ab1a111` |
| `GBMSX7.COM` | 16,126 | `35bb426b5089dfa967f6cd0ab521bf074e5a022018cf5e5de8b0100159e39ac8` |

The scheduler stays at 1,448/1,536 bytes. Screen 6/7 retain 1,580/2 bytes of
child-COM headroom. The extraction changes neither instructions nor stack use
on MSX2; it does not create additional headroom. No new stack high-water
measurement or CPC performance result is claimed.

`tests/test_owner_page_core.py` assembles the actual shared source with
independent low-RAM (`0x2000`) and high-RAM (`0xD800`) state providers, without
MSX glue or mapper symbols. Negative cases reject table-page crossing, banked
application memory, straddling scratch handles, and invalid pool capacities.
These are assembly/layout tests, not emulated CPC execution tests.

Fresh results on 2026-09-05:

| Check | Result |
|---|---|
| Corrected architecture diagnostic, before and after extraction | PASS in openMSX: 25 retained pages; owner `0103` closes and reopens as `0203`; both launches start with 21 free pages and retain one; final state restores 22 free pages, two owners/windows and File Manager's one filesystem context. |
| PAINT lifecycle, before and after extraction | PASS in openMSX: all three pane moves, focus/exposure checks and independent close paths; peak five total windows; final state restores 22 free pages and two owners/windows. |
| Screen 6/7 boot, after extraction | PASS in openMSX using the existing two-mode smoke. This smoke still observes the private v5 shadow; the updated architecture diagnostic additionally validates the public v6 record. |
| Independent state-layout assembly and rejection cases | PASS: four unittest methods, including subcases, assemble real shared code and enforce its indexing/fixed-RAM constraints. |
| Full `make check`, after extraction | PASS: 61 discovered Python tests plus all existing C, assembly, package, asset, media and ABI checks. |

The runtime uses the launcher's Philips NMS 8250 + 512 KiB expansion + Nextor
configuration, headless openMSX, and disabled optional UNAPI. Core comparisons
use the same source inputs, flags and toolchain in both runs. The separate
diagnostic correction is present on both sides of the behavioral comparison.
No 1983 or CPC run is claimed for this extraction.

Local logs in the validation tree are `m1-runtime-v6-baseline.log`,
`paint-runtime-before.log`, `m1-runtime-after.log`, `paint-runtime-after.log`,
`modes-runtime-after.log`, and `make-check-after-release.log`. These temporary
paths are conveniences; the results and binary hashes above are the durable
record.

The first after-extraction `make check` reached its media audit and rejected
the intentionally network-free floppy because the release fixture check
requires `UNAPINET.COM` and its notice. Regenerating only the disposable
floppies through `tools/build_msx_floppy.sh` with its normal dependency defaults
restored the expected release profile; the complete suite then passed. No
runtime or test assertion was changed to suppress that failure.

To reproduce the runtime checks in a clean checkout with the documented
toolchain/Nextor inputs, first build the distribution and then run:

```sh
MSX_HEADLESS=1 MSX_UNAPI=0 tools/test_m1_architecture_openmsx.sh
MSX_HEADLESS=1 MSX_UNAPI=0 tools/test_m2_paint_openmsx.sh
MSX_HEADLESS=1 MSX_UNAPI=0 tools/test_m3_boot_modes_openmsx.sh
python3 tests/test_owner_page_core.py -v
```

For the pre-extraction comparison use `64ff6f0`: it contains the corrected
diagnostic but the original MSX2 kernel. Build each revision with the same
compiler/assembler and compare the four artifacts listed above. The common
layout tests exist only after extraction. Use the explicit `SDCC`/`SDAS`
overrides from the step-1 record when running `make check` outside the usual
development directory.

## Remaining step-2 work

Next extract window attachment/validation and full application lifetime through
the same state provider, keeping compositor policy unchanged until its own
gate. Then address shared visibility/scheduling, deferred/timer paths and
filesystem/service bookkeeping in bounded packages. The experimental ABI's
CPC framebuffer/mailbox collision remains a separate design task before the
CPC hardware foundation can pass.

No CPC target is enabled by this change. The old CPC branch and its generated
workspace artifacts remain preserved. The production workspace's media were
not replaced by the disposable validation images.
