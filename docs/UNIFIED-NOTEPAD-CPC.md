# Unified Notepad — CPC receiver binding

2026-09-13, issue #84, `feature/84-unified-notepad`.

The MSX arrow-navigation / incremental-repaint fixes were accepted by the
user and committed/pushed as **`6e6fe05`**. This work brings the **same APP**
to CPC; it is not a separate CPC editor or a replacement desktop port.
The accepted normal CPC distribution remains unchanged.

## Current checkpoint: private desktop two-bank receiver

The shared package loader and sealed secondary-call policy now run in the
**full private CPC Desktop/File Manager/Settings composition**. The transport
foundation was committed/pushed as `fd04dd1`; this follow-up remains on #84.
It does not yet make Notepad runnable on CPC: filesystem identity/handoff and
focused text input still need receiver bindings. No APP source was changed.

- `PORTABLE_PACKAGE_STREAM=1` binds the existing shared launch transaction,
  dual admission, package stream, generation seals and secondary calls to
  CPC's real owner/page tables and bank leaf. CRC/descriptor validation and
  successful CLOSE precede seal publication and execution. Owner/page release
  use the existing shared cleanup hooks.
- Classification consumes one 256-byte prefix, then hands the **same open
  descriptor and cached prefix** to the shared transaction. Native/root/module
  reads use the same bounded sequential reader without package admission.
  Native File Manager/Settings retain their build-matched admission checks.
- After the low M4 bootstrap has jumped to high code, the receiver loads
  `GBENCH/GBPKLOAD.MOD` into `0100..0400`. Exact length, EOF, successful CLOSE
  and a build-bound CRC32 must pass before readiness, capabilities or the
  desktop are published. CRC is a build-integrity check, not authentication.
  A missing, short, appended or corrupt module stops boot without executing it.
- The 510-byte transport is split between SUPPORT (open/close) and HARDWARE
  (read/context handling), without changing the original contiguous diagnostic
  bytes. Fixed state occupies `1F00..1F80`; the locked 512-byte transfer uses
  `1500..1700`. No app bank, framebuffer, stack or live native-edit state is
  borrowed. Fixed IRQ timekeeping continues while the root lock excludes app
  callbacks and other storage users.
- Only this explicit private profile advertises secondary calls (`05DF` high
  capability word). Default remains `01DF`, filesystem API remains **v1**,
  and the unqualified portable-data-page combination is rejected at build time.

Measured full composition, including real native modules:

| Region | Used / reserved | Remaining |
| --- | ---: | ---: |
| High kernel `8000..C000` | 16366 / 16384 | 18 bytes |
| Support `0400..1000` | 3035 / 3072 | 37 bytes |
| Hardware `3800..3E00` | 1483 / 1536 | 53 bytes |
| Scheduler `2900..2F00` | 1452 / 1536 | 84 bytes |
| Checked package module `0100..0400` | 757 code/header, 768 loaded / 768 | 11 padding bytes |
| F7 filesystem module `4400..5E00` | 4583 / 6656 | 2073 bytes |
| Firmware-loaded bootstrap `8000..9A00` | 6312 / 6656 | 344 bytes |

The next bindings must respect these separate address domains. In particular,
18 kernel bytes is **not** enough for the remaining input/handoff work without
measured code savings or reviewed placement inside existing allocations.
Do not enlarge memory limits or shrink Notepad to solve this.

Qualification uses actual 512-KiB CPC/M4 in unmodified `../1984/1984`:

- The existing universal computation APP passes **54 checks / 17 successful
  copied secondary calls per launch**, for three launch/close cycles through
  the real Desktop menu. Owner `(2,1)`, `(2,2)`, `(2,3)` identities, exact primary
  and secondary code bytes, seals, page purpose, reclaimed pages/owners, fixed
  code, stack guards and an unchanged disk are checked. Its 11206-byte APP SHA
  is `ab6e6eef5bea73ff474d3357e69da4b549e2235429eb917478963f82cf1cc0f4`.
- Missing/short/appended/corrupt loader-module cases all stop before root-owner
  or window publication, with closed transport and stable halted state.
- CRC-corrupt, truncated and appended APPs, plus a valid APP returning without
  registering a window, each pass three attempted launches with owner/page/seal
  rollback and no stale transport state.
- The final private image passes **32 desktop stacking checkpoints**, including
  Clock seconds, partial/complete occlusion, pointer save-under, Calculator
  input/drag/close and File Manager edge/resize/cleanup. Settings passes **21
  normal + 9 cold-reboot checkpoints**, six appearance choices, cancellation,
  close/reopen, exact config readback and 46 unchanged expected file payloads.
  Maximum observed main stack is 209 bytes (IRQ 4, temporary 6 in stacking);
  all guards remain intact. The test runner preserves the private profile for
  its automatic Settings reboot; it must never select the normal image there.
- **22 host/Z80 tests pass**, including the original 6,058 transport calls,
  shared stream/sealed-call policy, storage, native loading and complete
  default/private assembly budgets. Baseline CORE, SUPPORT, HARDWARE, SCHED,
  BOOT and LOADER binaries are byte-identical to `fd04dd1` with the private
  receiver disabled.

Evidence under `build/notepad-84/evidence/`:

| Case | Directory or log |
| --- | --- |
| Computation / three generations | `cpc-receiver-normal-2h68i6xu` |
| Bad APP CRC / short / extra / no registration | `geobench-cpc-runtime-eof8sjjd`, `-naxlejlh`, `-ztgnq_zp`, `-ayb2t4s_` |
| Missing / short / extra / corrupt module | `geobench-cpc-runtime-1j509ed_`, `-_3wu4v75`, `-4y7oa0yd`, `-f4xlktwb` |
| Final desktop stacking | `cpc-receiver-stacking-kealzdni` |
| Settings save / cold reboot | `cpc-receiver-settings-kctitpa1`, `geobench-cpc-runtime-j0s8hv60` |
| Host/Z80 regressions | `cpc-receiver-regressions.log` |
| Default binary comparison | `cpc-receiver-default-before`, `cpc-receiver-default-after` |

Abbreviated `-suffix` entries retain the `geobench-cpc-runtime` prefix.
The first normal Settings process passed its guest checks but initially failed
to select the private profile for its automatic reboot. The harness was fixed;
the explicit cold-reboot run uses that exact saved Settings image and passes.
These are private receiver checks, not complete storage-fault or v1.0 acceptance.

Private build and qualification commands (compiler/tools available via
`my-distrobox`; the emulator runs on the host):

```sh
python3 tools/build_cpc_runtime.py --notepad-receiver
python3 tools/test_cpc_runtime_1984.py --skip-build \
  --private-media build/notepad-84/cpc-receiver --package-case normal
```

Use the same test command with `crc`, `short`, `extra`, `no-register`, or
`module-missing`, `module-short`, `module-extra`, `module-corrupt` as the case.
Baseline desktop checks replace `--package-case normal` with
`--filemgr-scenario stacking` or `--settings-case normal`. The computation
fixture replaces CALC.APP only on each **disposable test image**, not in the
private source media or normal distribution. This is not a manual Notepad
image. No normal `make cpc` build or manual saved-document image is replaced.

## Previous checkpoint: sequential M4 transport qualified

`lib/cpc/m4_stream.asm` adds a private single-open reader for the shared
package transaction. It reuses the existing `m4.asm` bounded command/response
transport. Unlike the old CPC app reader, it does not reopen and seek for
every 128 bytes. It performs one dynamic OPEN, sequential READ2 commands and
one CLOSE. A caller's 0–512-byte read is divided into at most four wire reads.

The caller must hold the root scheduler lock for the whole descriptor
lifetime. Each entry preserves the incoming IFF and GA/ROM configuration;
the adapter never switches application banks. The ordinary filesystem gate
is excluded by `io_busy`. Uncertain OPEN/CLOSE replies poison the backend,
without guessing a descriptor or retrying a close. Every failure returns
zero usable bytes; the package loader must discard any partially filled
private buffer and must not publish executable pages before validation and
successful close. No new public filesystem operation or capability is added.

The adapter is **510 code bytes + 11 fixed state bytes**, plus the existing
M4 scratch and a caller-provided fixed 512-byte transfer buffer. It is not
linked into normal CPC delivery builds. The standalone probe addresses are
test bindings; the subsequent full private receiver placement is recorded above.

Evidence:

- `tests/test_cpc_stream_adapter.py`: **6,058 executed Z80 calls**, all counts
  0–512, repeated reads, short/EOF, malformed response lengths/counts/IDs,
  I/O errors, uncertain open/close, nesting, ordinary-gate exclusion, invalid
  context/path/buffer and preserved bank/ROM/IFF/index registers. The device
  model rejects SEEK, writes and guessed closes. Observer-negative tests
  separately reject changed code, segment bytes/tails, guards and context.
- Longest modeled adapter call: **28,587 CPU cycles, 12 stack bytes**. This
  excludes physical M4 bus-hold time and CPC contention; it is not a measured
  desktop latency claim. The caller can service fixed IRQs between reads.
- `tools/test_cpc_stream_1984.py`: actual 512-KiB CPC/M4 in the unmodified
  `../1984/1984`, SHA256
  `b99c482451e67b2a2876487af7021c0ad78a57c5e1778f6c217ab5956df7616a`.
  The accepted **20209-byte** APP is copied to real C4/C5 banks: **14443-byte
  primary + 5766-byte secondary**, with exact-byte and untouched-tail checks.
  One OPEN, **160 READ2**, one CLOSE; real fixed-time IRQs advance. Code,
  stack guards, bank/ROM state, framebuffer and M4 image remain intact.
  Truncation, appended data and missing-file cases also pass cleanup checks.
- Private evidence under `build/notepad-84/evidence/`:
  `cpc-stream-normal-8ruga5sx`, `cpc-stream-short-49xj80tj`,
  `cpc-stream-extra-f4dqs0d3`, `cpc-stream-missing-_x42ljc0`.
  Each has `build.json`, M4 image, emulator log, two snapshots and
  `result.json`. Earlier normal run `cpc-stream-normal-4tj3ych0` is retained.
- All **14 focused tests** pass: the two new transport/observer tests, six
  existing CPC storage tests, and shared package/sealed-call regressions at
  both fixed layouts. No default transport, runtime, application, emulator
  or firmware source was modified.

The hardware probe deliberately **does not execute the APP**, perform GBAP
admission, seal a secondary page, or present a desktop. A transport PASS is
not a runnable-Notepad or full CPC receiver acceptance claim.

## Remaining receiver work

1. **Document and input bindings.** Enable the existing shared filesystem
   identity / owner-bound launch-handoff policy in CPC's paged FS module and
   File Manager. Port focused `GB_WK_TEXT_INPUT` routing using CPC keyboard
   capture, preserving Ctrl+arrows/Space pointer access. Native/default
   windows must retain their existing input behavior. No editor-side fork.
2. **Identical APP acceptance in a private desktop M4 image.** Open/edit/save,
   arrows/Space/backspace, bounded repaint, exact-path document launch,
   focus/occlusion, dirty close, 4096-byte round trip, 4097-byte rejection and
   repeated cleanup. Only then supply a manual CPC editor image. Normal
   delivery promotion is separate; M4/Albireo tests only, never floppy tests.

## Baseline placement investigation (before receiver binding)

Measured from the accepted `QA/CPC-Desktop/manifest.json`, not a smaller
diagnostic build:

| Resident region | Used / reserved | Remaining |
| --- | ---: | ---: |
| High kernel `8000..C000` | 15821 / 16384 | 563 bytes |
| Support `0400..1000` | 1836 / 3072 | 1236 bytes |
| Hardware `3800..3E00` | 1130 / 1536 | 406 bytes |
| Scheduler `2900..2F00` | 1452 / 1536 | 84 bytes |
| F7 filesystem module `4400..5E00` | 4583 / 6656 | 2073 bytes |

These are separate address domains, not interchangeable free RAM. The new
510-byte transport alone exceeds hardware headroom. Measure the complete
composition before choosing placement or advertising capabilities.

- The shared stream transaction is 742 bytes in the serialized fixture and
  749 bytes with its IRQ profile. `0100..0400`
  was a candidate only **after** the M4 loader jumps to the high kernel. Do
  not overwrite that loader while it is executing. A deferred checked module
  load is now implemented and qualified as described above.
- Growing SUPPORT also grows the firmware-loaded bootstrap payload, which
  must remain below `9A00`. Check both the final resident map and bootstrap.
- `3000..3400` is already used by graphics, window and input state despite
  its historical `FUTURE_STATE` name. Do not allocate over it or framebuffer.
- F7 filesystem code cannot simply host helpers that must execute with an
  application/secondary bank mapped. Primary, secondary, fixed transfer and
  all live stacks must remain disjoint.
- Portable data-page support currently has a diagnostic-only CPC profile.
  If included in the receiver composition, remove that restriction only
  after proving the complete desktop layout and unchanged baseline behavior.
- Keep full 4096-byte document + independent 4096-byte staging. Notepad's
  primary has only 5 code / 11 data bytes spare; do not solve receiver
  placement by reducing the editor or adding CPC-specific APP code.

## Reproduce the transport check

Use the already accepted private MSX APP, not the native normal-image Notepad:

```sh
python3 -m unittest discover -s tests -p test_cpc_stream_adapter.py -v
python3 tools/test_cpc_stream_1984.py \
  --app build/notepad-84/build/msx/portable-notepad-7-ze7nl4tm/probe.APP
```

Its SHA256 must remain
`1d554abbd83f65ad2c332b48f7712694d55ed68a1ae5d0358f266c8ecdc340e8`.
Repeat with `--variant short`, `--variant extra`, `--variant missing` for
negative media. `--prepare-only` allows building in `my-distrobox` and then
running `--stage <printed-directory>` on the host. Every preparation creates
a fresh evidence directory/image; existing media and manual saved documents
are never overwritten. These commands test storage, not the editor UI.
