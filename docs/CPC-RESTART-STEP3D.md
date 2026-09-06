# Restart step 3D: production CPC memory layout and adapters

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`, based on context/IRQ #76 at
`076f01f`. Parent plan: [CPC-RESTART-PLAN.md](CPC-RESTART-PLAN.md).

Status: **3D-A is implemented and M4/1984 validated; the complete production
adapter gate is still open.** This checkpoint connects actual shared context
and visibility code to a checked CPC layout and CPC hardware. It is not a
desktop, public application loader, or proof that the complete kernel fits.
The remaining 3D-B work below must finish before the first shared-core window.

## Why the addresses change

MSX2 has VRAM outside the CPU address space. CPC Mode 1 consumes the complete
`C000..FFFF` CPU page, including 384 non-display raster-gap bytes. None of that
page may hold fixed architecture tables, M4 responses, commands or stacks.
The old native CPC bulk-buffer map and the newer shared architecture state
cannot simply coexist. The isolated foundation probes also occupied high
addresses needed by the final kernel; those addresses are not carried over.

The map authority is `lib/cpc/production_layout.inc`. Assembly asserts reject
stack/table/code overlaps; `tools/build_cpc_production.py` checks contiguous,
exclusive ownership of all 65,536 CPU addresses and records the allocations
and actual linked section sizes in the image manifest. Reservations below are
explicit budgets, **not measured implementations or free RAM claims**.

## Fixed allocations

All end addresses in this table are exclusive.

| CPU range | Owner / status |
|---|---|
| `0000..0100` | Vectors; owned IM1 vector at `0038`. |
| `0100..0400` | Fixed low M4 core loader, implemented. |
| `0400..1000` | Low support/universal receiver budget, not linked. |
| `1000..1A00` | Native fixed state; retained 25-byte window records, eight slots, bank/context cells. Other native clients are not linked. |
| `1A00..2000` | Explicit hardware state, bounded M4 staging, keyboard/ticks and private boot/test telemetry. |
| `2000..2900` | Shared architecture table budget; context/visibility subset bound, remaining owner/lifetime/defer/FS bindings pending. |
| `2900..2F00` | Actual shared context/visibility scheduler: **1,437 / 1,536 bytes**. |
| `2F00..3000` | Sysinfo budget; no public CPC record advertised yet. |
| `3000..3400` | Reserved integration state. |
| `3400..3500` | Drawing staging budget; not used by this non-drawing test. |
| `3500..3800` | Main/IRQ/temporary stacks and guards. |
| `3800..3E00` | Bank, bounded M4 transport, IRQ and raw input leaves: **1,055 / 1,536 bytes**. |
| `3E00..4000` | Native 512-byte clipboard reservation. |
| `4000..8000` | Banked application aperture; payload below `7F00`, last 256 bytes reserved for shared context snapshots. |
| `8000..C000` | Resident kernel budget, **not linked in full**. Current admission/private probe uses 558 bytes. |
| `C000..10000` | Complete CPC framebuffer page, never fixed state or staging. |

512 KiB admits 29 aperture pages: base configuration C0 and four pages from
each of seven expansion groups. F7 is reserved for data/modules, leaving 28
potential owner-pool pages including C0. The real shared allocator and module
loader are not initialized by this test; no free-page or module-capacity
guarantee is published. RAM admission writes/checks unique two-byte tags in
all 29 **unallocated** aperture pages and always restores C0. Missing/aliased
memory is rejected before application allocation; the 128-KiB fixture fails.

Native geometry remains 80 four-pixel byte-columns by 200 top-down scanlines;
public ABI 2.1 remains pixel/top-down and caller-owned `GB_PARAMS`. No universal
APP byte, public ABI constant, MSX2 state map or release build is changed here.
The old native bulk-buffer addresses are not a universal ABI promise.

### Stacks

| Stack | Live range, exclusive end | Guard bytes on each side | Observed high-water |
|---|---|---|---|
| Main | `3510..3610`, 256 bytes | 16 | 26 bytes |
| IRQ time sampling | `3630..3730`, 256 bytes | 16 | 4 bytes |
| Context-copy temporary | `3750..37D0`, 128 bytes | 16 | 6 bytes |

The context snapshots observed are 24 bytes for root yield and 26 for worker
IRQ preemption; shared `SCHED_STACK_MAX` is 26. These measurements cover this
fixture, **not** maximum real application/drawing/FS call depths. Stack-fill
canaries and all six guard sides are checked after actual execution.

## Composition and takeover

The three previously proved hardware leaves now have a single source:
`lib/cpc/bank.asm`, `graphics.asm`, and `m4.asm`. Their old foundation paths
are include wrappers. Promotion preserves the earlier probe binaries exactly.
Graphics is promoted for the next integration, but is **not linked into this
production-address image yet**. Its request validation and generated pointer/
row tables remain in the 3B diagnostic until the receiving adapter is connected.

`kernel/cpc_scheduler.asm` includes the same `kernel/core/` context-init,
save/restore, task-startup, worker selection, visibility/region and IRQ-dispatch
units used on MSX2. CPC files bind addresses, bank selection and IRQ return;
they do not implement another scheduling or visibility policy. The native
record accessor is a hardware-layout provider, not a window manager.

Boot sequence:

1. M4 firmware loads only the 2,823-byte `BOOT.BIN` at `8000`, ending below
   `9A00`, with firmware workspace still intact. The final firmware call sets
   Mode 1; takeover then disables interrupts and ROMs.
2. A temporary boot stack at `9F00` stays outside the low area being cleared
   and canary-filled. Bootstrap copies the measured scheduler/hardware leaves
   and the 170-byte loader into their final low allocations. It initializes
   truthful bank/GA/ROM shadows and disables M4 NMI.
3. Execution jumps to the low loader with the guarded main stack. The same M4
   runtime transport reads raw `/CORE.BIN` in at most 128-byte chunks into
   `8000..BFFF`, checking status and exact count. No firmware call occurs here.
   Loading may overwrite the earlier high bootstrap and firmware workspace.
4. The high core checks RAM, installs owned IM1, initializes shared contexts
   and runs the private integration fixture. Loader errors halt with `E1`;
   test errors publish an explicit failure. Exiting takeover currently means
   resetting, not returning to BASIC.

The `full-slot` variant extends the 558-byte probe to all 16,384 bytes with
`B9` padding. This proves the low-loader lifetime when the high slot is fully
overwritten. Padding is **not complete-kernel size evidence**.

## Adapter contracts exercised

- Bank switching uses only admitted C0/C4..F7 configurations and the same
  fixed-code leaf for root, IRQ/context restoration and M4. The caller owns DI.
- The CPC IRQ wrapper first samples fixed counters on its guarded stack,
  preserves registers and restores the raw interrupted-PC stack, then enters
  the shared dispatcher. Its owned completion is `EI; RETI`, not a firmware
  chain. A nominal 300-Hz tick source supplies a six-tick worker quantum.
- Software ticks/seconds are explicit fixed state. `cpc_ticks_read` preserves
  caller IFF. There is no mandatory RTC; missed IRQs during DI/bus holds are
  **not recovered**. This is not yet a qualified wall-clock/time-of-day API.
- Root-owned keyboard scanning uses 8255/AY directly, publishes ten active-low
  rows including joystick, preserves entry IFF and leaves AY inactive/port A
  output. The runner presses Right via the emulator keyboard; it does not
  inject input data into RAM. Text/repeat/event translation and mouse-device
  detection are still pending, not replaced by a fake mouse-present flag.
- The existing M4 request gate stages caller-page request/path/data before
  replacing the aperture, bounds transfers to 128 bytes, and restores bank,
  ROM/mode, IFF and stack before returning. It remains serialized with **DI
  over the entire request**. No bounded CPU loop can time out a hardware-held
  M4 ACK bus cycle; responsive storage integration is still an exit criterion.
  No public FS-context provider or new write-transaction guarantee is claimed.

Two synthetic native records exercise the actual shared scheduler: root is
partly visible; the focused managed worker is visible/runnable. Its task starts
through the real `k_task_enable` initial snapshot, repeatedly increments a
counter in C4 and **never voluntarily yields**. Root yields, actual IRQ dispatch
preempts the worker, and root resumes with its C0 page and stack. Each of 64
rounds performs a real `/DATA.BIN` M4 read, alternating DI/EI caller entry and
checking the returned IFF, bank and all 64 bytes. The private worker counter
wraps; it is not a slice count or benchmark.

## Validation on 2026-09-06

1984 runner: unchanged `../1984/1984`, CPC 6128 / 512 KiB / M4, SHA-256
`0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`.
RASM 3.2.1 in `my-distrobox`. All boots use private FAT16 M4 image copies,
never floppy media or snapshot injection. Snapshots only observe CPU/RAM state.

| Runtime case | Result | Artifact directory under `/tmp/` |
|---|---|---|
| Normal | 64 root/worker rounds + 64 I/O checks, 926 IRQs, 277 M4 commands; PASS | `geobench-cpc-production-9d8_51lp` |
| Full high slot | Same 64 rounds, 769 commands, all 16 KiB core bytes intact; PASS | `geobench-cpc-production-wk60wrg9` |
| Damaged main guard | Rejected for guard damage | `geobench-cpc-production-zw5ser1j` |
| Wrong restored caller bank | Rejected with failure 6 (wrong returned data) | `geobench-cpc-production-tdgww__m` |
| 128 KiB | Rejected by RAM admission, failure 8 | `geobench-cpc-production-dbrxr602` |

Positive checks additionally require exact linked code in all four allocations,
shared visibility/current/lock/runnable state, no unfinished I/O or pending IRQ,
correct software tick-divider arithmetic, root/worker snapshots, ROM/mode/IFF,
balanced SP, and the **entire unchanged framebuffer including raster gaps**.
The framebuffer SHA-256 is
`fe4dde11b323cc80d43176778f8d4977ce45617d7d8448568b2484a4f60b7d73`.
An additional 150 emulated frames must leave all RAM stable after completion.
IRQ totals are observations, not deterministic latency targets.

The three foundation suites were rerun before and after hardware-source
promotion. They remain byte-identical and pass from M4:

| Proof | After-promotion runtime | Raw payload SHA-256 |
|---|---|---|
| 3A | 1,450 page/IRQ checks, `geobench-cpc-foundation-k01r_av3` | `5ccdaf35f5142ac2d4a51648f6a99b6df0f14766f2d0cba256c586194105ada0` |
| 3B | 2,450 requests / 24 exact pixel checkpoints, `geobench-cpc-foundation-f0gum4x1` | `e722d7b4235241717e6d6124c51b62a1cf19684389d982abe589907b0ed2232e` |
| 3C | 592 requests / 913 commands / 74 byte checkpoints, `geobench-cpc-foundation-0sllv_kd` | `315ecacce00e1437f127c3e6538b5676ce39421517cb96585cfd629e37a36f52` |

Seven new host tests assemble all variants, check deterministic raw payloads,
link budgets/boot exports, reject bad maps, and mutate synthetic observations
to test the checker. Synthetic snapshots are **checker tests**, not CPC runtime
evidence.

Full `make check` passed in clean detached worktree
`/tmp/geobench-77-check.UktoHN` at implementation commit `894d882`: all **148
Python tests, no skips**, native C checks, ABI/layout and distribution audits.
Toolchain: RASM 3.2.1 and SDCC/SDAS 4.6.2 #16671, with `SDCC` and `SDAS`
explicitly selecting the compiler binaries under `../sdcc/bin`. Log:
`/tmp/geobench-77-make-check.log`. No local `QA/CPC` artifacts were copied in.
The static MSX floppy-distribution audit does not boot a floppy.

The fresh universal ABI Probe, Calculator and Clock builds retain their
reference SHA-256 values:

| APP | Bytes | SHA-256 |
|---|---|---|
| ABI Probe | 2,571 | `a6a696cc0bef9caf69c38b6c44f8d8e50dbb7dd560c88e99feb9595993e0adfc` |
| Calculator | 7,825 | `5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5` |
| Clock | 7,571 | `8d605d045087199769dea40bfdfc50009a2a50bf958ffbcc26e97cdfcdfef2f2` |

The normal MSX2 scheduler was rebuilt: 1,448 bytes, unchanged SHA-256
`70c0e6f9402eae994a6e509a91381d70a85d3217597b7859ffc6be09048f62f9`.
Fresh `tools/test_context_irq_openmsx.sh` runs passed in both Screen 6 and 7,
with private hard-disk fixtures: eight switches/returns, worker/root progress,
maximum snapshot 45 bytes and zero stack faults. Logs:
`/tmp/geobench-77-msx-irq-6.log` and `/tmp/geobench-77-msx-irq-7.log`.
Normal Desktop and MSX distribution media were not rebuilt or changed; the
retained `QA/MSX/GBMSX.IMG` hash remains
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.

### Reproduction

From this checkout:

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-production-1984
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant full-slot
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant bad-guard
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant bad-restore
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --memory 128
```

Build only: `make diagnostic-cpc-production`, inside the toolchain container.
It stages `BOOT.BAS`, `BOOT.BIN`, raw `CORE.BIN` and `DATA.BIN` in
`QA/Diagnostics/CPC-production/normal/CARD` and creates its private
`ADAPTERS.IMG` plus source/section/hash manifest. The runner keeps config,
console log, snapshots, capture and `result.json` in the printed temporary
directory. For another checkout, select the qualified 1984 executable with
`--emulator /absolute/path/to/1984`; no sibling source is modified.

No `make cpc` release target or distribution capability is enabled. Existing
untracked `QA/CPC/` is preserved; checks of retired release targets must run in
a clean worktree, not by deleting those files or weakening the checks. Whole
FAT image hashes can differ with file timestamps; raw payload bytes and their
source fingerprints are the reproducible comparison.

## Remaining 3D-B exit work — before a window

1. Bind the real shared owner/lifetime/focus/damage/defer/FS tables, module/data
   reservations and receiving-side `GB_PARAMS` contracts to this CPC map.
   Link/measure **all** resident and low support sections, not only the current
   scheduler and private probe. Resolve any overflow explicitly; reserved
   space cannot be counted as a completed service or removed to hide overflow.
2. Connect the promoted Mode-1 drawing/pointer leaves with exact clipping,
   line/text/font primitives and canonical block staging. Reuse the same
   public parameter policy; preserve cursor-under-damage and all raster gaps.
   Replay exact pixel oracles with IRQs and M4 in this production layout.
3. Finish root input/event and time adapters plus bounded public storage/FS
   bindings. Measure interrupt-off/ACK and drawing latency under simultaneous
   worker/input activity; the current request-wide DI is not a smoothness pass.
4. Re-measure combined maximum stacks and full code/data budgets; rerun MSX2
   regressions and the CPC restoration/failure suite. Only then advance to
   the first window using the shared lifetime/focus/visibility/damage core.

Issue #77 remains open. No alternate CPC desktop/WM is introduced, no new
universal APP binaries are required, and no PCW, Albireo, second-emulator or
real-hardware qualification is implied by passing M4 on 1984. The
[emulator strategy](CPC-EMULATOR-TEST-STRATEGY.md) still governs additional runners.
