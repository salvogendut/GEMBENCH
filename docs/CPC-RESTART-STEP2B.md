# Restart step 2B: shared window/application lifetime

Issue: [#69](https://github.com/salvogendut/GEMBENCH/issues/69).
Branch: `feature/69-shared-window-lifetime`, based on `2a17832` (step 3C).
Validation date: 2026-09-05.

This continues [step 2](CPC-RESTART-PLAN.md) after the isolated CPC foundation
proofs. It extracts the working MSX2 implementation; it does not enable the
parked CPC desktop or change the public ABI, application packages or UI.

## Extracted policy

| Shared unit in `kernel/core/` | Responsibility |
|---|---|
| `app_code.asm` | Bind the pending owner's primary code page and opaque page handle. |
| `window_identity.asm` | Window generations and handles; attach/detach, primary-window replacement, worker-window clearing; validate public handles against slot, generation, alive status and owner. |
| `owner_context.asm` | Resolve pending loader identity, then mapped-page owner, then the existing legacy focus fallback; attach a newly registering window to its owner. |
| `app_lifetime.asm` | Root/worker marking, application service lookup, owned-window scan, and existing `GB_APP` operations 0–8, including windowless publication and explicit quit. |
| `window_close.asm` | Close one window, preserve an application with surviving windows, and release its resources after the last window. |

The ordered includes replace the original bodies in `msx_page_pool.asm` and
`gbkern.asm`. There is one implementation of this policy, not a CPC copy.
`msx_window_close_slot` remains a real, exported diagnostic label at the same
address as the new shared `app_window_close_slot` label.

Close retains the original ordering: save owner/caller bank, establish damage,
remove the worker contribution, mark dead, remove from z-order, detach identity,
select/map focus, restore the caller bank, release resources when appropriate,
and repaint. The legacy ownerless page-release path is retained too.

Focus/z-order algorithms, damage and rendering, scheduling, loader/boot,
deferred dispatch, filesystem contexts and service-registry internals remain
in their existing implementations. Calling those providers from shared close
or reclamation code does **not** mean their policies have been extracted.

## Provider contract and memory

`msx_app_lifetime.inc` binds `CORE_*` state and `LIFETIME_*` hooks to MSX2.
Its inline macros retain the existing window-table access sequences without
extra calls, allocations or changes to flags/register behavior. The shared
units contain no MSX state addresses, window-table offsets, raw I/O or bank
instructions. Mapping is an explicit provider hook.

`core/app_lifetime_contract.inc` documents hook clobbers, scratch persistence,
mapping responsibility and serialized root/kernel execution. It checks the
new scalar/handle spans against fixed address space, and the generation array
against its low-byte indexing boundary. The complete platform map still has
to exclude framebuffer, overlays and other allocations; these local checks
alone cannot prove that map.

Internal attachment helpers require a valid fresh slot and consistent tables.
They are not public input validators. Public window operations retain the
existing ownership/generation checks. Mapped application identity remains
authoritative ahead of the legacy focus fallback. This is a behavior-preserving
extraction, not a redesign of those conventions.

## Binary comparison and budgets

The unchanged baseline artifacts were retained before editing. Both modes
were then assembled in the normal `build/msx` directory with matching generated
inputs and flags, followed immediately by the corresponding DOS stub. `cmp`
reports exact equality for all four artifacts:

| Artifact | Bytes | SHA-256, identical before/after |
|---|---:|---|
| Screen 6 kernel | 13,956 | `d152d66e690c3c7d35bd28227f51c7bdf75efea3d62821341413f5b94b37b531` |
| Screen 7 kernel | 15,534 | `c420f156c0552d30affb1e8a80c24a7883e5579b9563ce9430e9ab292e2c6829` |
| `GBMSX6.COM` | 14,292 | `8261c670520e5a5a4544f84cdf5440d2992ceb370f5c52fc80d3fa53e3cb6cb4` |
| `GBMSX7.COM` | 15,870 | `986debb2144defdef5f4bbe30b1a60c22c073df6531e6849098b2c30431eb9ba` |

Normal flags are `PLATFORM_MSX=1`, `GEMBENCH_BASELINE=0`, `PREEMPTIVE=1`,
`PREEMPTIVE_CONTEXT=1`, `TITLEBAR_TILE=1`, plus `MSX_SCREEN7=1` for Screen 7.
The stub uses the matching screen-mode define. The 983-byte selector launcher
was restored after these comparisons.

A clean source worktree at `2a17832`, using the same generated inputs, also
compares byte-identically against the extracted source with both preemption
flags set to zero:

| Cooperative kernel | Bytes | SHA-256, identical before/after |
|---|---:|---|
| Screen 6 | 13,929 | `f447b1d97fd321b748326ca1b564819d3b4731da964deda410bc4dda08805fdb` |
| Screen 7 | 15,507 | `da09cf9626b2ca6861288afb3f9024a268c3eb4464dcea0961705953f432da14` |

No cooperative-mode runtime test is claimed. The scheduler remains
1,448/1,536 bytes, the universal gate remains 2,079 bytes, and Screen 7 retains
258 bytes below its child-COM ceiling. State, instructions, stack use and
capacity are unchanged. This extraction creates no additional memory headroom.

No release image refresh is needed: the rebuilt executables are identical to
the staged files. The tested source image `QA/MSX/GBMSX.IMG` remains SHA-256
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.
Diagnostic scripts use private media copies; existing CPC QA files are untouched.

## Runtime and host validation

Toolchain: RASM 3.2.1; SDCC 4.6.2 #16671 from
`/var/home/salvogendut/Dev/sdcc/bin`; openMSX 21.0, Philips NMS 8250 with
512 KiB expansion and Nextor/Sunrise IDE. Tests run headless with optional
UNAPI disabled. No physical-machine or new CPC runtime result is claimed.

| Check | Result |
|---|---|
| Architecture diagnostic, before and after | PASS: public sysinfo v6; 25 retained pages; owner `0103` reopens as `0203`, window generation 1→2; owned-window validation/stale rejection; final 22 free pages, two owners/windows and one filesystem context. |
| PAINT lifecycle, before and after | PASS: three owned panes move/focus/close correctly; clean and exposed canvas hash `B99399C8`; peak five windows, final two; free pages 22→22. Explicit quit reclaims the multiwindow owner. |
| Desk/Clock/Calculator, Screen 6 and 7, before and after | PASS: menu registration and singleton lookup, borders/menu/text, close/relaunch allocation 4→3→4 busy pages; final focus 1, three windows, no deferred/shell busy state or stack-guard fault. |
| Existing M7 service lifecycle, one run against the unchanged executable media | PASS: failed-start rollback without leak; windowless provider creation/removal, lease refs 3→2→1→0, stale cleanup; final two owners/windows, zero providers/leases, unlocked. Response status 11 is expected network-unavailable with UNAPI off, not a networking success claim. |
| Independent lifetime provider checks | PASS: five unittest methods, including subcases. Actual shared assembly compiles with separate low (`0x2000`) and high (`0xD800`) state layouts and a different window-flags layout; invalid spans/index-page crossings are rejected. |

The independent providers are assembly/layout fixtures, not executed CPC
kernels. The service diagnostic still observes the private v5 sysinfo shadow;
the architecture diagnostic separately checks the canonical v6 record. Root
quit denial and every error permutation are not newly exercised by dedicated
runtime tests here; their instructions are preserved by the exact comparison.
Sampled accessory stack maxima vary with timing and are not worst-case bounds.

Reproduce the runtime checks after building matching MSX2 media and diagnostic
dependencies:

```sh
MSX_HEADLESS=1 MSX_UNAPI=0 bash tools/test_m1_architecture_openmsx.sh
MSX_HEADLESS=1 MSX_UNAPI=0 bash tools/test_m2_paint_openmsx.sh
MSX_HEADLESS=1 MSX_UNAPI=0 MSX_TEST_MODE=6 bash tools/test_desk_accessories_openmsx.sh
MSX_HEADLESS=1 MSX_UNAPI=0 MSX_TEST_MODE=7 bash tools/test_desk_accessories_openmsx.sh
make gembench-m7-service-probes
bash tools/test_m7_service_openmsx.sh
python3 tests/test_app_lifetime_core.py -v
```

Use `2a17832` for the before-extraction source and the same toolchain/generated
inputs for both revisions. Binary evidence is locally retained under
`/tmp/geobench-69-kernels.9Jzbf1/`. Runtime logs are
`/tmp/geobench-2b-{native,paint}-before.log`,
`/tmp/geobench-69-{native,paint}-after.log`,
`/tmp/geobench-69-desk-{6,7}-{before,after}.log`, and
`/tmp/geobench-69-service-reference.log`. These paths are temporary conveniences;
the results and hashes above are the durable record.

## Next boundary

Extract shared focus/z-order policy next, then visible damage and scheduling,
with the existing overlap/exposure regressions on MSX2 before any CPC desktop
integration. Deferred/timer and filesystem/service policy still need bounded
extractions. Step 2 remains in progress; neither this package nor the isolated
CPC driver proofs establishes complete desktop parity.
