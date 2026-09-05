# Step 3B: production caller-owned parameters

Date: 2026-09-05. Issue [#67](https://github.com/salvogendut/GEMBENCH/issues/67).
Branch: `feature/67-universal-caller-parameters`, stacked on #66.

This implements the public ABI/SDK/MSX2 adoption gate left open by the
[CPC hardware proof](CPC-RESTART-STEP3B.md). It does not restore a CPC desktop.
Runtime M4 I/O (3C), remaining shared-policy extraction and application parity
are still separate work.

## Contract

GEOBENCH-2.1 appends `GB_PARAMS` at `0x80D5`, retaining all 71 inherited slots
and the frozen GEMBENCH-1 contracts. The v6/48 sysinfo layout is unchanged:
universal minor becomes 1 and capability `caller-parameters` is `0x00800000`.
The authority and [ABI document](UNIVERSAL-APPLICATION-ABI.md) specify the
16-byte version-1 record, status codes and operation layouts.

The service validates whole primary-page spans below `0x7F00`, including text
with an explicit length of at most 48 bytes. It copies descriptors and pointed-
to text before any bank change and retains no pointers. Line/text are root-
callback operations; workers may publish/query/cancel timer values only.
Window validation uses the mapped application's identity and the live window
generation. Focus is not authority. The existing visible-damage collector is
retained, with a generation added to its private dropped-damage acknowledgement.

The C stack is kernel-owned fixed RAM. The SDK therefore constructs automatic
records, then an interrupt-protected assembly bridge copies them and any stack
text into application-primary storage. Both contexts can use the wrappers
without a shared root/worker request race. The kernel independently validates
and copies that storage. Interrupt enable, mapper state, stack and scheduler
lock must survive successful and rejected calls alike.

The builder requires ABI `[2,1]` and the new capability, preventing a new SDK
binary from being labelled as compatible with an older loader. The original
2.0 CRT checks an exact minor zero: `GB_SYSINFO` supplies a separate immutable
compatibility view for those old packages. Native and new callers retain the
canonical record. The new CRT uses a minimum-minor comparison. Future CPC/PCW
kernels must reject old packages using the framebuffer-aliasing convention.

## MSX2 placement and budgets

No application pages, stack guards, snapshots or legacy fixed-RAM limits are
reduced. The kernel bootstrap has already left its child-COM payload before
loading the support module into reclaimed TPA below `KCFG_TEXT`.

| Region/artifact | Placement or measured size |
|---|---|
| Admission + parameter + sysinfo module | `0x0400..0x0C1E`, 2,079 bytes |
| Reserved low-TPA module area | `0x0400..0x0FFF`, 3,072 bytes |
| ABI 2.0 compatibility sysinfo | `0x0F00..0x0F2F`, 48 bytes |
| Canonical sysinfo | `0xCF00..0xCF2F`, unchanged |
| Former admission-gate page-3 area | `0xCF30..0xD3FF`, still reserved |
| First app-usable fixed RAM | `0xD400`, unchanged |
| Screen 6 kernel / child COM | 13,956 / 14,292 bytes |
| Screen 7 kernel / child COM | 15,534 / 15,870 bytes |
| Child-COM ceiling | 16,128 bytes; Screen 7 has 258 bytes spare |
| ABI Probe / Calculator / Clock | 2,571 / 7,825 / 7,571 bytes |

The module cannot be an interrupt-entry routine: BIOS IRQs temporarily hide
page 0, then restore DOS RAM before returning. Its service serializes shared
scratch with the existing scheduler lock; it never schedules or runs callbacks.
Boot-only sysinfo construction moved out of the child COM, recovering space.
The low-RAM map, assembler module bounds and existing COM guards enforce this
placement. An absent, truncated or old-version module is rejected before the
new capability is published.

Do not pad the module to its loader buffer capacity: the existing loader's
exact-capacity EOF probe treats an EOF error as failure. The shipped module
uses its actual measured length, with an exact-size boot check and a larger
bounded loading area. This was caught by the first startup regression.

## Validation commands

Build with the existing local toolchain in `my-distrobox`:

```sh
MSX_UNAPI_TSR=QA/MSXDEPS/UNAPINET.COM bash tools/build_kernel_msx.sh
MSX_TEST_MODE=6 bash tools/test_universal_parameters_openmsx.sh
MSX_TEST_MODE=7 bash tools/test_universal_parameters_openmsx.sh
MSX_TEST_MODE=6 bash tools/test_geobench_v2_msx_openmsx.sh
MSX_TEST_MODE=7 bash tools/test_geobench_v2_msx_openmsx.sh
```

The parameter regression first performs the real Desk/Clock/Calculator
launch, activation, border/menu/text, close/relaunch and allocation workflow.
It then injects calls at a root application's public parameter entry, checking
pointer/size/operation/version boundaries, stale/foreign windows, queue busy,
cancel/active/drop behavior, worker restrictions and exact-end text spans.
It checks both interrupt-enable states, SP, mapper and scheduler-lock restoration,
stack/application guards, code integrity and no VRAM writes on rejection.
Injected calls are boundary evidence, not simulated successful UI interaction.
The launch regression also boots the actual old ABI 2.0 Probe from `a30a802`.

Run `make check` in a clean worktree: the user's untracked `QA/CPC/` leftovers
are deliberately preserved here and conflict with the release-only absence
check. Temporary probe media must not replace release QA media.

Validation results are recorded after the integration checks below.
