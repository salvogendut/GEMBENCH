# Step 3D-H: shared application admission and M4 launch transactions

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`. Follows the committed
[3D-G input/root loop](CPC-RESTART-STEP3D-G.md) at `77c44fe`.

Status: **M4 loading/validation/rollback diagnostic implemented and validated
in unmodified 1984. Not a public CPC application runtime or Desktop.**

The next integration identified in 3D-G is split at a testable boundary:
this checkpoint handles loading; full owner filesystem-context operations,
public jump table/sysinfo and loaded SDK execution remain open. Admitting a
package format does not establish support for the capabilities it requests.
No CPC capability record is advertised by this private link.

## Shared policy and CPC storage

`kernel/core/app_launch.asm` is the production MSX launch path: copy name and
optional argument; enforce window limit; allocate owner and primary page;
bind/map/load; validate before entry; call the entry; restore the caller bank;
reclaim the pending owner and all owned pages on rejection or an unregistered
return. Registration consumes the pending identity through the same shared
code. Last-window close uses the existing shared owner/page cleanup.

`kernel/core/app_admission.asm` is the existing primary-only GBAP v4 validator:
canonical header, manifest/ABI identity, version, bounds, primary descriptor,
icon directory, minimum-page requirement and CRC32. Headerless/native and
v1-v3 compatibility retain the MSX policy; unknown versions are rejected.
The CRC field is restored before return, even on a failed comparison.

MSX binds both units at their original locations. Both screen-mode kernels
and `GBAPV4.MOD` reassemble byte-for-byte unchanged. No universal APP, ABI
constant or MSX filesystem behavior changes.

`lib/cpc/app_load.asm` reads absolute `/GBENCH/NAME.EXT` paths on one mounted M4
volume, without changing a global working directory. Strict and normal opens
use the same namespace here; boot/browse-drive fallback is not implemented.
Bounded uppercase padded 8.3 components allow letters, digits, underscore and
hyphen; empty components, separators and embedded padding fail before I/O.

The qualified M4 `storage_gate` is unchanged. Each 128-byte read executes real
OPEN/SEEK/READ2/CLOSE. Requests/path/buffer live in reserved data-page scratch,
not the APP being loaded. Bytes cross fixed staging before the destination is
mapped. All exits restore that mapping for the shared caller-bank rollback.
Only successful/short reads are copied. Exact file size is published.

The maximum image is `3F00` bytes (`4000..7EFF`). A one-byte EOF read at the
limit rejects oversized files instead of executing truncated prefixes. Empty
files never enter; `7F00..7FFF` remains reserved for context snapshots.

## Allocations and measured link

| Allocation | Purpose |
|---|---|
| Fixed `2840..287F` | Path, after four reserved 144-byte owner FS contexts. |
| Fixed `2880..2888` | Offset/destination/count/status/native page/path length. |
| Fixed `28A0..28AE` | Validator scratch and stored/calculated CRC. |
| Fixed `3400..347F` | Existing serialized drawing staging reused for loading. |
| F7 `6000..60FF` | Request, path and read buffer, disjoint from its font at `4000..432F`. |
| F7 `6200..641F` | Seventeen 32-byte diagnostic captures. |
| Fixed `3300..3365` | Private diagnostic counters/captures/allocation pressure. |

High kernel: **14,361 / 16,384 bytes**, including unused diagnostic vectors
and fixtures. Launch/admission/M4 leaf: **1,668 bytes**. Low support:
1,673 / 3,072; scheduler: 1,437 / 1,536; hardware: 1,055 / 1,536.
No framebuffer/raster-gap state. Assembly rejects an undersized high allocation.

This registration/cleanup link is separate from the interactive 3D-G fixture.
It is not evidence that the complete combined kernel/modules fit. Full
integration and module placement remain acceptance gates.

## Executed checks

Firmware boots an isolated FAT16 M4 image through the real core loader. Host
commands only send Right, wait and save read-only observations. No snapshot
boot, application RAM injection, alternate WM or emulator modification.

Seventeen transactions cover valid v4 return/reclamation; bad CRC, unknown
version, invalid identity, wrong primary address, inconsistent length and
truncation; empty, oversized, missing and invalid-path files; an unsatisfied
minimum-page requirement; native managed registration/close; strict launch and
file argument; real allocator owner/page exhaustion, cleanup, then a successful
maximum-size v4 launch. Four entries execute, two register windows.

The native window fixture calls the private registration adapter and returns.
Its paint callback is null: this checks publication/focus/lifetime, not a
visible loaded SDK window. V4 fixtures only increment telemetry and return.
These files are not ABIPROBE, Clock or Calculator.

The oracle checks each owner table, pending identity, free count, focus, bank,
IFF/root lock, registered code-page identity and argument. It also checks all
maximum-size file bytes after admission (including restored CRC), the entire
256-byte context fence, final owner/page reclamation, reserved FS contexts,
code/font integrity and exact framebuffer including raster gaps. Last-window
cleanup restores the pointer; those pixels are accounted for independently.

The positive run performs **1,834 M4 commands**, including bootstrap and the
existing 64 IRQ/worker/I/O rounds. Final RAM is stable for another 150 frames.
Main/IRQ/temporary stack high-water: **26 / 4 / 6 bytes**, guards intact.
A deliberately broken admission provider fails specifically at the bad-CRC
case (`loading 1 admission/entry count`), not merely with a generic crash.

The five new source/package/layout/repeatability tests pass. Full `make check`
passes in an isolated worktree (181 Python tests, no skips, plus native C,
SDK/ABI/package/layout/distribution checks). The isolation leaves the user's
untracked parked `QA/CPC` tree untouched and does not weaken the target audit.
OpenMSX with private Nextor images and UNAPI disabled passes good v4, bad-CRC
pre-entry rejection/rollback and unchanged legacy ABI 2.0 admission in both
Screen 6 and Screen 7. The known unrelated Notepad opening test is not claimed
fixed. MSX module SHA-256 before/after extraction:
`57a88b26c3f5608f6f738770ed505e06cc84e875b1f652166e35756d3a577977`.

1984 executable SHA-256:
`0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`.
Positive M4 image SHA-256:
`3376aba83359fca2617933fc7c891c869d2ecfd8c4a85110c245a4054773198e`.
Final framebuffer SHA-256:
`b2ab81149176edcf76462babc9d6daa479b5e09d4e58aea698479f44345e169a`.

## Reproduce

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-loading-1984
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant loading-bad-admission
```

Build-only: `make diagnostic-cpc-loading` in the container. Media are in
`QA/Diagnostics/CPC-production/loading/{CARD,ADAPTERS.IMG,manifest.json}`.
Runtime uses a private image copy and prints its `/tmp` artifacts. Never use
the parked `QA/CPC` tree or floppies for this checkpoint.

## Still required

Next: bind shared filesystem-context policy and required M4 directory/read
operations, then finish budgeted public API/sysinfo/module composition. Join
loaded applications to the shared loop and prove the first unchanged SDK
window before Desktop/FileManager and application parity.

Loading remains synchronous/IRQ-excluded like the reference MSX transaction.
This does not qualify real GUI/file latency; software ticks omit IRQ-masked
loader time. Menu/bar definitions, themed graphics/services, full placement
and responsiveness remain open. The previously recorded MSX legacy Notepad
shell-service opening failure is not addressed here. #77 stays open.
