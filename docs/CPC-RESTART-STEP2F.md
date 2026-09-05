# Restart step 2F: shared deferred-message and timer dispatch

Issue: [#73](https://github.com/salvogendut/GEMBENCH/issues/73).
Branch: `feature/73-shared-deferred-timer-dispatch`, stacked on `31d02f4` (2E).
Validation date: 2026-09-05.

This continues [restart step 2](CPC-RESTART-PLAN.md), extracting existing MSX2
policy without changing the ABI or enabling a CPC desktop.

## Shared implementation and placement

| Shared unit | Existing policy |
|---|---|
| `kernel/core/deferred_api.asm` | Endpoint registration/unregistration, send validation/order, queue publication, current/free queries, service/accessory owner lookup and sender cancellation. |
| `kernel/core/deferred_queue.asm` | Queue-record addressing and bounded overlap-safe FIFO removal. |
| `kernel/core/deferred_purge.asm` | Generation-tagged sender/receiver purge on teardown/unregister, sender-only explicit cancellation. |
| `kernel/core/deferred_dispatch.asm` | One head per root-loop turn; remove before callback, validate receiver, map handler, expose stable delivery record, restore bank/busy and optionally activate. |
| `lib/gembench/core/timer_collect.inc` | Root-side timer mailbox validation, hidden-component acknowledgement, active-source tagging, visible damage composition and final release. |

Deferred code stays in its late resident-kernel position, after the graphics
driver's alignment padding. `msx_deferred.inc` supplies root-context and input
pointer checks, current-owner/validation, bank/callback, lookup and activation
hooks. Inline macros retain the original instructions and exported labels.
The public six-byte send record, eight-byte delivery record, eight-entry queue
and error precedence are unchanged.

The timer collector stays linked into Desktop, not moved into the nearly full
kernel. Its SDAS wrapper includes `msx_timer_collect.inc`, a checked state/hook
binding, and the shared SDAS core. The app builder adds the include search path
and tracks all three new include files as dependencies. This is the same
collector used for both retained native and release universal Clock requests.

Timer publication, universal `GB_PARAMS` marshaling/validation, low-level IRQ
and context copying, filesystem context and service implementations remain in
their existing providers. This package does not claim those are already shared
or that native applications are now universal binaries.

## Contracts and retained limits

`deferred_contract.inc` documents callback registers, phase-local scratch,
serialized root execution and fixed/indexed storage. Send validation remains
before the capacity test, preserving stale/no-handler versus full precedence.
MSX executable-pointer and full six-byte input-buffer checks remain in the
provider, including its current app-page/fixed-TPA rules and worker rejection.

The head is copied into the stable current record and removed before receiver
validation/callback. The busy guard rejects recursive dispatch while callbacks
can enqueue replies or cancel queued messages. Teardown/unregister purge both
directions; explicit cancellation matches only the sender, including generation.
Current-owner lookup during delivery follows the receiver's mapped code bank;
WM focus is not implicitly changed to the receiver.

Activation deliberately retains the existing pre-callback primary-slot and
post-callback alive-slot check, not a new generation/owner revalidation. Existing
lifecycle rules still apply; arbitrary self-destruction/slot reuse inside a
handler is not newly guaranteed safe. Delivery validates receiver liveness,
not sender liveness independently of the teardown purge.

The timer contract preserves the single coalesced mailbox: producers write
rectangle/generation before publishing slot+1; the root retains active bit 7
through painting and clears owner afterward. Hidden components record dropped
generation before dropped slot. The visibility test may replace the clip with
a fragment, so the immutable mailbox rectangle is reinstalled before repaint.
This is not a per-window timer queue or a new fairness/cadence policy.

Both contracts require fixed state and byte-indexed arrays. Timer capacity is
bounded below bit 7; queue capacity/record-size assertions bound byte arithmetic.
Providers must separately prove non-overlap with ROM, framebuffer, other state
and stacks. Assembly fixtures do not prove runtime concurrency or CPC hardware.

## Binary comparison and budgets

RASM 3.2.1 and SDCC/SDAS 4.6.2 #16671 are supplied through `my-distrobox`.
Pinned-before source is `31d02f4`; normal/cooperative kernel comparisons use
identical generated inputs, baseline instrumentation off and tiled title bars.

| Artifact | Bytes | Before/after result |
|---|---:|---|
| Normal Screen 6 kernel / child COM | 13,956 / 14,292 | Byte-identical. |
| Normal Screen 7 kernel / child COM | 15,534 / 15,870 | Byte-identical. |
| Cooperative Screen 6 / Screen 7 kernels | 13,929 / 15,507 | Byte-identical; no cooperative runtime claim. |
| App-carried scheduler | 1,448 / 1,536 reserved | Unchanged. |
| Timer collector | 116 Z80 code bytes | Complete SDAS `.rel` object byte-identical, including relocation records. |
| Desktop payload | 15,147 | Byte-identical after a normal rebuild with `DATA_LOC=0x7D90`. |

Kernel/child hashes remain those in [2B's table](CPC-RESTART-STEP2B.md#binary-comparison-and-budgets);
the scheduler hash remains that in [2D](CPC-RESTART-STEP2D.md#binary-comparison-and-budgets).
Desktop SHA-256 is
`552199b90097c7a6c5ee398152c0f1c0b15ea952f986a7e86d747ddc10e1abe5`;
collector object SHA-256 is
`ef808a884dd74d1a6e57750204da83560bb2679b6cc8324a7c0c48ccf8455c5b`.
No state or stack frames were added; Screen 7 retains 258 bytes of child-COM
headroom. The 983-byte selector is untouched and fresh normal symbols are
installed for diagnostics.

The new record-pointer expression masks the low byte before division. During
extraction, byte comparison caught RASM rounding `C380/100` to `C4`; masking
keeps the existing `C3` operand. A new instruction-byte test covers queue bases
with bit 7 set. This was an extraction error caught before runtime acceptance,
not a pre-existing application/emulator fault.

Both child COMs and Desktop match their staged CARD files. No release-media
refresh is needed; `QA/MSX/GBMSX.IMG` remains SHA-256
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.

## Behavioral validation

Paired runs use headless openMSX 21.0, Philips NMS 8250, 512-KiB expansion,
Nextor/Sunrise IDE, UNAPI off and private hard-disk images. Baseline scenarios
passed before extraction; existing diagnostic scripts were not changed.

| Check | Before and after result |
|---|---|
| SYSINFO deferred API and lifetime | PASS twice: deferred test mask `FF` required by the harness (register/current/free, bad type, full queue, cancellation, FIFO, sender/receiver identity and later delivery); eight pending heartbeat messages purged at close; owner `0103` reused as `0203`; final free pages 22, two owners/windows. |
| Native Clock partial/hidden/restored updates | PASS: hidden worker/draw/damage deltas `0/0/0`; covered and hidden framebuffer hashes stable; exact File Manager restore rectangle `4 26 56 158` and fresh draw delta 1 at a stable poll. |
| Universal Clock/Calculator accessories, Screen 6 and 7 | PASS: Desk dispatch, launch/activation and close/relaunch; ten stacking checks each; menus/borders/text intact; busy pages 4→3→4; final three windows, focus 1, no stack-guard fault. |
| Shared deferred assembly/contract | PASS: six unittest methods with low/high state, root-check variants, exact queue-pointer opcode/operand checks and negative fixed-span/index/capacity/record tests. |
| Shared timer assembly/contract | PASS: four methods covering independent low/high state, 116-byte deterministic code, app-build dependency/binding checks and invalid spans/index pages/active-bit capacity. |
| Existing ABI/mailbox checks | PASS: four universal-parameter and four background-timer tests, including recursive consume, stale generation and hidden acknowledgement. |

The independent providers are assembly fixtures, not executed CPC backends.
The existing workflows do not cover every malformed-pointer, nested lifecycle
or callback-failure path. Byte equivalence preserves the existing behavior;
it is not evidence of new validation guarantees or improved performance.

Reproduction with matching media/diagnostic artifacts:

```sh
MSX_HEADLESS=1 bash tools/test_m1_architecture_openmsx.sh
MSX_HEADLESS=1 bash tools/test_multi_event_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=6 bash tools/test_desk_accessories_openmsx.sh
MSX_HEADLESS=1 MSX_TEST_MODE=7 bash tools/test_desk_accessories_openmsx.sh
python3 tests/test_deferred_core.py -v
python3 tests/test_timer_collect_core.py -v
```

Local evidence: `/tmp/geobench-dispatch-baseline.tsAppj/` (raw/object comparisons),
`/tmp/geobench-dispatch-reference.31nSgJ` (pinned source, shared generated inputs
and isolated assembler output), `/tmp/geobench-73-{messages,clock}-{before,after}.log`,
`/tmp/geobench-73-clock-{before,after}.txt` and
`/tmp/geobench-73-desk-{6,7}-{before,after}.log`. Temporary paths are convenient
evidence locations; this document records the durable results.

## Next package

Filesystem-context state/service bookkeeping is next. Low-level context/IRQ
adapters and remaining publication/universal-parameter provider work also remain
before CPC desktop integration; restart step 2 is not complete.
The [M4/Albireo-only CPC runtime rule](CPC-EMULATOR-TEST-STRATEGY.md) remains in
force. No CPC emulator or floppy-backed runtime was used here. Untracked
`QA/CPC/` is preserved. Review and merge remain separate.
