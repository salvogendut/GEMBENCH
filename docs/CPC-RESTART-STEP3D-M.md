# Restart step 3D-M: caller-owned portable filesystem client

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`. Follows
[3D-L unified runtime](CPC-RESTART-STEP3D-L.md).

Status: **portable client boundary implemented and tested on CPC/M4 and MSX2
Screen 6/7**. Desktop/File Manager and Desk/menu integration are still pending.
This does not close the complete production adapter gate or claim PCW support.

Follow-up: [3D-N](CPC-RESTART-STEP3D-N.md) connects the shared Desktop bar and
application-menu publication. Full Desk/accessory and shell integration remain open.

## Design and implementation

The shared filesystem context policy already runs on both targets. Its native
client's fixed MSX `C3D0`/`C400` buffers, however, collide with CPC pixels. The
solution is a caller-owned transport, not another filesystem implementation or
a framebuffer save/restore workaround.

`GB_PARAMS` gains optional operation 8, behind the previously unadvertised
`portable-filesystem` capability. ABI 2.1 and all jump-table addresses stay
unchanged. The old native `GB_FSCTX` calls and buffers remain unchanged on MSX2.
The machine-readable layout is in `abi/geobench-v2.json`; see the
[universal ABI](UNIVERSAL-APPLICATION-ABI.md#portable-filesystem-binding-optional-abi-21-service).

The 16-byte parameter descriptor names a caller-primary 32-byte filesystem
header and a caller-primary 512-byte transfer buffer. The receiver rejects
invalid spans, lengths, overlapping header/transfer buffers, unsupported native
operation numbers, workers and unmapped owners before copying into native state.
It stages inputs, calls the existing owner-aware context gate, restores the
caller page, then copies results back. No pointer is retained after return.
Transport errors and filesystem status remain separate.

`kernel/core/parameters_fs.asm` is shared. Only the native buffer addresses and
gate entry differ between the CPC and MSX providers. Both retain the existing
context policy/module: generation-safe handles, implicit owner identity,
independent directory/path/name/offset state, owner cleanup and launch handoff.

`UNIVERSAL_FS=1` links the existing `gbfsctx.c` client policy with
`gbfsctx_universal.c` instead of the native trampoline. `gbfsctx.h` selects
application-owned header/transfer storage; all public functions and the batch
accessor remain the same. The build requires `portable-filesystem` in the
manifest, so an older kernel rejects the APP before entering it. This client
is root-callback-only and non-reentrant; workers must not enter its wrappers.
It costs 544 bytes per application plus the existing parameter bridge, which
must be included in future Desktop/File Manager data budgets.

CPC advertises the new high-word capability and context capacities but keeps
the old native filesystem-context capability off: its inherited `GB_FSCTX`
slot and target-era file calls are not portable bindings. MSX2 supports both
the new operation and the old native calls. Package resources, CPC background
timers and other unfinished services remain gated as before.

## Measured size and stack results

| Section | Before (3D-L) | Now | Budget |
|---|---:|---:|---:|
| CPC low support | 1,673 | 1,832 | 3,072 |
| CPC resident kernel, including launcher | 10,949 | 10,984 | 16,384 |
| CPC shared FS module in F7 | 4,502 | 4,502 | 7,168 |
| CPC scheduler | 1,437 | 1,437 | 1,536 |
| CPC hardware leaves | 1,130 | 1,130 | 1,536 |
| MSX2 GBAPV4 module | 2,079 | 2,238 | 2,816 before the legacy sysinfo view |

The resident-kernel increase is the launcher's F5 control. Context policy and
native storage code are unchanged. The MSX exact loader byte count is updated
and checked at assembly. Screen 6/7 kernel builds remain within their guards.

CPC observed main/IRQ/temporary stack usage is **127/4/0 bytes**, with all six
16-byte guard sides intact. The main stack is 256 bytes. Temporary context-copy
stack usage remains unqualified by this root-only APP test, not proved by zero.
The probe's data ends at `76AE`, below the `7F00` task reservation.

## Runtime evidence

One `FSPROBE.APP`, 5,061 bytes, is copied unchanged to all three tested setups:

`d17ea5eb23c1b2de66c8f1627dbf56980fe653b8ebf2786adf8b2646f7b35d5d`.

Its 46 assertions cover nine malformed boundary requests, independent contexts
and paths, interleaved 128/512-byte reads, a short final read and EOF, rewind,
directory first/next/batch and packed attributes, free space, replacement and
append, multi-chunk readback, zero-byte truncation, capacity exhaustion,
stale-handle rejection and complete close cleanup. The probe writes only
`UFSTEST/RESULT.BIN` on disposable generated media. Host-side `mtype` verifies
the final exact bytes `DONE` independently of the APP result.

- CPC uses real firmware/M4 boot and the launcher's F5 command. Runtime checks
  require three live windows and focus on the filesystem probe, intact code,
  font/module and stack guards, no leaked filesystem contexts, and exact
  framebuffer restoration after closing the probe over ABI Probe. Evidence:
  `/tmp/geobench-cpc-runtime-9wejulgd`; log `/tmp/geobench-77m-fs-cpc-final.log`.
- MSX2 uses the actual Desktop Desk menu, with the probe copied to a private
  `CLOCK.APP` test alias. This exercises the normal owner/application launch
  path without injecting a launch, executable bytes or test state. Read-only
  entry/return hooks check SP, IFF, mapped page, mapper port, scheduler lock,
  the `7F00` task guard and all 128 KiB of VRAM for **each of 46 parameter calls**.
  Both Screen 6 and 7 pass. Logs: `/tmp/geobench-77m-fs-msx6.log` and
  `/tmp/geobench-77m-fs-msx7-final.log`. Artifact directories under `build/msx/`:
  `portable-fs-6-achcliy4` and `portable-fs-7-pq30pbg9`.

1984 executable SHA-256:
`00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`
(main includes FAT/M4 protection PR #292). Toolchain: RASM 3.2.1 and
SDCC/SDAS 4.6.2 under `../sdcc/bin`, in `my-distrobox`.
The CPC runtime image and CARD are rebuilt under `QA/Diagnostics/CPC-runtime`.
No floppy runtime tests, RAM injection, physical hardware or Albireo are involved.
Release `QA/MSX` media and the user's parked `QA/CPC/` are not modified.

The ordinary CPC window regression also passes all 11 checkpoints against this
final image: `/tmp/geobench-77m-windows-final.log`. Existing ABI Probe, Clock and
Calculator hashes remain unchanged. Three new host tests check the shared
binding/authority, native-buffer exclusion in the universal client, target C
layout, deterministic APP builds and rejection of a filesystem client manifest
lacking the required capability.

Full `make check` passes: **204 Python tests without skips**, native library
checks, deterministic universal SDK builds, ABI/layout and distribution audits.
Isolated worktree: `/tmp/geobench-77m-check.UAp0HF`; log:
`/tmp/geobench-77m-check.log`. The parked `QA/CPC` tree was not copied into the
worktree, and the MSX2-only distribution audit was not weakened.

## Try it

The current image is already built:

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Press **F5**. A `Portable FS` window should show `FILESYSTEM PASS`. Escape
closes it, revealing ABI Probe without leftover pixels. F3 opens another ABI
Probe; arrows and Space remain the keyboard pointer controls. F5 can be repeated
on the same generated card; its diagnostic file is replaced, never a user document.

Build and automated checks:

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-portablefs-1984

distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-portablefs-openmsx
```

The MSX test requires the existing staged MSX distribution and build assets.
It rebuilds the changed kernel/module into private hard-disk test media rather
than replacing the release card. Build-only CPC target remains
`diagnostic-cpc-runtime`; ordinary window regression is
`diagnostic-cpc-runtime-1984`.

## Remaining work

Next: integrate the actual shared Desktop/File Manager and Desk/menu behavior,
starting with their native service dependencies and application data budget.
Do not replace them with a CPC-only launcher/menu implementation. The portable
FS client makes the filesystem side possible but does not provide icons,
themed chrome, shell/service registry, document helpers or package resources.
These must be bound/measured before claiming the full Desktop is usable.

The previous M4 namespace, bounded directory replay, synchronous IRQ-excluded
storage and backend error-reporting limits remain. This runtime APP does not
cover physical/corrupt/full/read-only media, worker entry, cross-owner forgery
or launch handoff through the new boundary. Existing shared-policy tests cover
several of those mechanisms separately, not as new end-to-end APP evidence.
Desktop integration and Clock/Calculator worker/timer parity remain open.
