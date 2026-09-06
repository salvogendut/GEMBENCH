# Step 3D-I: shared read-only filesystem contexts on CPC M4

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`. Follows the committed and pushed
[3D-H loading checkpoint](CPC-RESTART-STEP3D-H.md) at `a23af29`.

Status: **45 read-only context checkpoints pass on real M4 media in unchanged
1984. Private diagnostic integration, not the public CPC filesystem API or
Desktop.** Directory iteration, writes and free-space reporting explicitly
return `UNSUPPORTED`. No CPC capability record is advertised.

## Shared policy, mapped module and hardware boundary

`kernel/core/fsctx_gate.asm` extracts the production MSX resident gate without
changing its instructions: reject workers, obtain the implicit owner from the
mapped caller, then dispatch the module. Both targets include it. CPC ignores
an application-supplied request owner, just as MSX does. The CPC wrapper holds
the root lock and excludes IRQs, restoring the caller's bank, lock and IFF.

`kernel/kc/gbfsctx_cpc.c` compiles the **unchanged**
`kernel/core/fsctx_policy.inc` with CPC fixed-state and hardware bindings.
The same code owns four generational contexts, path/name state, independent
32-bit offsets, launch preparation/adoption and validation. Existing shared
resident owner cleanup invalidates contexts without doing storage I/O.

The build links a separate `FSCTX.BIN` at `4400` in reserved data bank F7.
The real M4 loader reads it in 128-byte chunks and verifies its linked length
and destination bounds before marking it ready. It is a trusted build asset,
not an APP admitted by the GBAP validator. Executable bytes are not injected by
the host or included in the resident binary. The C module stays mapped during
CD/GETPATH and the existing fixed read-at gate's OPEN/SEEK/READ2/CLOSE work.

Each activation starts with CD to root, then relative CD components, followed
by GETPATH and an exact path comparison. This retains the original M4 backend's
real-hardware workaround for unreliable absolute CD. CD has no status payload;
an empty reply alone cannot establish that a directory exists. A missing-path
case tests the verification. Context switching never overwrites the caller's
512-byte transfer buffer merely to select a directory.

One mounted volume is supported (drive ID 0). This leaf accepts uppercase
letters, digits, underscore and hyphen, directory components up to eight
characters, a context path up to 47 characters and padded 8.3 file names.
Backslashes are normalized to slashes. Reads of 1..512 bytes use at most four
128-byte native transfers, copying only actual bytes; the shared policy then
advances its context offset once. The adapter rejects 32-bit offset wrap, but
large-offset/wrap behavior is not yet exercised by the native fixture.

The existing shared API's zero-read/I/O-error ambiguity remains: after a
successful activation, a failed read may yield zero or an already received
prefix with an OK policy status. This checkpoint does not introduce stronger
error or atomic-read semantics than MSX.

## Why directory operations are still disabled

The original `../geobench/lib/fs_m4.asm`, M4 firmware source
`../m4rom/M4ROM.s`, and unchanged `../1984/src/m4.c` were inspected as protocol
references; none becomes a build dependency. Their catalog representation
uses a directory marker in the first display-name position, truncating an
eight-character directory name to seven, and supplies only a 16-bit size.
The firmware reference SHA-256 is
`347694dc0dc4cbe0d7ce37ae70b594e47b84afd3ebe20ff5d80064c98748123d`.

Passing that representation through would not establish MSX directory parity.
A later adapter must qualify full names, file sizes, independent enumeration
cursors and end/error handling before enabling first/next/batch. Write and
free-space bindings also remain separate acceptance work.

The private resident dispatcher rejects operations 5, 6, 9, 10 and 14 before
entering the C module. Unreachable stub bindings only permit compiling the
unchanged shared source; they never report successful empty directories or
writes. This backend-level rejection does not claim full MSX validation/error
precedence for unsupported operations.

The M4 transport accepts the two-byte, no-payload control frames only in the
`CPC_FSCTX` composition, and avoids a zero-count `LDIR`. The ordinary read-at
composition and its stricter minimum framing remain unchanged. Hardware HOLD
still cannot be bounded by a software timeout. Storage is synchronous and
IRQ-excluded; this diagnostic is not a GUI responsiveness measurement.

## Memory and executable measurements

| Allocation | Purpose |
|---|---|
| Fixed `1500..16FF` | 512-byte transfer buffer in the existing reserved allocation. |
| Fixed `2400..241F` | Shared request record. |
| Fixed `2420..245F` | Reserved directory cursor; not yet hardware-bound. |
| Fixed `2460..249F` | Shared launch handoff. |
| Fixed `24A0..24AF` | Diagnostics, selected-context pointer and native/module-loader scratch. |
| Fixed `24C0..24EF`, `2500..253F` | Normalized path and joined absolute file name. |
| Fixed `2600..283F` | Four shared 144-byte context records. |
| F7 `4400..4F5F` | Loaded 2,912-byte C module; hard upper limit `6000`. |
| F7 `6000..60FF` | Existing native request/path/read staging, separate from code and font. |
| Fixed `3300..3344` | Private fixture counters, saved handles and capture-page IDs. |
| Four allocated owner pages | 45 request/state/data captures; reclaimed after the test. |

High kernel: **15,314 / 16,384 bytes**, including fixture code and older unused
vectors. Resident FS adapter: **398 bytes**; F7 module: **2,912 / 7,168 bytes**;
low support: 1,673 / 3,072; scheduler: 1,437 / 1,536; hardware: 1,057 / 1,536.
The module map has no mutable DATA/BSS allocation. Assembly and build checks
reject overlapping/oversized sections. Repeated two-pass assembly and C linking
produce identical payloads and stable resident symbols.

This composition includes loading/registration/cleanup, but is **separate from
the 3D-G interactive root-loop fixture**. These numbers do not prove that the
complete public API, modules, GUI and kernel fit together. No framebuffer or
non-display raster-gap bytes hold state. The transfer-buffer reservation must
remain disjoint when the remaining services are composed.

## Executed checks

Firmware boots a private FAT16 M4 image through the actual loader. The image
contains the module and two deterministic files: `DOCS/SUB/A.BIN` (700 bytes)
and `ALT/B.BIN` (333 bytes). Host control only sends a key, waits and takes
read-only snapshots; no floppy, snapshot boot or injected application RAM.

The native fixture uses the real caller bank and poisons `REQ_OWNER` with
`DEAD`. Forty-five transactions cover:

- Invalid drive; root and other-owner allocation; independent paths/names.
- Interleaved 128/300/512-byte reads, short reads, EOF and transfer-tail guards.
- Zero/oversized read rejection, wrong-owner access, close, stale generations,
  slot reuse and full-table exhaustion.
- Launch preparation/adoption, inherited path/name with a fresh read offset,
  one-shot adoption and explicit unsupported operations.
- Missing-directory activation failure, path restoration, cancel/rewind and
  a repeated exact read.
- Shared resident owner cleanup, rejected old handles, fresh allocation/read
  and final close.

An actual scheduled worker also calls the gate during the existing 64
IRQ/root/worker/I/O rounds and must receive `CONTEXT`, not enter the module.
This is distinct from root execution on behalf of an application's bank.

An independent host oracle compares all 1,192 captured bytes per transaction:
request, four contexts, launch handoff, full transfer buffer and return state.
It checks alternating caller bank/IFF, root lock, descriptor/offline state,
117 context-phase M4 commands, trace padding, complete page reclamation, module
and font integrity, and every framebuffer byte including the raster gaps.
There are **946 M4 commands overall**, including boot/module loading and the
base rounds. Final RAM remains stable for another 150 frames. Observed
main/IRQ/temporary stack use is **59 / 4 / 6 bytes**, guards intact; context
high-water is 26. These are workload measurements, not worst-case bounds.

The fault variant deliberately substitutes the root owner for the real caller.
It is rejected specifically at `fsctx worker-owner-allocate: byte 4 got 01
expected 02`. Five unit tests cover source sharing, the private boundary,
deterministic native/module linking and bounds, a deliberately undersized
allocation, and oracle rejection of corrupted owner/data/bank/guard records.

Native execution caught a bad path-copy sequence emitted by pinned SDCC
4.6.2 #16671: the inline volatile load in the read loop was spilled incorrectly
and copied the destination address high byte. Splitting filename construction
and using the existing shared `copy_bytes` helper fixes the emitted code; the
complete native file-byte oracle passes afterward. No compiler or emulator
source was changed.

Both MSX kernels reassemble byte-identically after the resident-gate extraction:

- Screen 6: `1f8f5d37e3350a1c07a8e17df947fa95a62dc97d0c78dfad6bb6eaeddeb4d59f`.
- Screen 7: `68898fb51ccb4acfca696609fbddb8b5b2aaac426d572992cb837cb0f3d9dc71`.

The shared C policy and MSX provider are unchanged. No MSX release-image rebuild
is required. The previously recorded legacy Notepad-opening failure is not
fixed or claimed passing by this checkpoint.

Full `make check` passes (exit 0): **186 Python tests without skips**, plus
native-library, universal SDK/ABI/package/layout and distribution checks.
The isolated worktree `/tmp/geobench-77i-check.sobyZV` excludes the user's
untracked parked `QA/CPC/` tree without changing or weakening the target audit.
Log: `/tmp/geobench-77i-check.log`.

The preceding 3D-H loader test still passes all 17 transactions and 1,834 M4
commands; hardware code remains 1,055 bytes outside this composition. Artifacts:
`/tmp/geobench-cpc-production-9x3ilur4`, log
`/tmp/geobench-77i-loading-regression.log`.

The unchanged SYSINFO lifecycle harness passes in headless openMSX, Screen 7,
with a private Nextor hard-disk image and UNAPI disabled. It verifies the full
filesystem test mask, owner generation reuse `0103` to `0203`, 53 context calls,
22 final free pages, and only the baseline File Manager context left alive.
Log: `/tmp/geobench-77i-msx-fsctx.log`. Screen 6 has binary identity evidence
here, not a newly executed filesystem lifecycle run.

Positive artifacts: `/tmp/geobench-cpc-production-4tj8rll1`, log
`/tmp/geobench-77i-fsctx-final.log`. Fault artifacts:
`/tmp/geobench-cpc-production-obwl661y`, log `/tmp/geobench-77i-fsctx-bad.log`.
Unit log: `/tmp/geobench-77i-unit.log`. Toolchain: RASM 3.2.1 and SDCC/SDAS
4.6.2 #16671. Unchanged 1984 executable SHA-256:
`0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`.
Positive M4 image SHA-256:
`cca836878eff580c4d750cdb9bdc233c27bae622ca003a6c670bbda057739c50`.
Final framebuffer SHA-256:
`fe4dde11b323cc80d43176778f8d4977ce45617d7d8448568b2484a4f60b7d73`.

## Reproduce and next integration

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-fsctx-1984
```

Build only: `make diagnostic-cpc-fsctx` with the same toolchain. Output:
`QA/Diagnostics/CPC-production/fsctx/{CARD,ADAPTERS.IMG,manifest.json}`.
Fault test: `python3 tools/test_cpc_production_1984.py --variant fsctx-bad-owner`.
Runtime uses a private image copy and prints its `/tmp` artifacts. The parked
`QA/CPC/` tree is untouched. This is not an Albireo qualification.

Next: qualify the missing M4 directory/cursor and metadata bindings, then the
write/free-space operations required for actual filesystem parity. Complete
the budgeted public API/sysinfo/module composition and join loading to the
shared loop before claiming the first unchanged SDK window. Desktop/File
Manager and application parity still follow that gate. Issue #77 stays open.

Follow-up: [3D-J protocol preflight](CPC-RESTART-STEP3D-J.md) now demonstrates
that current 1984 lacks extended READDIR and FSTAT. Directory integration is
blocked; the new real-M4 reproducer returns a nonzero qualification result.
