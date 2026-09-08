# Restart step 2H: client bindings, timer publication and parameters

Issue: [#75](https://github.com/salvogendut/GEMBENCH/issues/75).
Branch: `feature/75-shared-client-timer-parameters`, stacked on `fe88017` (2G).
Validation date: 2026-09-06.

This continues [restart step 2](CPC-RESTART-PLAN.md). It separates remaining
filesystem-client, native timer-publisher and receiving-side parameter policy
from their MSX2 state/hardware bindings. No CPC desktop is enabled.

## Shared code and provider boundaries

| Shared policy | Provider / retained placement |
|---|---|
| `lib/gembench/core/fsctx_client.inc` | App-linked native C marshaling. `include/gembench/msx/gbfsctx_client.h` supplies request/transfer storage through `gbfsctx_platform.h`. Full, directory-only, batch-only and combined profiles remain supported. |
| `lib/gembench/core/timer_publish.inc` | App-linked SDCC/Z80 worker publisher; `msx_timer_publish.inc` supplies fixed mailbox, current worker slot and window-generation table. |
| `kernel/core/parameters.asm` | Receiving-side `GB_PARAMS` descriptor/text copying, validation, owner checks and timer operations remain in the low-TPA support module. `msx_parameter_provider.inc` supplies state/geometry, owner/window calls, rendering and critical-section hooks. |

The public `gb_fsctx_batch_entries()` accessor now uses the same selected
transfer provider as the C wrapper. It no longer independently hard-codes
`0xC400`. Non-MSX builds must select `GB_FSCTX_PLATFORM_HEADER` explicitly;
there is no automatic CPC fallback. Local contracts check fixed storage,
request/transfer separation and frozen capacities. The native public gate at
`0x80D2` is unchanged. This does not advertise universal filesystem support or
turn these native clients into compile-once applications.

The native publisher's wrapper retains the SDCC ABI (A/L plus two stacked
arguments, IX preservation and callee cleanup). Its contract checks complete
fixed spans, indexed generation-table bounds and capacity below active bit 7.
The app builder adds the include path and tracks all new client/publisher
headers and includes as dependencies.

The parameter receiver still validates complete caller spans within
`0x4000..0x7EFF` before copying, copies text before native font mapping, validates
mapped identity and exact window ownership, and preserves interrupt state,
stack, bank and scheduler lock through its provider. The provider's line hook
alone bridges canonical parameters to the private MSX graphics workspace.
The shared contract checks fixed code/scratch/state, indexed owner storage,
four-pixel-column geometry and byte-sized coordinate limits.

## What deliberately did not change

The universal SDK's C request construction and Z80 stack-copy bridge are already
platform-neutral. `gbuniversal.c`, `gbuniversal_draw.s`, ABI 2.1, the 16-byte
parameter record and their canonical public mailboxes remain unchanged.
Those public mailbox addresses are ABI commitments, not places to substitute
per-target SDK constants. The three universal APPs retain identical hashes;
CPC must provide the matching services rather than require another APP build.

Retained limits and provider obligations:

- Native filesystem calls remain serialized root operations. Batch data expires
  at the next context call. READ clamps to 512 bytes; WRITE rejects larger input.
  Existing pointer preconditions and partial-copy/error/status behavior are not
  strengthened by this extraction. Target integer/packed-entry layouts remain
  the Z80 contract, not the host test ABI.
- The native timer publisher trusts its worker's current window slot. It rejects
  busy/fullscreen, zero extents and invalid slots; it does not gain universal
  parameter validation or general multi-producer atomicity. Invalid requests may
  touch unpublished rectangle bytes. Preserve the existing scheduler/mailbox
  single-writer protocol: rectangle and generation precede published identity.
- Universal timer requests retain stronger owner/span/geometry checks, copied
  values, generation-tagged dropped acknowledgement and non-cancellation of
  active consumption. No new queue, cadence or fairness policy is introduced.
- Provider hooks must restore their module bank/stack and preserve documented
  registers. Local assembler/C checks cannot establish a complete CPC memory
  map, interrupt latency, worst-case stack depth or runtime hook correctness.

## Binary comparison and budgets

Toolchain: RASM 3.2.1, SDCC/SDAS 4.6.2 #16671 in `my-distrobox`.
Pinned-before source is `fe88017`; isolated assembler outputs use identical
generated inputs. Normal kernels use preemption, baseline instrumentation off
and tiled title bars. No extra code, state cells or stack frames are introduced.

| Artifact | Bytes | Before/after evidence |
|---|---:|---|
| GBAPV4 admission/parameter/sysinfo module | 2,079 | Fresh baseline/candidate assemblies byte-identical. |
| Filesystem C object | Profile-dependent | Complete SDCC `.rel` objects byte-identical for all four profiles. |
| Native timer publisher | 75 code bytes | Complete SDAS `.rel` object byte-identical. |
| File Manager / native Clock / SYSINFO | 14,762 / 12,836 / 4,601 | Rebuilt payloads byte-identical. |
| Universal ABI Probe / Calculator / Clock | 2,571 / 7,825 / 7,571 | Rebuilt APPs byte-identical and matching staged CARD artifacts. |
| Normal Screen 6 kernel / child COM | 13,956 / 14,292 | Byte-identical. |
| Normal Screen 7 kernel / child COM | 15,534 / 15,870 | Byte-identical. |
| Cooperative Screen 6 / Screen 7 kernels | 13,929 / 15,507 | Byte-identical; no cooperative runtime claim. |
| Desktop / scheduler | 15,147 / 1,448 | Unchanged. |

The selector remains 983 bytes and Screen 7 retains 258 bytes of child-COM
headroom. Fresh normal kernel/module symbols are installed. Module/File Manager
and child COMs match their staged artifacts, so no release-media refresh is
needed. `QA/MSX/GBMSX.IMG` SHA-256 remains
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.

Universal APP SHA-256 values:

- ABI Probe: `a6a696cc0bef9caf69c38b6c44f8d8e50dbb7dd560c88e99feb9595993e0adfc`
- Calculator: `5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5`
- Clock: `8d605d045087199769dea40bfdfc50009a2a50bf958ffbcc26e97cdfcdfef2f2`

## Runtime and host validation

Paired before/after runs use the existing unchanged openMSX 21 scripts,
Philips NMS 8250, 512-KiB expansion, Nextor/Sunrise IDE, UNAPI disabled and
private hard-disk images. No CPC emulator or floppy-backed runtime is involved.

| Check | Result |
|---|---|
| Filesystem/deferred/owner lifecycle, Screen 7 | PASS before/after: required FSCTX mask `7F`, 53 context calls, owner `0103` reused as `0203`; final 22 free pages, two owners/windows and one File Manager context. |
| Native Clock partial/hidden/restored updates, Screen 7 | PASS before/after: covered/hidden hashes stable, fully hidden worker/draw/damage deltas `0/0/0`; exact restore rectangle `4 26 56 158`, fresh draw delta 1 at a stable poll. This is the retained native fixture, not a claim of equivalent coverage on every universal Clock component. |
| Public parameters, Screen 6 and Screen 7 | PASS before/after in both modes: 90 injected cases each, including span/size/version/op/geometry/owner/generation errors, timer operations, both IFF states and exact stack/bank/mapper/lock restoration. Four actual worker publications and 465 root drawing calls observed per run. |
| Release Desk/Clock/Calculator presentation | Included in both-mode parameter runs: borders, text, menu activation and close/relaunch intact; ten stacking checks, pages `4→3→4`, final three windows/focus 1 and zero stack fault. |
| New provider tests | Nine unittest methods PASS: actual filesystem client execution across four profiles and two state layouts; fixed-span/overlap rejection; real SDAS publisher and RASM parameter assembly with independent low/high state and 128×212, 80×200, 90×248 column/line geometries; negative layout/index/geometry/code-placement checks. |
| Existing targeted checks | Four universal-parameter and four background-timer tests PASS; filesystem header/gate/module build checks PASS (three-byte native gate, 2,024-byte module). |
| Full repository `make check` | PASS (exit 0) in a clean detached checkout at `c04ee97`: all 135 discovered Python tests, no skips, plus host-library suites, Z80 compilation/universal SDK builds, ABI and distribution audits. |

The host client tests execute production C with fake synchronous calls; they do
not establish Z80 integer sizes, packed structures or CPC storage correctness.
Independent RASM/SDAS providers are assembly fixtures, not executed CPC/PCW
backends. Parameter injection counts are boundary checks, not a performance
benchmark. Existing emulator observation rules were not changed for these runs.

Reproduction with matching media/diagnostic symbols:

```sh
MSX_HEADLESS=1 bash tools/test_m1_architecture_openmsx.sh
MSX_HEADLESS=1 bash tools/test_multi_event_openmsx.sh
MSX_TEST_MODE=6 bash tools/test_universal_parameters_openmsx.sh
MSX_TEST_MODE=7 bash tools/test_universal_parameters_openmsx.sh
python3 tests/test_client_parameter_core.py -v
make check
```

Local evidence: `/tmp/geobench-2h-baseline.GQUzGe`, pinned reference worktree
`/tmp/geobench-2h-reference.NDmZ4X`, `/tmp/geobench-75-build-compare.log`,
`/tmp/geobench-75-abiprobe.log`, `/tmp/geobench-75-targeted-checks.log`,
`/tmp/geobench-75-{fs,clock}-{before,after}.{log,txt}` and
`/tmp/geobench-75-params-{6,7}-{before,after}.log`. These paths are temporary
evidence locations; the durable results are recorded here.

Full-suite checkout: `/tmp/geobench-75-check.Qk7ZEZ`, with an independent clean
build directory; log: `/tmp/geobench-75-make-check.log`. Its freshly assembled
GBAPV4 module also matches the pinned baseline byte-for-byte. The static MSX
floppy-distribution audit does not boot a floppy or run a CPC emulator.

## Next package

Finish the low-level context/IRQ adapter boundary, including fixed-state and
stack/snapshot assumptions needed to connect the proven CPC banking/interrupt
foundation. Then approve a measured production CPC memory layout and wire the
shared core into staged desktop scenarios. CPC rendering/input/time/storage
providers, application integration and full parity remain later work.

The new boundaries do not enable `make cpc`, a CPC desktop, Albireo support or
PCW. The M4/Albireo-only CPC runtime policy remains in force; untracked `QA/CPC/`
is preserved. Review and merge are separate.
