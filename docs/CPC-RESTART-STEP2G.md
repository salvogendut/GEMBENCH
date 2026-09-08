# Restart step 2G: filesystem contexts and service bookkeeping

Issue: [#74](https://github.com/salvogendut/GEMBENCH/issues/74).
Branch: `feature/74-shared-filesystem-service-bookkeeping`, stacked on
`ad476cc` (step 2F). Validation: 2026-09-05/06.

This continues [restart step 2](CPC-RESTART-PLAN.md). It separates existing
MSX2 policy from fixed-state/native-operation bindings without changing its
ABI, memory placement or behavior. It does not enable a CPC desktop.

## Shared implementation

| Unit | Policy and placement |
|---|---|
| `kernel/core/fsctx_policy.inc` and `fsctx_layout.h` | Existing paged GBFSCTX.MOD context allocation/validation, names/paths, iterator retention, sequential offsets, bounded transfers, directory batches and one-shot launch handoff. |
| `kernel/core/fsctx_cleanup.asm` | Existing late resident teardown scan; invalidate only records with the exact closing owner/generation, without storage or module loading. |
| `lib/gembench/core/service_internal.h` | Existing app-linked provider/lease access, generation validation, clearing, discovery, context/lock guard, capability and deferred-status policy. Client/provider/collector C callers remain shared in `lib/gembench/gbservice_*.c`. |

`kernel/kc/msx_fsctx.h` binds fixed request/context/transfer/cursor storage and
native Nextor operations. Inline hooks retain the original call sites: drive/
directory selection, enumeration, load/save and free-space queries. The shared
policy treats the retained directory cursor as opaque. The current MSX2
provider supplies 64 bytes and three drive IDs.

`kernel/msx_fsctx_cleanup.inc` supplies resident record/table bindings.
`lib/gembench/msx_service.h` binds service tables, owner arrays and root/worker
identity. Non-MSX service builds must select an explicit
`GB_SERVICE_PLATFORM_HEADER`; there is no silent CPC fallback to MSX addresses.

The C contracts check fixed spans and pairwise non-overlap within each provider,
public capacities and workspace bounds. The RASM cleanup contract additionally
checks record stride and IX field displacements. Production map authorities
still own cross-subsystem/ROM/framebuffer/stack placement; local assertions do
not prove a complete CPC layout. Both build scripts track the new includes.

## Retained behavior and limits

- Four 144-byte filesystem contexts, 512-byte transfer buffer, generation-tagged
  handles and stale-before-foreign-owner validation remain unchanged. The
  resident gate captures caller identity and rejects workers before module work.
- Each storage operation is synchronous and returns with the module bank and
  stack restored. Native CHDIR uses the cursor workspace, preserving a pending
  WRITE payload. No persistent native handles survive between calls; a future
  backend that retains handles needs an explicitly reviewed cleanup contract.
- CANCEL rewinds context offset, not the directory cursor. An overlong direct
  SET_PATH request can leave a partially written path; this is retained behavior,
  not new transactional validation. Native reads still use a 24-bit offset and
  return zero without distinguishing every load failure from EOF. Nonzero-offset
  writes append; no new general seek or atomic-write guarantee is introduced.
- Pending launch handoff remains one-shot, consumed only after successful
  allocation. Owner teardown does not purge that handoff. The module relies on
  the resident gate for caller authority; it does not independently validate
  owner liveness or introduce new launch permissions.
- Service capacity stays two providers and three leases. Clearing retains
  generation bytes; the root collector reconciles stale owners/references and
  attempts at most one STOP enqueue per turn. Full queues cannot pin a released
  lease. The service lock is a root non-reentrancy guard, not an IRQ lock.
- Existing deferred API/startup hooks remain responsible for copied messages,
  caller bank/stack restoration and mapped owner identity. No network transport
  is moved into the manager; NETSVC still has its MSX2 provider.

## Binary comparison and memory budgets

RASM 3.2.1 and SDCC/SDAS 4.6.2 #16671 run through `my-distrobox`.
The pinned-before source is `ad476cc`, sharing only generated build inputs with
the candidate. Before/after kernel assembler outputs are isolated. Normal
builds use baseline instrumentation off, tiled title bars and preemption on.

| Artifact | Bytes | Result |
|---|---:|---|
| Normal Screen 6 kernel / child COM | 13,956 / 14,292 | Byte-identical. |
| Normal Screen 7 kernel / child COM | 15,534 / 15,870 | Byte-identical. |
| Cooperative Screen 6 / Screen 7 kernels | 13,929 / 15,507 | Byte-identical; no cooperative runtime claim. |
| GBFSCTX module | 2,024 | Byte-identical after rebuild; unchanged `0x6000` code and `0x7F00` data boundary. |
| Desktop / NETSVC / TELNET | 15,147 / 4,781 / 13,823 | All rebuilt and byte-identical. |
| Service clients A / B / C / D | 5,318 / 4,645 / 4,652 / 4,595 | All rebuilt and byte-identical. |
| App-carried scheduler | 1,448 / 1,536 reserved | Unchanged. |

There are no additional target code bytes, state cells or stack frames. Screen 7
retains 258 bytes of child-COM headroom; the 983-byte selector is untouched.
The rebuilt module/Desktop and child COMs match staged CARD files. Production
media was not refreshed because the payloads are identical. Image SHA-256:
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.

GBFSCTX SHA-256:
`9ab4d8b625b34d226eb635f3112a7cf86ac8f6eaddc337680caac9b85f83abdc`.
Desktop retains the [2F hash](CPC-RESTART-STEP2F.md#binary-comparison-and-budgets).

## Behavioral validation

Paired before/after runs use the existing, unchanged openMSX scripts, Screen 7,
Philips NMS 8250 with 512-KiB expansion, Nextor/Sunrise IDE, UNAPI disabled,
private hard-disk images and fresh normal kernel symbols. Screen 6 has binary
comparison evidence in this package, not a newly run lifecycle scenario.

| Check | Result |
|---|---|
| SYSINFO filesystem/deferred/owner lifecycle | PASS before and after. The harness requires filesystem mask `7F`; independent file offsets/read/write, exhaustion, stale/reused handles and cleanup pass. Owner `0103` is reused as `0203`; 53 FSCTX calls, final 22 free pages, two owners/windows and one File Manager context. |
| Multi-client shared-service lifecycle | PASS before and after. Failed startup status 10; duplicate 9, foreign lease 3 and fourth client full 4. References descend `3,2,1,0`; provider appears then unloads; final leases/providers/lock all zero and two baseline owners/windows. Seven responses; network-unavailable statuses `11,11,11`, not successful network traffic. |
| Actual C policy with independent state | PASS for low (`0x2000`) and high (`0xD800`) bindings. Filesystem allocation/generation/validation, interleaved iterators, batches, I/O bounds/failure, cancel and launch handoff; actual service client/provider/collector functions cover startup failure, queue pressure, owner death, stale leases, generation wrap and bounded STOP collection. |
| Provider/contract tests | Eight new unittest methods PASS: the executable C fixtures above, shared-source/dependency/layout checks, invalid fixed spans and overlap, and real RASM cleanup assembly with independent addresses and record layouts plus negative field/stride bounds. Existing three service-manager tests also pass. |
| Full repository `make check` | PASS (exit 0) in a clean detached checkout at `0395b27`: all 126 discovered Python tests, no skips, plus host-library suites, Z80 compilation/universal SDK builds, ABI and distribution audits. |

Host tests execute the real shared C implementation, not a second policy model.
Their native C integer widths and fake synchronous I/O do not prove Z80 ABI,
16-bit offset carry, interrupt timing or CPC hardware. Cleanup assembly fixtures
are not runtime evidence; the MSX2 owner lifecycle supplies that separately.
The existing service script observes a historical private sysinfo view; its
`SYSINFO=5,7FFF` diagnostic is not a public v6 ABI conformance check. No test
script's observation rules were weakened or changed to obtain these passes.

Reproduction with the documented toolchain and matching artifacts:

```sh
bash tools/build_fsctxmod.sh
make gembench-m7-service-probes
MSX_HEADLESS=1 bash tools/test_m1_architecture_openmsx.sh
MSX_HEADLESS=1 bash tools/test_m7_service_openmsx.sh
python3 tests/test_filesystem_service_core.py -v
python3 tests/test_service_manager.py -v
make check
```

Local evidence: `/tmp/geobench-2g-baseline.IDAyGX` (payloads/kernel comparisons),
`/tmp/geobench-2g-reference.5CGnGM` (pinned source),
`/tmp/geobench-74-build-compare.log`, `/tmp/geobench-74-policy-tests.log`, and
`/tmp/geobench-74-{fs,service}-{before,after}.{log,txt}`. These temporary paths
are convenient evidence locations; this report records the durable results.

Full-suite evidence: `/tmp/geobench-74-check.Ib1gNf` has its own clean build
directory; output is `/tmp/geobench-74-make-check.log`. The suite's static MSX
floppy-distribution audit does not boot a floppy or run a CPC emulator.

## Next gate

App-side filesystem marshaling in `lib/gembench/gbfsctx.c`, native timer
publication and universal-parameter adapters still need their provider boundary,
along with low-level context/IRQ adaptation. Native CHDIR/BDOS/module loading
remain intentional MSX2 leaves. CPC must implement matching providers around
its proven M4 foundation; no Nextor code is transplanted into CPC.

Finish those boundaries and the production CPC memory/stack budget before
integrating the shared desktop in the restart plan's order. Application parity,
M4 release packaging and Albireo qualification remain later gates. No CPC
runtime or floppy-backed test was run; untracked `QA/CPC/` is preserved.
Review and merge remain separate.
