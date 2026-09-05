# CPC foundation: package 3A

Date: 2026-09-05. Issue: [#65](https://github.com/salvogendut/GEMBENCH/issues/65).
Branch: `feature/65-cpc-foundation-probes`, based on `b1e2cd9` (#64).

This is the first hardware package of [restart step 3](CPC-RESTART-PLAN.md),
not a working CPC desktop and not completion of the entire step. It proceeds
independently of the remaining step-2 shared-policy extractions. No MSX2
production source, ABI authority, universal application or release media is
changed. The parked CPC experiment and its local `QA/CPC/` artifacts remain
untouched.

## Boundary being proved

The diagnostic boots a headed binary from an M4 FAT16 image. It makes one
firmware call to set Mode 1, then explicitly takes over: DI, a fixed resident
stack, both ROMs disabled, base RAM configuration and its own IM1 entry. It
does not call firmware again or return to BASIC; reset exits the diagnostic.
There is no implicit assumption that arbitrary firmware calls are safe while
application pages or a private interrupt handler are installed.

The small bank gate is adapted from `lib/bank.asm` at parked CPC revision
`56478578`. The gate-array configuration encoding is retained; invalid maps
are rejected, and the caller owns the interrupt-disabled critical section.
It never unconditionally enables interrupts. Foreground and interrupt code
use the same gate. This is a hardware fixture, not a duplicate owner,
scheduler, compositor or filesystem implementation.

### Diagnostic memory map

Ranges below are inclusive. Symbols in `debug/cpc_foundation/layout.inc` and
the assembled `foundation.sym` are authoritative for the probe; these are
**not allocations promised to the eventual full kernel**.

| CPU addresses | Use and invariant |
|---|---|
| `0000..0037`, `003B..3FFF` | Unallocated by the probe after takeover; no application or module executes here. |
| `0038..003A` | RAM IM1 jump to resident interrupt entry; lower ROM must be off. |
| `4000..7FFF` | Only banked aperture. Base page plus 28 expansion pages on the 512-KiB fixture; never code or stack for this diagnostic. |
| `8000..97FF` | Resident probe reservation. Actual code/tables occupy 619 bytes; remaining bytes are padding, not measured production headroom. |
| `9800..98FF` | Result/state reservation, 73 bytes currently used. Never placed in framebuffer RAM. |
| `9900..99FF` | Padding/unallocated. |
| `9A00..9A0F`, `9B10..9B1F` | Interrupt-stack guards, 16 bytes each. |
| `9A10..9B0F` | 256-byte resident interrupt stack, SP starts at `9B10`. |
| `9B20..9BFF` | Padding/unallocated. |
| `9C00..9C0F`, `9D10..9D1F` | Foreground-stack guards, 16 bytes each. |
| `9C10..9D0F` | 256-byte resident foreground stack, SP starts at `9D10`. |
| `9D20..BFFF` | Not allocated or written by the probe; includes the firmware/ROM workspace reservation. |
| `C000..FFFF` | Screen RAM only, including raster gaps. All 16 KiB checked for unexpected changes. Upper-ROM response overlays are not used after takeover in this package. |

Assembly assertions reject code/state overlap, code in the banked aperture,
overlapping stacks and allocation into the firmware workspace reservation.
The 7,456-byte load image includes initialized state, guard/sentinel bytes and
padding; it is not 7,456 bytes of resident executable code.

### Execution contexts

- **Boot:** BASIC/firmware own their normal memory and interrupts. `MEMORY
  &7FFF` precedes loading the binary at `8000`. Firmware sets the mode before
  switching to the diagnostic's own stack and IM1 handler.
- **Foreground:** both ROMs off; mapping is shadowed and changes only while
  interrupts are disabled. Only `C0` or configurations 4..7 in seven expansion
  groups are accepted. Configurations that can replace vectors, executing
  code or screen RAM are rejected.
- **Interrupt:** the hardware return address is on the fixed foreground
  stack. Entry immediately switches to the fixed interrupt stack and saves
  main/alternate AF, BC, DE, HL and IX/IY. It maps the temporary `F7` service
  page, verifies a byte from that mapping, restores the caller's bank and
  registers, restores SP, then executes EI/RETI. Nested interrupt work is not
  enabled inside the handler.
- **Failure/completion:** DI/HALT in fixed memory, no reboot/firmware fallback.
  The host verifies completion again after another 150 frames.
- **Runtime storage, modules and applications:** deliberately not enabled.
  Their resident/swap/transfer budgets and call boundaries still need to be
  integrated and measured before a complete desktop memory map can be approved.

## Reproduce

From the repository root, with RASM, Python, dosfstools/mtools/util-linux and
the existing `../1984/1984` emulator available:

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-foundation-1984
```

This builds `QA/Diagnostics/CPC-foundation/normal/CARD/{BOOT.BAS,FOUND.BIN}`
and `FOUNDATION.IMG` (32 MiB, FAT16 partition at sector 32). It uses M4, never
a floppy. Each emulator run uses a private image copy and PTY under a unique
`/tmp/geobench-cpc-foundation-*` directory. The directory contains the emulator
log, full RAM snapshots, screenshot and `result.json`. Nonzero exit means a
failed assertion, boot failure or timeout. Generated diagnostics are ignored
by Git and are not added to release media.

For a visible hardware-only run (a static diagnostic pattern, not a desktop):

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-foundation
../1984/1984 --config=QA/Diagnostics/CPC-foundation/normal/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

The automated command, rather than visual inspection of that pattern, checks
the result. `--emulator /path/to/1984` selects another emulator executable.
Image manifests record the exact raw/image hashes and probe source hashes;
FAT file timestamps can differ between builds, so byte-identical image hashes
are not a requirement. The harness records the hash of the image it actually
boots and the emulator executable hash.

Negative runtime checks, each in its own diagnostic variant:

```sh
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant bad-bank
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant bad-register
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant bad-stack
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --memory 128
```

These commands succeed only when the intended failure is detected. They must
not be used as positive-test images. `make cpc` remains intentionally absent.

## Validation and limits

The positive probe seeds all bytes in 29 distinct pages with address- and
page-dependent patterns. Each of 50 rounds checks every 256-byte block and
page tail, forces a real interrupt on each mapped page, checks all saved
registers/flags and rechecks the hardware mapping after return. The final
host check compares **every byte of all 464 KiB** against its expected page
pattern, plus all 16 KiB of framebuffer RAM and the resident code. A PASS flag,
changed screenshot or moved coordinate alone cannot satisfy the checker.

Observed in 1984 on the 512-KiB CPC 6128 fixture:

- 50 rounds, 1,450 page checks and 1,450 interrupts; 50 IRQs on every page.
- All physical-page bytes, framebuffer bytes, resident code, registers and
  stack guards preserved. Final bank is C0, both ROMs off, Mode 1, IM1, IFF off.
- Sentinel-observed stack use: foreground **4/256 bytes**, interrupt
  **24/256 bytes**. These are this fixture's measurements (sentinel scans are
  lower bounds), not a full scheduler/application stack budget.
- Deliberate bad bank restoration, register corruption and stack-guard damage
  are rejected with codes 2, 3 and 7 respectively. A 128-KiB machine fails the
  page-content check with code 1 instead of being accepted as 512 KiB.
- Six host unittest methods cover headers, unsafe-map assembly rejection,
  fault builds, snapshot parsing and checker mutations. Synthetic snapshots
  test the host checker only; they are not counted as emulator execution.
- Full `make check` passes from clean worktree
  `/tmp/geobench-cpc-foundation-check.Ty8gzl` at `dbdf58f`: 67 discovered Python
  tests plus existing C, assembly, universal SDK/ABI, asset and media checks.
  Log: `make-check.log` in that worktree. The command used `my-distrobox` with
  `SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc` and
  `SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80` to avoid relative tool-path
  assumptions in `/tmp`. The clean tree avoids the previously documented
  retired-target check conflict with leftover, untracked `QA/CPC/` artifacts;
  neither that check nor the parked artifacts were modified. No fresh MSX2
  emulator run was necessary or performed: production code/media are unchanged.

No real-CPC test, new emulator fix, runtime file-save proof, clipping/pointer
proof, desktop stability claim or input-latency result is implied. The current
1984 executable is SHA-256
`0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`.

Final positive-run artifacts are retained locally at
`/tmp/geobench-cpc-foundation-ka2z8pqz/`. Its raw probe SHA-256 is
`5ccdaf35f5142ac2d4a51648f6a99b6df0f14766f2d0cba256c586194105ada0`;
the booted M4 image is
`3e32aafbbbc32b47750422f8e7c1c81d3d9d8fec184d5db190918ac5dae75663`.
Negative-run logs/results are under the same `/tmp/geobench-cpc-foundation-`
prefix with suffixes `rfodawom` (bank), `d9tgmbeq` (register), `3itav8xg`
(stack) and `pcprrzkx` (128 KiB). These are disposable local evidence, not
repository dependencies. Re-run the commands above to regenerate evidence.

## Remaining step-3 gates

**3B — graphics and portable parameters.** Test the canonical four-pixel
column geometry through audited CPC primitives with exact clipping and
save-under checks over changing backgrounds. Keep display pixels separate
from command state. The existing universal SDK's `C030`, `C039`, `C1EC` and
`C3CA` mailboxes still conflict with CPC screen RAM; this package does not
change or pretend to support them.

The candidate to validate is a caller-owned parameter block passed by pointer,
with explicit length/range checks and copy-in before any application-page
switch (copy-out only after restoring the caller). Deferred operations must
own a copy, never retain a transient pointer. This avoids requiring a common
fixed mailbox address across machines. It remains a proposal until the
experimental ABI authority, SDK, MSX2 implementation and universal artifacts
are updated and tested together. The frozen GEMBENCH-1 ABI is not changed.

**3C — runtime M4 boundary.** Use bounded resident staging, explicit ROM/mode
and bank restoration, and caller-owned interrupt state for every success and
failure return. Verify load/save bytes on the host, short/failed reads and
invalid requests, plus all memory guards. M4 boot success in 3A does not prove
this runtime boundary. Floppy and Albireo are later backend gates.

Only after these gates and the remaining step-2 shared-policy extractions may
step 4 integrate windows, focus, damage, scheduling and application teardown.
