# Unified Notepad — CPC receiver binding

2026-09-13, issue #84, `feature/84-unified-notepad`.

The MSX arrow-navigation / incremental-repaint fixes were accepted by the
user and committed/pushed as **`6e6fe05`**. This work brings the **same APP**
to CPC; it is not a separate CPC editor or a replacement desktop port.
The accepted normal CPC distribution remains unchanged.

## Current checkpoint: sequential M4 transport qualified

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
linked into normal CPC delivery builds. Probe addresses are explicit test
bindings, **not approved production allocations**.

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

1. **Private runtime placement and shared two-bank transaction/call gate.**
   Bind `kernel/core/package_stream.asm`, dual admission, secondary seals and
   `secondary_call.asm` to the CPC owner/page tables and native mapping leaf.
   Reuse the new stream leaves; wire the existing launch transaction hooks,
   not a second application-launch policy. Publish a seal only after CRC,
   descriptor validation and successful CLOSE. Enable the parameter operation
   and capability only with a successfully installed matching receiver.
   Qualify page/owner-generation cleanup, failed launch rollback and stack
   guards in the actual private desktop build, including Clock/Calculator.
2. **Document and input bindings.** Enable the existing shared filesystem
   identity / owner-bound launch-handoff policy in CPC's paged FS module and
   File Manager. Port focused `GB_WK_TEXT_INPUT` routing using CPC keyboard
   capture, preserving Ctrl+arrows/Space pointer access. Native/default
   windows must retain their existing input behavior. No editor-side fork.
3. **Identical APP acceptance in a private desktop M4 image.** Open/edit/save,
   arrows/Space/backspace, bounded repaint, exact-path document launch,
   focus/occlusion, dirty close, 4096-byte round trip, 4097-byte rejection and
   repeated cleanup. Only then supply a manual CPC editor image. Normal
   delivery promotion is separate; M4/Albireo tests only, never floppy tests.

## Placement constraints for the next gate

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
  is a candidate only **after** the M4 loader jumps to the high kernel. Do
  not overwrite that loader while it is executing. A deferred checked module
  load is one candidate, not yet an implemented solution.
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
