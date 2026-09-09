# Portable secondary code — implementation contract

Issue #84, `feature/84-unified-notepad`. Continues the privately qualified
[owned data-page prerequisite](PORTABLE-PAGES.md). Native delivery and public
capability publication remain unchanged until both receiver paths are proved.

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
