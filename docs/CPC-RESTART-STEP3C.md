# CPC foundation: bounded runtime M4 storage

Date: 2026-09-05. Issue [#68](https://github.com/salvogendut/GEMBENCH/issues/68).
Branch `feature/68-cpc-m4-runtime`, stacked on #67 at `ef6a391`.

This completes the isolated M4 runtime proof in restart package **3C**. It is
not a CPC desktop, a public filesystem ABI, or completion of shared-core
integration. MSX2 production code, ABI authority, applications and release
media are unchanged. The user's parked `QA/CPC/` is untouched.

## Reuse and boundary

`debug/cpc_foundation/storage_driver.asm` adapts the packet/response convention
from `lib/fs_m4.asm` and `kernel/modules/m4save.asm` at archived CPC revision
`56478578`. The audit also used local M4ROM `a8a0291` (`send_command`, `char_in`,
`fwrite`, command constants) and 1984's `src/m4.c`. Those sibling sources are
references, not new build dependencies. Local `M4ROM.s` SHA-256:
`347694dc0dc4cbe0d7ce37ae70b594e47b84afd3ebe20ff5d80064c98748123d`.

The adapter keeps the sized `FE00` command stream and `FC00` acknowledgement,
dynamic file descriptors, absolute-path open, 32-bit seek, raw `READ2`, write
and close. It does not reuse implicit firmware calls, unconditional EI,
hard-coded restoration to AMSDOS, or framebuffer-backed command storage.
Short reads use the validated actual count; M4ROM's EOF literal is decimal
20 (`0x14`), not hexadecimal `0x20` as some archived comments suggested.

Boot uses BASIC and one firmware mode-set before explicit takeover, as in 3A.
The fixture installs a fixed-stack IM1 handler and explicitly disables M4 NMI
with `C_NMIOFF`. Subsequent requests execute entirely in RAM without firmware.
Reset exits the probe; it does not return to BASIC.

## Private request contract

HL points to a 16-byte version-1 record, BC must equal 16. All nonempty caller
spans lie wholly in the currently mapped primary page, `[0x4000,0x7F00)`.
This is a hardware-test interface, not another `GB_*` entry or a second owner/
filesystem-context policy implementation.

| Offset | Field |
|---:|---|
| 0 | Operation: 1 read-at, 2 replace/create a bounded file |
| 1 | Record version, 1 |
| 2..3 | Absolute path pointer |
| 4 | Path length including final NUL, 3..64 bytes |
| 5 | Reserved, zero |
| 6..7 | Caller buffer pointer |
| 8..9 | Count/capacity, 0..128 bytes |
| 10..13 | 32-bit absolute read offset; zero for replace |
| 14..15 | Reserved, zero |

Path validation rejects embedded NUL, control/space, non-ASCII and backslash
bytes and requires a leading slash and final NUL. It is not a path-permission,
directory-context or sandbox policy. Those belong to the shared upper layer.
Offset plus requested count must not wrap. Empty reads validate the record/
path but do no I/O; empty replace creates/truncates and closes an empty file.
Empty transfers never inspect the buffer pointer or execute a zero-count LDIR.

The complete record, path and write payload are copied into bounded fixed RAM
before the fixture maps an unrelated poisoned F7 service page. Responses are
read through upper-ROM slot 6, with a bounded header-first copy. Echo, frame
length, command status and actual count are validated before data is accepted.
Read output is published only after a successful close and restoration of the
caller page. No caller pointer is retained for deferred use.

Return A: 0 OK, 1 short/EOF, 2 bad argument, 3 I/O failure, 4 malformed response,
5 busy, 6 unsupported entry context, 7 offline. DE is the actual byte count on
OK/EOF and zero on failure. Other registers/flags are volatile. The gate
preserves the caller's fixed SP, bank, upper-ROM selection, gate-array video/
ROM configuration and interrupt-enable state, including rejection returns.
Supported entry contexts have lower ROM disabled, Mode 0..2 and truthful
hardware shadows; upper ROM may be on or off. These fixture mode checks do not
broaden the production CPC four-color profile.

Opened handles are closed after success and after seek/read/write errors.
An uncertain open response leaves the handle unknown; a failed close leaves
cleanup uncertain. Both poison the adapter, and later requests return offline
without sending further commands. Recovery/reset is deliberately not faked by
clearing the flag. Busy rejections do not overwrite an in-flight transaction.

Writes are **not atomic**: opening replace may already truncate, and a command
may write bytes before reporting failure. No automatic retries, rollback,
durability guarantee or false success is provided. Higher-level safe-save and
large-file/streaming lifecycles remain shared-service integration work. The
128-byte limit bounds this proof's transfer, not the eventual public file size.

## Memory budget and timing limits

Addresses below are exclusive-end ranges in this diagnostic, not promised
allocations in the future production kernel. The common layout assertions
retain the fixed stacks and firmware workspace reservation.

| Region | Use |
|---|---|
| `0038..003B` | RAM IM1 jump; no ROM IRQ routine |
| `1000..1010`, `39B0..39C0` | Normal run's trace guards |
| `1010..39B0` | 74 returned-buffer/control records, 144 bytes each |
| `4000..7F00` | Caller record/path/buffers on C0, C4 or C5 |
| `7F00..8000` | Caller-page sentinel, never accepted as a buffer |
| `8000..940A` | Probe, adapter, vectors and constants, 5,130 bytes |
| `9800..9866` | Control state, request record and guards, 102 bytes |
| `9A10..9B10`, `9C10..9D10` | 256-byte IRQ and foreground stacks, each guarded |
| `9D40..9D80` | Copied path, 64 bytes |
| `9DA0..9E20` | Transfer staging, 128 bytes |
| `9E40..9EC8` | Response staging, 136 bytes |
| `9EE8..9F6C` | Command packet, 132 bytes |
| `A000..C000` | Not allocated/written by the probe; firmware workspace reserved |
| `C000..10000` | Display RAM only, including raster gaps |

Each buffer has its own 16-byte guard pair. Terminal-error variants have 76
trace rows and 5,210 code/vector bytes; assertions enforce their larger bounds.
The raw load image is 8,060 bytes ending at `9F7C`, including guards, stacks,
initial state and padding. The adapter itself is **891 bytes**, including
diagnostic hook calls but excluding their implementation and fixture code.
This is not a production resident-budget estimate.

All command sends and memory copies have finite software bounds; there is no
read-until-EOF loop or retry loop. However, M4's acknowledgement can hold the
Z80 bus until SD I/O completes. **Z80 software cannot time out that OUT while
the bus is held.** Requests currently serialize with DI throughout; this
proves restoration, not acceptable desktop input latency. Hardware timing,
IRQ-off duration, recovery and scheduling integration remain separate gates.
The run's host elapsed time includes bank seeding, emulation and observation
and must not be presented as an M4 throughput benchmark.

## Reproduce

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-storage-1984
```

The existing builder generates
`QA/Diagnostics/CPC-foundation/storage/CARD` and a fresh 32-MiB FAT16 M4 image
at sector 32. The harness boots only a private copy under a unique
`/tmp/geobench-cpc-foundation-*` directory through `../1984/1984`, CPC 6128,
512 KiB and M4. No floppy, mounted release card or parked CPC image is used.
It retains the booted/modified image, emulator log, RAM snapshots, screenshot
and `result.json`. The generated image is disposable: the probe intentionally
creates/truncates `OUTPUT.BIN`, `ZERO.BIN`, `FAULT.BIN` and `BADFD.BIN` there.

Additional failure checks:

```sh
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant storage-close-error
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant storage-open-error
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant storage-bad-bank
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant storage-bad-rom
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant storage-bad-copy
distrobox enter my-distrobox -- python3 -m unittest discover -s tests -p test_cpc_storage.py -v
```

The three `bad-*` commands succeed only when the deliberately broken adapter
is rejected. They are not usable positive-test images. The terminal open/
close cases instead verify a controlled failure and the following offline
rejection. `make cpc` remains absent; this is not an application demo.

## Recorded validation

RASM 3.2.1, container Python 3.14, local 1984 executable SHA-256
`0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`.
No sibling emulator source was modified. No physical-CPC or second-emulator
result is claimed.

- Normal run: **592 requests / 913 commands over eight rounds**, 700 observed
  interrupts, 74 full 128-byte returned-buffer checkpoints. Every round checks
  status/count, command count, bank, IFF, SP, ROM shadows and eight CPU-visible
  ROM/RAM bytes. Four rounds enter with DI and four with EI. The exact IRQ
  count varies with timing.
- Host checks compare every retained checkpoint, all three final caller pages,
  every unused expansion page (including F7), all 16 KiB of display RAM,
  resident code and every guard. Final RAM is unchanged after another 150
  frames. Checkpoints retain the last round, not every instruction/frame of
  all rounds. Caller-page boundary bytes are also recorded after every call.
- Host M4 file extraction verifies the complete source, output, truncated/
  restored payload, zero-length files and raw header behavior. Repeated open/
  close cycles reuse the finite descriptor pool. `INPUT.BIN` stays unchanged.
- Exact-capacity, exact-end, partial and empty reads; zero-length create;
  missing file/parent; invalid spans, lengths, schema, offset and entry mode;
  busy rejection; and recovery after a failed operation all pass.
- Invalid-fd commands elicit real M4 read/write error replies, then close the
  retained valid handle. Other fault hooks alter copied response headers/data:
  wrong echoes, oversized/truncated/empty frames, oversized actual counts and
  error status. These simulate transport/device faults, not physical media
  removal or a full SD card. Failed reads leave destination bytes untouched.
- The reported-write-error fixture leaves the payload on disk; the real bad-fd
  write leaves a newly truncated empty file. Both return failure, explicitly
  demonstrating why a failed write must not be treated as an atomic rollback.
- Uncertain-close/open runs each pass 76 requests, with 119/116 commands and a
  final offline state. These one-round terminal tests enter with DI; ordinary
  operation/rejection paths are separately exercised in both interrupt states.
- Bad bank restoration, upper-ROM restoration and copy-after-bank-switch are
  rejected with fixture failures 9, 12 and 8 respectively.
- Sentinel-observed stack use is **20/256 foreground bytes and 4/256 IRQ
  bytes** (terminal DI-only runs use no IRQ stack). These are fixture lower-
  bound observations, not worst-case scheduler/application budgets.
- Six new host unittest methods pass, including deterministic fault assembly,
  rejected memory maps and checker mutations. Synthetic snapshots test the
  checker; they are not counted as Z80 execution.
- Existing 3A and 3B probes pass again: 1,450 bank/IRQ checks and 2,450 graphics
  requests respectively. Their raw binaries retain the hashes recorded in
  their original package documents.
- Full `make check` passes at implementation commit `7f7da9d` in clean worktree
  `/tmp/geobench-68-check.qxJOBC`: **82 discovered Python tests**, plus the
  existing C, assembly, SDK determinism/layout, ABI, asset and media checks.
  Log: `/tmp/geobench-68-make-check.log`. It used `my-distrobox` with explicit
  `SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc` and
  `SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80`. The clean tree avoids the
  known retired-target assertion conflict with the user's untracked `QA/CPC/`;
  neither that assertion nor the parked directory was changed.

Normal artifacts: `/tmp/geobench-cpc-foundation-xgyg6hbn/`. Raw probe SHA-256:
`315ecacce00e1437f127c3e6538b5676ce39421517cb96585cfd629e37a36f52`.
Booted image:
`78c32794dce8f9a0241122dbc03905738dd562608765b63c02a9ed53b74e5ee9`.
Image after writes:
`921e04d8ee046c494b12cf783534cdf6ea5df3434b4ebb6139d4ee4921e8c43a`.
Output payload:
`0aedd4856f8eba0963627336ad5144a9a7dbe12498e6066f0165fc97d8ddee4c`.

Final terminal/fault artifact suffixes under the same temporary-directory
prefix are `cg1q5qie` (close), `vzikfgmg` (open), `1xdlstm9` (bank),
`x2zjgjhd` (ROM) and `025wcxgd` (copy). Rechecks are `b2lbhgfs` (3A) and
`fvoz956_` (3B). These are disposable local evidence, not dependencies.

The production MSX2 disk image still has SHA-256
`a0c6fb4c1cf0dc4e2d0e1f9fb29356c981c022ab4202f12cf7f4077d9cc6ae0b`.
No fresh MSX2 emulator run is needed for this diagnostic-only change.

## Next gate

Return to **step 2's shared-core extraction**: window attachment/validation and
full application lifetime through the existing state provider, with MSX2
baseline/regression evidence, before compositor changes. Shared visibility,
damage, scheduling, deferred/timer and filesystem/service state still need
their bounded extraction packages. This is the route to one policy
implementation on MSX2 and CPC; do not revive the broken CPC desktop wholesale.

The isolated 3A/3B/3C proofs are not a complete production CPC memory map or
desktop. Full input/line/text adapters, measured runtime budgets/latency and
shared integration remain; floppy, Albireo and PCW are later backend gates.
