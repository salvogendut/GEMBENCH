# Portable secondary code — implementation contract

Issue #84, `feature/84-unified-notepad`. Continues the privately qualified
[owned data-page prerequisite](PORTABLE-PAGES.md). Native delivery and public
capability publication remain unchanged until both receiver paths are proved.

**2026-09-13 checkpoint 2h:** ordinary Desktop launches now call the stream
loader in the private MSX profile. Two-bank success, bad CRC/truncation/trailing
data rejection, rollback and pointer-only progress are qualified in openMSX;
the same APP also passes three lifetimes in 1983, in Screen 6/7. Earlier
standalone and boot-only evidence remains below. **Executable secondary calls
and editor partition/runtime are still missing**; this is not a runnable
unified Notepad. CPC streaming and normal distribution replacement still follow.

## Ordered gates

1. **Complete in instruction fixtures:** shared streamed package admission/loading and rollback,
   tested by executing the assembled Z80 policy with real owner/page allocation
   and controlled storage faults. No target loader bypass or executable call yet.
2. Bind the stream transaction into normal MSX/CPC launch, place its code/state
   within measured receiver budgets, and qualify real storage/admission failures
   with openMSX/1983 and CPC M4/1984. Keep existing primary-only/native paths.
3. Bind the sealed secondary identity and root call/return service, qualify the
   same APP on both receivers, then partition actual Notepad. A loader fixture
   is not evidence that the desktop can launch the package.

## Initial package profile

Reuse GBAP v4, GBM4 v1 and their existing 20-byte descriptors. Exactly two
segments: mandatory common uncompressed primary code, followed immediately by
mandatory common uncompressed secondary code. Both load at `4000`; each stored
image is at most `3F00` bytes, retaining the uniform `7F00` boundary. Total file
size is at most `7E00`. All 32-bit ranges must have zero high words in this
bounded profile. Reject gaps, overlaps, trailing bytes, unknown selectors,
flags/compression, mismatched stored/unpacked sizes and insufficient page claims.

The secondary starts with `JP entry; "GBS4"; version 1`. Entry must be within
the loaded secondary bytes and at least eight bytes past its start, not merely
somewhere in the allocated page. The package CRC covers the entire byte stream,
with only the manifest CRC field treated as zero. Validate the existing primary
identity, capabilities, entry, descriptors and icons using the shared admission
implementation; do not manufacture a primary-only header or waive CRC checks.
Required capability bits must also be present in the receiver's live low/high
capability words, not merely assigned in the format.

## Stream transaction and provider boundary

The existing outer launch owns the pending identity and primary page. It opens
the selected APP once using the target's existing path/drive rules. The shared
stream loader enters with that live pending owner's primary mapped and an
already-open stream at offset zero. The provider supplies native mapping and
bounded reads/close; it does not make format, ownership or rollback decisions.

Read the first 256 bytes to fixed scratch, validate the minimum prefix and safe
primary/package bounds, then load only the primary range. Reads request at most
512 bytes and must report the exact count or fail; a provider which allows
partial reads must assemble an exact read or return failure. Extra-byte EOF
probing rejects trailing data. Never reopen the file between segments.

After complete primary structural admission, allocate one SECONDARY_CODE page
through the shared owner allocator, clear its full allocation, and stream its
bytes through fixed scratch. Validate the secondary entry and complete CRC;
close storage before returning the successful private result. Until that point
there is no executable identity or callback registration. Failure frees the
secondary allocation and invalidates the result; the existing outer launch then
reclaims its pending primary/owner. Neither failed nor partial images execute.

The provider close contract releases its private stream/context even if close
reports an I/O error. An uncertain device close must retain the existing
offline/recovery policy; this is not a claim that a lost transport reply proves
the hardware descriptor was freed. A close error fails the transaction. No caller pointers,
native page number or file handle are published in an APP record. Return to
the original mapped primary, preserving IX/IY, SP, IFF and scheduler lock.
Reject worker/non-primary/terminating owners and nested load transactions.
The supplied owner must match the pending outer launch. Context/nesting
rejection occurs before stream ownership transfers: no reads or close occur,
and the outer caller remains responsible for its stream/launch cleanup.

## Checkpoint 2e — implementation and evidence, 2026-09-09

New `kernel/core/package_stream.asm`, `package_stream_contract.inc`,
`package_secondary_descriptor.asm`, `package_crc.asm` and an internal `ADMISSION_STREAMED` branch
in `app_admission.asm` implement the first gate. The branch is **not selected
by either receiver**. Its structural check deliberately defers final admission
to the stream transaction; do not wire it directly to APP entry. It uses the
distinct `gbap4_validate_streamed_primary` entry rather than the existing
`gbap4_validate_loaded`, so defining the internal flag alone cannot silently
turn the old entry gate into a CRC bypass.

Measured assembled footprint with the existing owner/page routines linked
separately: transaction **742 bytes**; streamed admission/CRC **1296 bytes**,
including 15 mutable admission bytes in the fixture. Additional transaction
state is 22 bytes and transfer scratch is 512 bytes; both must remain fixed.
Receiver bindings may relocate admission state through its existing macro.
These are component measurements, not proof of a complete receiver layout.

`tests/test_package_stream.py` executes the actual assembly and shared allocator
on the 1983 Z80 CPU core, with a simulated aperture and sequential storage
callbacks. At both low (`2000`) and high (`D800`) fixed-state layouts,
**459 transactions/checks pass**. Cases include:

- packages of 394, 12298 and 32256 bytes, including one/two icon resources;
- exact primary/secondary bytes, zeroed secondary tail, no primary snapshot or
  parent-page mutation, no application instruction execution;
- every exact read in the medium workload failing, returning short, making
  zero progress or reporting an oversized count; EOF/close errors;
- repaired-CRC malformed records, invalid/high-word ranges, each missing live
  required capability, truncated files, trailing bytes and bad full-stream CRC;
- page exhaustion before/during allocation, secondary-entry bounds, pending
  identity, worker, stale owner, terminating owner, non-primary and nesting guards;
- rollback of the secondary allocation and actual shared owner teardown after
  success; exact mapper/shadow, SP, IX/IY, IFF and lock restoration.

The injected failures are **instruction-fixture evidence**, not real M4/Nextor
fault acceptance. No secondary code executes in this test, intentionally.
`build/notepad-84/evidence/secondary-stream-complete.log` records all
**31 focused tests passing**, including prior owner, parameter, data-page,
clipboard, admission and button-capture regressions. ABI conformance and the
existing host GBAP v4 corruption/icon-editor roundtrip checks also pass.

Keeping the streamed CRC accumulator in Z80 registers reduces the maximum
fixture load from **64453420 to 25602091 T-states** (about 60% less), without
a lookup table; the default primary-only CRC is unchanged. Small/medium loads
measure 665271/9982518 T-states. These counts exclude storage, contention and
IRQ costs. Earlier timing evidence is in `secondary-stream-timing-final.log`.
Even the reduced cost is too long for a production interrupt blackout: the
next gate must qualify interrupt-safe progress, not just file I/O throughput.

### Existing dual-icon admission bug corrected

The maximum-size/two-icon case exposed an existing shared validator bug. After
comparing the second icon offset, `HL` was zero; exchanging HL/DE discarded the
offset before computing the payload end. Recovering the verified offset before
adding 512 fixes both old primary-only and new streamed validation. Instruction
size is unchanged, so the normal/opt-in MSX module sizes remain 2889/2931 bytes.

The regression uses PAGEPRB.APP with both existing icon codecs: **5524 bytes**,
SHA-256 `c0c1b9f1ee618ecc5cdb7abf520cf07195f48a016ccfb98271c23fb65e705553`.
This is the previous data-page APP with a larger icon preamble, **not a streamed
or executable-secondary diagnostic**. Reuse `PORTABLE_PROBE_ICON16=apps/formref/icon16.asm`
with the existing isolated MSX/CPC data-page test helpers.

Evidence under `build/notepad-84/evidence/`:

- `secondary-dual-icon-msx{6,7}.log`: openMSX passes three lifetimes, 448 APP
  checks and 407 preserved parameter returns per mode.
- `secondary-dual-icon-1983-{6,7}/result.json`: read-only bridge runs with the
  corrected RainBIOS, borders, code preservation, owner generations, exact pool
  cleanup and unchanged private images. These are not SDL pointer-latency tests.
- `secondary-dual-icon-cpc.log` and `secondary-dual-icon-cpc-artifacts/`: M4/1984
  passes 454 APP checks, exact pool/close-exposure recovery and unchanged APP/disk;
  stack maxima main 93, IRQ 4, temporary 0.

The new streaming core was not involved in those emulator runs. Normal MSX/CPC
media retain their recorded hashes. No new editor APP, capability, public call
opcode, commit or push is supplied by this checkpoint.

## Next integration gate — concrete receiver work

1. Audit and reserve fixed loader code/state in **both** actual delivery
   profiles. The 742-byte transaction could fit reclaimed `0100..03FF` boot
   storage, but that lifetime/exit-path assumption must be verified before
   reuse; it is not an allocated region yet. The MSX admission module is already
   close to `0FD0`; do not append the streamed variant unchecked. CPC's region
   named `CPC_FUTURE_STATE` is **already used** by drawing, registration and
   input state and must not be treated as a free kilobyte.
2. Extract single-open/read/close adapters from existing storage primitives.
   MSX must preserve strict/current versus boot/browse fallback resolution.
   CPC's current `lib/cpc/app_load.asm` repeatedly calls the read-at service,
   which opens/closes per operation; it does **not** satisfy this transaction's
   one-open-stream contract. Reuse M4 command/error/offline policy, but implement
   and qualify private descriptor lifetime explicitly.
3. Route only eligible two-segment GBAP v4 packages through the new transaction
   while keeping ordinary primary-only/native paths, shared pending-owner
   rollback, and close-error cleanup. Preserve exact source file identity;
   no reopen-by-name shortcut between segments.
4. Test real success/rejection/rollback on MSX Screen 6/7 in openMSX/1983 and
   CPC M4/1984, including load latency and interrupt/input capture under load.
   The fixture wrapper serializes the whole synchronous transaction with DI;
   bounded reads do not make that whole load a bounded-latency operation. Do not
   turn this into a production interrupt blackout without measuring and fixing
   the receiver's interrupt-safe progress boundaries. Only then connect the
   sealed call gate described below. Do not
   change normal media or advertise call support based on the fixture passes.

## Checkpoint 2f — MSX stream and interrupt boundary, 2026-09-13

`PKG_ALLOW_IRQ=1` is an explicit internal provider opt-in. After accepting the
root/pending owner and setting its busy/lock state, the common transaction allows
fixed-state time/input IRQs through validation, CRC, reads and bank clearing.
Hardware/shadow mapping transitions still exclude IRQs. Caller IFF, IX/IY,
mapping and the previous lock are restored. The provider must prove that no
worker, root callback, filesystem re-entry or transaction-state consumer can run
from its IRQ. This is not permission to dispatch the Desktop while a package is
partially loaded. The original IRQ-excluded fixture remains the default; neither
production receiver enables the new profile yet.

`kernel/msx_package_stream.asm` supplies private OPEN/READ/CLOSE leaves over
Nextor/MSX-DOS 2, preserving both index registers, caller IFF and mapper/shadow
state even if DOS returns with its own TPA page selected. OPEN takes an already
resolved absolute path; these leaves do not choose boot/browse fallback, alter
CWD, borrow the legacy file handle or use/reopen filesystem contexts. A failed
close clears the active transaction but retains the uncertain handle and a
poison status, refusing another open until explicit recovery/restart.

The real Nextor run exposed `_READ` returning `A=C7`, `HL=0` at EOF. The provider
now normalizes **only that zero-byte EOF** to the common success/zero-count
convention. Other errors and inconsistent nonzero-count EOF remain errors.
Normal primary-only/native storage paths are unchanged.

### Evidence and limits

- `stream-checkpoint-20260913-tests.log`: **42 focused tests pass, no skips**,
  including the earlier editor/doc/chooser/data-page/clipboard/owner/parameter
  and MSX input regressions. At each of two fixed-state layouts, 459 checks run
  with IRQs excluded, 459 with fixture IRQs enabled, and 928 through the actual
  MSX provider with controlled DOS returns. The last count includes real
  assembled opens, short/error reads, close poisoning and inconsistent EOF.
- Fixture IRQs deliberately clobber and restore the CPU registers. The longest
  measured DI interval in the enabled profiles is **234 T-states**, including
  the fixture ISR but **not real BIOS/DOS latency**. The test permits DOS's own
  temporary bank only within the tracked DOS call/recovery interval, and always
  requires the caller's mapping back on return. No package code executes.
- `debug/package_stream_msx.asm` is a **standalone DOS diagnostic**, with a
  3713-byte relocated payload at `8000`, not a fitted production kernel. It
  uses real mapper allocations, the shared owner/page policy and both new
  components. Six cases: valid maximum package, bad CRC, truncated secondary,
  extra trailing byte, missing file, then valid load again. All successfully
  opened streams close; owner teardown restores the exact two-page free count,
  and the two DOS mapper allocations are freed at completion.
- `stream-nextor-openmsx-20260913-eof.log`: openMSX passes **345 read-only
  observations**, including exact primary/secondary bytes and zero tail. It
  observes opens `1 1 1 1 1 1`, reads `65 65 64 65 0 65`, closes
  `1 1 1 1 0 1`. The final 32256-byte load spans **557 BIOS ticks**.
- `stream-nextor-ph9009o_/1983-result.json`: the same private disk passes all
  six guest cases with the existing read-only 1983 bridge/corrected RainBIOS;
  the final load spans **438 BIOS ticks**. This repeat observes result/cleanup
  checkpoints, not openMSX's instruction breakpoints or SDL pointer behavior.
  Both runs leave the image unchanged. Package SHA-256:
  `d64ee5170e5b268c0051ef1a24347459bbf5926db604251364435ff538f809bd`.

All paths above are under `build/notepad-84/evidence/`. The 1983 report pins the
bridge and ROM hashes. Preserve the earlier failed logs: the first observer
mistakenly overwrote a failure with PASS because openMSX `exit` is asynchronous.
That run has zero completed cases and is **not acceptance**. The observer now
stops evaluation on failure and cannot overwrite a result; a host Tcl regression
checks this independently. The subsequent DOS-return trace identified EOF, and
the passing repeat retains the original six cases and byte/count assertions.

Reproduce privately with the project tools available:

```sh
python3 tools/test_msx_package_stream.py
python3 tools/test_msx_package_stream.py --check-1983 <stage-from-first-run> \
  --bridge build/notepad-84/evidence/clipboard-1983-bridge \
  --omega build/rainbios-170/build/rainbios_omega.rom \
  --sunrise ../1983/ROMS/Nextor-2.1.1.SunriseIDE.ROM
```

### Historical checkpoint 2f placement candidates — superseded by 2g

| Component | Measured bytes | Candidate interval (end exclusive) |
| --- | ---: | --- |
| IRQ-enabled shared transaction | 749 | `0100..03ED`, 19 bytes before existing `0400` module |
| MSX stream provider | 173 | `D2EC..D399`, after the 492-byte data-page module |
| Provider state + transaction state | 3 + 22 | `D399..D3B2`, leaving 78 bytes before `D400` |
| Transfer scratch | 512 | Existing `1800..1A00` filesystem buffer, only under exclusive launch ownership |

The bootstrap's final `JP GB_KERNEL` leaves no return into its low stub; its
tick handler is copied to page 3, and normal exit runs resident cleanup then
BDOS termination. Reclamation must occur after this handoff. The component
span test protects the candidate budgets, but the standalone diagnostic does
not execute these placements or prove the complete Screen 6/7 child images fit.

In particular, the existing opt-in admission module ends at `0F73`, with only
93 bytes before the legacy sysinfo view at `0FD0`. Replacing its 1181-byte old
admission with the 1296-byte streamed variant alone needs 22 bytes more than
that gap **and would lose the required primary-only entry**. Integrate both
routes deliberately, preserving CRC admission for ordinary apps; the candidate
spans above are not a licence to overwrite sysinfo or extend the application
stack/memory limits. CPC's occupied FUTURE_STATE warning still applies.

**Next:** resolve normal MSX strict/current versus boot/browse paths before one
open; fit and load the components with both admission routes; exercise normal
launch/rollback and actual root input/pointer behavior. BIOS ticks advancing is
not proof of pointer smoothness: the synchronous CRC still takes seconds and
this diagnostic has no Desktop or installed scheduler. Then qualify CPC's
persistent provider and the sealed call gate. No normal images, capability
publication, runnable editor, commit or push are supplied by this checkpoint.

## Checkpoint 2g — dual admission and fixed MSX boot, 2026-09-13

`ADMISSION_DUAL` retains full CRC validation for normal primary-only packages
and a distinct structure-only entry for the stream transaction. The latter
still requires the transaction's complete CRC/EOF/close checks before success.
The normal entry clears the private mode every time, so a prior streamed call
cannot bypass primary CRCs. Native/GBAP v1–v3 behavior remains; normal admission
rejects two-segment packages and unknown versions. Default builds are unchanged.

The opt-in receiver uses `PORTABLE_DATA_PAGES=1 PORTABLE_PACKAGE_STREAM=1`.
It reclaims the dead low COM stub and unused fixed-RAM gaps, without changing
the `7F00` application limit, `D400` fixed-app boundary or stack allowance.
`tools/build_msx_package_modules.py --out PRIVATE_DIRECTORY` assembles and
checks three versioned boot files; it never stages normal media.

| Component | Actual interval, end exclusive | Bytes |
| --- | --- | ---: |
| `GBPKLOAD.MOD`, header + IRQ-enabled shared transaction | `0100..03F5` | 757 |
| `GBAPV4.MOD` v3, dual admission/parameters/sysinfo/input | `0400..0FB4` | 2996 |
| Existing copied button IRQ, unchanged | `CF60..CFDB` | 123 |
| `GBPKFIX.MOD`: stream helpers, bindings, state/padding | `CFDB..D100` | 293 |
| Same image: existing data-page module | `D100..D2EC` | 492 |
| Same image: relocated CRC helpers | `D2EC..D39F` | 179 |
| Same image: padding, then 16-byte admission state at `D3F0` | `D39F..D400` | 97 |

The high image is 1061 bytes. Its stream helpers end at `D0E3`; transaction
state is `D0E7..D0FD`, provider state `D0FD..D100`. The 512-byte transfer buffer
remains `1800`, exclusively borrowed under serialized launch. An assembler
assert prevents future IRQ-template growth from overwriting the helpers.
Shared `owner_validate` was extracted unchanged for the fixed binding; the
existing resident owner/page allocator is reused, not replaced.

The boot loader checks exact lengths and module versions, including the inner
data-page header. Its exact-capacity read exposed Nextor `_EOF C7/HL=0` on the
legacy loader's extra-byte probe; the opt-in branch accepts only that empty
EOF, rejecting C7 with bytes or other errors. Module faults are instruction
tests with a stubbed file-load boundary, **not real-media fault qualification**.

Evidence under `build/notepad-84/`:

- **45 focused tests, no skips**, ABI and deterministic packaging checks pass:
  `evidence/package-modules-regression-20260913-final.log`. Includes dual
  admission/stream matrices at both state layouts (941 combined checks each),
  39 module boot cases, six exact-capacity EOF cases, IRQ-install guards and
  the readiness/fail-closed observer regression.
- openMSX Screen 6/7: same 5004-byte PAGEPRB.APP, three real Desk launch/close
  lifetimes, 148/150/150 app checks and **407 service-return preservation
  observations per mode**. Logs `package-modules-screen6-20260913-ready.log`
  and `package-modules-screen7-20260913-final.log` in `evidence/`.
  Screen 6/7 child images are **14505/16083 bytes**; Screen 7 has only **45
  bytes spare** below `3F00`. Further resident code must be measured/refactored,
  not allowed to grow through that boundary.
- 1983 with the same recorded bridge/RainBIOS/Nextor: 37/46 independent
  lifecycle/guard observations, three generations each, exact pool teardown,
  unchanged APP/media. `evidence/package-modules-1983-{6,7}-20260913/result.json`.
  Screen 7 uses `build/msx/portable-data-pages-7-n8rstjv2/filesystem.img`;
  Screen 6 uses `build/msx/portable-data-pages-6-j1qraujz/filesystem.img`, rerun
  successfully with the corrected observer. A fresh automated Screen 6 repeat
  is `build/msx/portable-data-pages-6-z9ost1t2/filesystem.img`.
- APP SHA256 remains
  `bf08c4164500a05470214213b9189eb9146787d545ca643fccb5be88612ff97b`.
  The three normal-image hashes still match the handoff; no release media,
  new public secondary-call capability or unified editor was delivered.

Preserve failed evidence: the first boot rejected valid exact-size EOF; the
first Screen 6 observer sampled at a fixed time rather than verifying mapped
RAM/readiness. The updated driver waits for the real low module and Desktop
before baseline/input, retaining its workload deadline. An intermediate manual
repeat used the wrong probe-state address and failed correctly; successful runs
use the linked `7000` symbol. Neither failed run counts as acceptance.

**Next:** integrate current/strict and boot/browse path resolution with one open
and route normal pending-owner WM launches through the fixed transaction,
preserving existing primary/native behavior. Qualify actual two-segment
launch/rollback and root pointer latency before publication. The fixed stream
transaction's entry is installed but **not exercised by these Desktop tests**;
they qualify module coexistence, relocated primary CRC and ordinary app
lifecycles. The sealed call gate, editor partition and CPC stream binding still
follow. Do not present PAGEPRB as a runnable unified Notepad.

## Checkpoint 2h — normal MSX streamed launch, 2026-09-13

The first internal task of the [runnable-editor sprint](UNIFIED-NOTEPAD.md#consolidated-sprint--runnable-msx-notepad)
is implemented and qualified on private MSX receivers. It is not completion of
the sprint or of full cross-platform delivery.

`kernel/msx_app_launch.asm` connects the existing strict/current-system and
boot-system/browse fallback resolver to the shared pending-owner launch path.
The resolver still chooses and opens the file. An armed launch requests a
bounded 256-byte first read; only an eligible v4 two-segment prefix transfers
that already-open descriptor to the stream transaction. Its first read consumes
the cached prefix exactly once; subsequent reads use the same descriptor.
After adoption there is no reopen/fallback to a different file, even on failure.
The outer resolver restores the browsing context before the router returns the
stream status to shared WM publication/rollback. Ordinary/native candidates
retain their existing admission path; primary-only admission still checks CRC.

Worker, pending-owner, active transaction and uncertain-close guards run before
public launch changes the filename or allocates an owner. Failed/partial
packages never enter APP code. Stream cleanup frees its secondary and the
existing outer failure path reclaims the primary/owner. An uncertain close
still blocks another launch until recovery/restart; it is not silently reused.

### Placement and progress

MSX uses only the first 512 bytes of `fsam_buf` for backdrop loading and has no
2-KiB FDC directory provider. Its otherwise unused `1C00..2200` tail is now
reserved for the opt-in launch module, with a backdrop-bound assertion and a
documented mutually exclusive overlay in `kernel/lowram.tsv`. The legacy bulk
transfer area at `2200`, fixed application boundary `D400`, application limit
`7F00` and stack reserve are unchanged. In particular, do not claim `3C00..3E00`:
some native paged helpers still use the cooperative bulk-buffer size there.

| Installed component | Interval, end exclusive | Bytes |
| --- | --- | ---: |
| `GBPKLOAD.MOD` v2, shared IRQ-enabled transaction | `0100..03EB` | 747 |
| `GBAPV4.MOD` v4, dual admission/parameters/input | `0400..0FB4` | 2996 |
| `GBPKWM.MOD`, normal launch/progress/clear | `1C00..1D7C` | 380 |
| `GBPKFIX.MOD` v3, helpers/data pages/CRC/state | `CFDB..D400` | 1061 |

The high file retains data-page code at `D100..D2EC`; CRC helpers are now
186 bytes at `D2EC..D3A6`, cached-read helpers 43 bytes at `D3A6..D3D1`, and
admission state remains `D3F0..D400`. Launch/prefix/status use `D0E3..D0E6`,
transaction state `D0E7..D0FD`, descriptor state `D0FD..D100`. The four boot
files have exact sizes and versioned headers; `GBPKWM` additionally encodes
Screen 6/7 because its resident service addresses differ. The module builder
produces the first three files; the matching kernel assembly emits `GBPKWM.RAW`.

Measured Screen 6/7 child COM sizes are **14534/16112 bytes**, leaving **16 bytes**
in Screen 7's `3F00` envelope. Further services must fit/refactor measured
fixed-module space, not increase public limits.

The serialized transaction permits BIOS/IRQ input but never app callbacks.
CRC checks every 32 bytes, bounded storage reads and 512-byte zeroing chunks
provide tick-throttled pointer-only progress through existing input/movement/
hardware-cursor leaves. They do not call `k_poll`, dispatch menus, repaint
windows or update Clock mid-load. The provider preserves CRC registers and
publishes matching pointer coordinates for existing IRQ button capture.

### Evidence and reproduction

Evidence is under `build/notepad-84/evidence/`; all images are disposable, with
the probe installed as a **private CLOCK alias**, not a replacement editor.

- `sprint-launch-final-tests.log`: **55 tests pass, no skips**, including 39 actual-router
  control-flow checks, 50 module boot fault/size/header cases, six bounded EOF
  and nine cached-prefix checks, and the existing shared stream/owner/page/SDK/
  editor regressions, fail-closed launch observations and the settled-pointer
  regression. Faults in instruction fixtures are not hardware faults.
- `sprint-launch-msx7-paired.log`, `sprint-launch-msx6-good.log`: openMSX passes
  three normal Desk launch/close cycles each, 147/149/149 app checks and 401
  preserved parameter returns. Every launch opens once, reads 44 times, closes
  once, compares the complete 5024-byte primary and 16128-byte secondary plus
  zero tail, and returns the page pool exactly to baseline after close.
- `sprint-launch-msx7-{badcrc,short,extra}.log`: three attempts for each actual
  damaged private file pass rejection/no-entry/exact rollback. Truncation uses
  43 reads; the others 44. No retries against another filename or extra opens.
- The 21152-byte diagnostic takes **468 PAL BIOS ticks (9.36 s)** per successful
  load. It is still slow; pointer-only progress is not asynchronous app loading.
  openMSX observes 461/462 pointer updates, maximum gap 5/4 ticks (Screen 6/7).
- `sprint-launch-1983-{6,7}-settled/result.json`: the same APP passes three owner
  generations, exact primary/secondary bytes, tail, pool recovery and unchanged
  media; 352/361 checks. Each 100-frame in-flight pointer test records 78
  movements, maximum four frames between movements. These use real keyboard
  pointer input, not SDL mouse-latency measurements or injected guest calls.
- `sprint-launch-primary-msx{6,7}-final.log`: ordinary primary-only PAGEPRB still
  passes three lifetimes and 407 preserved service returns per mode in openMSX.
  `sprint-launch-compat-1983-{6,7}/result.json`: ordinary unified Clock/Calculator
  pass three launch/activate/close cycles and ticking-Clock pointer checks, with
  82/109 observations and exact application-page recovery. Native entry remains
  covered by admission fixtures and unchanged Desktop boot, not an all-app sweep.
- ABI, deterministic package and low-RAM checks (55 ranges, nine documented
  overlays) pass. Normal MSX, CPC Desktop
  and CPC runtime image hashes still match the handoff.

Successful private fixtures:

```text
build/notepad-84/build/msx/portable-data-pages-7-ijn4r1wi/
build/notepad-84/build/msx/portable-data-pages-6-5ndm_qjx/
APP SHA256: 2000485837e7e8fe8190936e4209d3b748932cb1b2d4517b7503e09aedaf7305
```

After explicitly syncing changed source to the private worktree, reproduce with
the container's RASM/SDCC toolchain:

```sh
cd build/notepad-84
python3 tools/test_portable_fs_openmsx.py --mode 7 --data-pages --package-modules --two-segment
python3 tools/test_portable_fs_openmsx.py --mode 6 --data-pages --package-modules --two-segment
python3 tools/test_portable_fs_openmsx.py --mode 7 --data-pages --package-modules --two-segment --launch-case badcrc
```

Use `short`/`extra` for the other faults and omit `--two-segment` for ordinary
primary-only regression. New fixtures save matching `probe.APP`/`probe.noi`;
pass `--app STAGE/probe.APP` to `tools/test_portable_pages_1983.py` with the
existing bridge/firmware/worktree/image arguments. For the older Screen 6
fixture above, pass the identical Screen 7 APP's `probe.noi` via `--symbols`.
This avoids depending on subsequently rebuilt probe symbols. `APP_SECONDARY`
in `tools/build_uapp.sh` only exposes existing two-segment packaging; it is
not the restricted secondary SDK or a callable secondary service.

Preserve the unsuccessful runs: pointer progress initially had 15- then
7-tick gaps; bounded read/clear hooks reduced them without weakening the
six-tick observer limit. The three-cycle driver needed a 300-second emulated
deadline after adding pointer journeys; the earlier 180-second run timed out
after completing all three workloads but before final close. The 1983 trace
showed the third click selecting `CALC.APP`, not a stream failure: the input
driver now rechecks settled coordinates after key release. A host regression
covers that overshoot. No sibling emulator or firmware was changed.

**Next internal sprint task:** bind immutable owner/page/entry seals, implement
and qualify copied secondary calls and the restricted SDK, then partition the
actual editor. The validated secondary in this probe is deliberately never
executed. CPC stream binding and full release qualification remain deferred.

## Sealed call contract (next, not yet implemented)

Bind one immutable `(owner generation, page generation, validated entry, length)`
record only after the full load succeeds. A raw allocated code-purpose page is
not a sealed executable. Owner teardown clears the record before reuse; every
call revalidates its live owner/page generations and purpose.

Initial secondary entries are **computation-only**, invoked from primary root
callbacks, non-nested, with up to 512 copied bytes of arguments/results. A
kernel-owned fixed buffer is passed by argument, not by a public target address.
The secondary may use its own private code/data and pure library functions;
it may not call UI, filesystem, timers, registration, page mapping or other
kernel services, retain callbacks, enter workers or call primary pointers.
The SDK audit must enforce the restricted leaf profile before packaging.
Application-defined commands in the copied block select model operations;
the caller does not choose arbitrary executable offsets.

Keep filesystem/UI work in the primary controller. This supports moving
Notepad's actual editor model and its state behind copied commands without
per-target editor implementations. If later measured partitioning needs leaf
services, extend and qualify that contract explicitly, rather than permitting
unchecked cross-page pointers or reusing native app-installed trampolines.

The runtime gate retains primary owner identity, mapping/shadow, return stack,
interrupt state and lock across entry/return, then copies results into primary
objects. No promise of sandboxing malicious Z80 code or recovering from a leaf
which never returns. Chunk long work and measure input latency in receiver tests.
No public opcode or capability for calls is advertised at this checkpoint.
