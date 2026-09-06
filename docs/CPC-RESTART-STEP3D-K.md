# Step 3D-K: shared write semantics and M4 free space

Date: 2026-09-06. Issue [#77](https://github.com/salvogendut/GEMBENCH/issues/77),
branch `feature/77-cpc-production-adapters`. Follows the committed/pushed
[3D-I/J context and directory work](CPC-RESTART-STEP3D-J.md) at `39f7dde`.
1984 prerequisite [PR #290](https://github.com/salvogendut/1984/pull/290) is
merged at `bfa0efb`; its issue #289 is closed. The sibling checkout is on main.

Status: **write/free binding implemented and validated as a private M4
checkpoint.** It does not advertise a
public CPC filesystem capability, complete the production composition gate,
or enable a desktop. No MSX source, shared policy, public ABI or universal APP
bytes change in this checkpoint.

## Architecture and contract

`kernel/core/fsctx_policy.inc` still owns validation, owner identity, request
status/actual counts and the context's logical offset. The new
`kernel/kc/cpc_fswrite.inc` supplies only hardware binding hooks. The same
paged module also contains the read and directory bindings from 3D-I/J.

Writes match the existing MSX provider: a zero logical offset replaces the
file; any nonzero logical offset appends at the file's **actual EOF**, not at
that offset. A read followed by a write therefore still appends. This is not
a new seek-and-overwrite API. Zero-length writes create/truncate at offset
zero, or open/close without changing contents in append mode.

The existing fixed `lib/cpc/m4.asm` gate stages 128-byte blocks and owns path/
buffer validation, bank/ROM/IFF restoration, descriptor cleanup and uncertain
open/close poisoning. Only the `CPC_FS_WRITE` composition extends its private
request ABI with op 3: dynamic open/create (`92h`), FSIZE, 32-bit absolute SEEK
to that size, WRITE and CLOSE. It rejects file-size-plus-count overflow. The
ordinary read/replace gate remains available without this extension. Protocol
and append ordering follow the original M4 backend's `m4save.asm`, which is a
read-only reference, not a build dependency.

A <=512-byte shared write uses <=4 native blocks: first replace or append as
required, subsequent blocks append. Selection and path construction never use
the caller's transfer payload as scratch. Every native transaction closes its
descriptor. On success, the shared policy advances the logical offset once by
the requested total. On failure, it reports IOERR and does not advance that
offset or publish a successful count. Already written prefixes are **not
rolled back**; this preserves the existing non-atomic contract. Callers must
not assume a failed append is safe to retry without recovery.

Free-space reporting sends C_FREE through the existing bounded command gate.
It parses CR/LF/space-prefixed ASCII decimal KiB through the `K` suffix and
saturates at 65,535, the shared u16 API limit. Missing/malformed/failed replies
return false to the shared hook, whose existing result is UNSUPPORTED. No
invented capacity value or wrapped counter is returned. Host tests cover zero,
the saturation boundary, huge values, truncation and invalid/failed replies.

## Real M4 qualification

`make diagnostic-cpc-fswrite-1984` builds a private CARD and FAT16 image. The
runner copies that image into a fresh temporary directory before booting 1984;
only that disposable copy is written. No floppy, snapshot boot, RAM injection,
host-backed virtual catalog or distribution image writes are used.

All **45 context checkpoints pass**, covering:

- Two owners with independent paths, filenames and offsets; 512/129/300-byte
  writes interleaved across them, full and short readback, and all payload tails.
- Append after reading only one byte, proving EOF rather than logical-offset
  placement; zero append, zero truncate and creation of an empty file.
- Directory enumeration after writes and truncation, with correct file sizes.
- Oversized writes, wrong-owner/stale handles, missing-directory activation,
  cancel/rewind, cleanup/reuse and an untouched original-file read.
- Free-space before writes and after truncation/empty-file creation. The oracle
  independently counts free FAT16 entries and uses the actual cluster size;
  geometry is test-side observation data, never a guest input.

After completion, `mtype` independently verifies the three output files and
every original staged file. The final free FAT count agrees with allocation of
one nonempty output file and two empty files. Shared worker admission, exact
request/context/transfer snapshots, bank/lock/IFF, code/font/framebuffer, stack
guards, page cleanup and 150-frame final RAM stability are also checked.

| Measurement | Result |
|---|---:|
| Context checkpoints / context-phase M4 commands | 45 / 207 |
| Total M4 commands, including boot/common checks | 1,092 |
| FSCTX module at F7:4400, hard limit 6000 | 4,502 / 7,168 bytes |
| Fixed hardware / resident context adapter | 1,130 / 378 bytes |
| Private high-kernel payload | 15,366 / 16,384 bytes |
| Observed main / IRQ / temporary stack use | 59 / 4 / 6 bytes |
| Final free KiB | 32,626 |

Evidence: `/tmp/geobench-cpc-production-2gjkisgg`; log
`/tmp/geobench-77k-write-final.log`. Input image SHA-256:
`c057bf366146bc21f3a5f11a1da51937a35642a9ec08be375f6a5e26663473c6`.
1984 executable SHA-256:
`3a90e06d108b347c1ef3135735cc69d01ebb53c6fccaf5c2b92a758ad7412d77`.

The `fsctx-write-bad-append` negative composition deliberately replaces on
every block. The real-M4 oracle rejects it at
`fsctx root-read-512: byte 10 got 01 expected 00`. Evidence:
`/tmp/geobench-cpc-production-66uqgn3q`; log `/tmp/geobench-77k-negative.log`.
Four new host tests execute the actual C provider, check repeatable SDCC/RASM
linking/budgets and verify that corruption of readback, offset, file size,
free-space and restoration observations is detected. Host-synthetic observations
test the checker only and never seed emulated RAM.

The previous directory composition still passes all 44 checkpoints, 140 context
commands, 1,005 total commands and final integrity/stability checks with its
unchanged section sizes. Evidence: `/tmp/geobench-cpc-production-byc3fr0h`;
log `/tmp/geobench-77k-directory-regression.log`.
The pre-3D-K directory snapshot also passes against the current linked code and
module, confirming byte-identical disabled-extension code; log
`/tmp/geobench-77k-unchanged.log`.

Full `make check` passes (exit 0), including **198 Python tests without skips**,
native libraries, deterministic universal SDK builds, ABI/package/layout and
distribution checks. Isolated worktree `/tmp/geobench-77k-check.fMBK5w`, log
`/tmp/geobench-77k-check.log`. It contains the current code while excluding the
user's untracked parked CPC tree, without weakening the target/distribution audit.

## Limits and next step

The 3D-I/J namespace, synchronous/IRQ-excluded I/O, read-error ambiguity and
bounded directory replay limits remain. Write permissions, corrupt/full media,
all firmware failure modes and physical M4 hardware are not exhaustively
qualified. The native append overflow guard is implemented, not tested by a
4-GiB runtime fixture. Host failure-prefix tests are not claims of an emulator
disk-full test. Saturation above 65,535 KiB is host-tested, not exercised by the
32-MiB runtime image. Albireo still needs its own backend qualification.

Specific emulator follow-up from source inspection: 1984 `src/fat.c:fat_open`
checks directory/volume attributes in its read branch, but its write/create
branch does not reject those or the read-only bit before truncating an existing
entry. The M4 open-always path also sets `write_mode` after read-open without a
read-only check. This is **source evidence, not a new destructive runtime test**.
Qualify/fix these emulator safeguards separately before advertising public write
parity; the current tests write only their disposable ordinary-file fixtures.

Follow-up resolved on 2026-09-06: [1984 issue #291](https://github.com/salvogendut/1984/issues/291)
and [PR #292](https://github.com/salvogendut/1984/pull/292), merged at `0851004`,
add the FAT/M4 protection checks and rejected-operation media-preservation
regressions. The 1984 native suite passed all 20 tests. This supersedes the
emulator blocker above, not the remaining physical-media/firmware qualifications.
[3D-L](CPC-RESTART-STEP3D-L.md) records the subsequent unified runtime integration.

Next: budget and compose the public filesystem/SDK service bindings with the
shared root loop and module placement, then load the first real shared-core
application window. Passing isolated adapter links does not prove the whole
kernel/GUI fits, remains responsive or matches the MSX desktop.

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-fswrite-1984
```

Build-only: `make diagnostic-cpc-fswrite`. Generated media:
`QA/Diagnostics/CPC-production/fsctx-write/`; the parked `QA/CPC/` is untouched.
