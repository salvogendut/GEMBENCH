# CPC graphics and caller-parameter proof

Date: 2026-09-05. Issue: [#66](https://github.com/salvogendut/GEMBENCH/issues/66),
following package 3A under [#65](https://github.com/salvogendut/GEMBENCH/issues/65).
Branch: `feature/66-cpc-graphics-foundation`, based on `f3c779a`.

The hardware/proposed-calling-boundary fixture is implemented. **Full step 3B
is still open:** the public universal ABI, SDK and MSX2 runtime have not adopted
this mechanism. No production code, application, capability or release media
is changed. This is not a CPC desktop, application loader or second UI policy
implementation.

## What is reused and what is new

`graphics_driver.asm` adapts the Mode-1 address calculation, byte-fill/copy
loops, and interleaved mask/data pointer composition from `lib/screen.asm` and
`lib/cursor.asm` at archived CPC commit `56478578`. Canonical four-pen packing
is unchanged: pixel 0 uses bits 7/3, pixel 1 bits 6/2, etc. There are 80 byte
columns by 200 lines.

The adapter removes the old helpers' implicit ROM toggling and unconditional
EI. Bounds, scratch ownership and entry state are explicit. The pointer uses
all four subpixel phases and top-down pixel coordinates; it does not inherit
the old firmware-coordinate conversion or two-phase aliasing. Its small 8x8
shape is diagnostic data, not a new project cursor asset.

Clipping handles zero extents, fully offscreen rectangles, partial overlap and
overflowing 8-bit endpoints. Save/restore packs only the clipped intersection,
row-major, with no screen stride in the buffer. Pointer show/hide are
idempotent; moves restore the old background. A draw intersecting the saved
pointer rectangle hides it, updates content, then re-saves/re-shows once.
Unrelated drawing does not touch pointer save-under at all.

## Prototype calling contract

This is a private diagnostic entry, **not** a new `GB_*` slot or final public
descriptor schema. It tests the mechanism proposed in step 3A:

- HL points to a 16-byte caller-owned record; BC must equal 16. The complete
  span must lie in `4000..7EFF`; wraparound and crossing `7F00` are rejected.
- Copy the complete record into guarded fixed RAM **before** replacing the
  caller's page. The fixture then maps an unrelated, poisoned F7 page while
  executing the operation.
- Restore input bytes are copied into bounded resident staging before that
  switch. Save output bytes are copied to the caller only after restoring its
  page. No application pointer is read while the service page is mapped.
- Save/restore has a 64-byte staging limit. Validate both actual clipped byte
  count against supplied capacity and the actual caller-buffer span. Empty
  intersections are no-ops and do not access a buffer. No zero-count LDIR runs.
- Return A=status: 0 success/no-op, 1 invalid descriptor span/length, 2 unknown
  operation, 3 invalid pen, 4 invalid buffer/pointer-coordinate range, 5 transfer
  capacity exceeded. Other registers and flags are volatile. Restore caller
  bank, SP and IFF on every return.
- Calls are serialized. No deferred operation or retained caller pointer is
  implemented. The entry requires Mode 1, both ROMs off, and a fixed stack;
  it does not claim to accept arbitrary ROM/video entry states.

Fixture record layout:

| Offset | Bytes | Meaning |
|---:|---:|---|
| 0 | 1 | Operation: fill, save, restore, show, move, hide = 1..6 |
| 1..4 | 4 | Rectangle x/y/w/h in four-pixel columns and lines |
| 5..8 | 4 | Test clipping rectangle x/y/w/h |
| 9 | 1 | Semantic fill pen 0..3 |
| 10 | 2 | Caller buffer pointer, little-endian |
| 12 | 2 | Caller buffer capacity |
| 14 | 2 | Pointer pixel X; pointer Y uses byte 2 |

The clipping rectangle is **test input**, not an application authorization
boundary. In production the shared compositor must supply/enforce visible
regions; an application must not enlarge those regions with a descriptor.
Likewise, "caller-owned" here means data in the mapped application page, not
an automatic array on an arbitrary kernel-owned stack. SDK adoption must
provide suitable per-application storage or explicitly validate an additional
owned stack range; accepting all fixed RAM is not a safe replacement.

## Isolated memory and execution

The probe retains step 3A's M4 boot, one firmware mode-set call, takeover,
fixed 256-byte foreground and interrupt stacks, guarded layout, and DI/HALT
completion. The interrupt handler runs on its own stack and only increments
a counter; it does not draw or switch pages. Step 3A separately proves bank
restoration by an interrupt that does switch pages.

Changes/additions to the [3A map](CPC-RESTART-STEP3A.md):

| Region | Use |
|---|---|
| `8000..97FF` reservation | Probe/gate/driver, input vectors and pointer tables; 2,874 bytes used |
| `9800..9871` | Fixed control state and a guarded 16-byte copied descriptor |
| `9900..996B` | Pointer save/restore counter trace, outside screen RAM |
| `9D30..9D67` | Guarded 24-byte pointer background buffer |
| `9D80..9DDF` | Guarded 64-byte transfer buffer |
| Main page, `4000..7FFF` | Test caller data; descriptors at `4000` and `7EF0`, save buffer at `4100` |
| Expansion pages C4..EF | 24 full 16-KiB framebuffer checkpoints from the final round |
| Expansion page F7 | Poisoned service page, checked unchanged afterwards |
| `C000..FFFF` | Display RAM only, including all 384 raster-gap bytes |

The raw load image is 7,648 bytes including padding, state and guards. Its
end is `9DE0`, below the reserved firmware workspace. Assembly assertions
check code/state/trace/stack/buffer bounds and prevent capture pages from
overlapping F7. These are fixture reservations, not a full desktop memory
budget.

## Run and verify

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-graphics-1984
```

This uses the same builder/harness as 3A, with a separate `graphics` variant.
Its generated card and image are under
`QA/Diagnostics/CPC-foundation/graphics/`. Every emulator launch uses a fresh
private image copy and PTY. No floppy or parked `QA/CPC/` image is used.

For a visible diagnostic-pattern run, not a desktop:

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-graphics
../1984/1984 --config=QA/Diagnostics/CPC-foundation/graphics/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

The automated test, not appearance alone, determines success. Each round
starts with a known pattern and runs 49 requests; 50 rounds check status,
bank restoration, SP balance and both enabled/disabled interrupt returns.
The last round records 24 full framebuffer checkpoints for the host's
independent pixel-level oracle. It compares every byte, including raster gaps,
plus the final framebuffer, caller page, copied buffer, service page, resident
code and all guard pairs. It checks selected pointer-operation counter traces
to catch unnecessary hide/show even when the final pixels look identical.
Framebuffer comparisons cover the last round's checkpoints, not every
intermediate instruction or every frame of all 50 rounds.

Negative runtime fixtures:

```sh
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant graphics-bad-clip
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant graphics-bad-cursor
distrobox enter my-distrobox -- python3 tools/test_cpc_foundation_1984.py --variant graphics-bad-copy
```

These succeed only when the expected defect is detected: drawing outside the
clip, re-saving an already-visible pointer, or copying the descriptor after
switching away from its page. Rejections also exercise invalid/straddling
descriptor and transfer pointers (including `C030` and wraparound), bad lengths,
unknown operations, invalid pens/coordinates, insufficient capacity and
transfers above the 64-byte staging limit. A clipped 56-byte save/restore uses
exactly 56 bytes of declared capacity and varied canonical pixel bytes.

Five new host unittest methods cover assembly/fault bounds, cursor-phase
decoding, the oracle and checker mutations. Synthetic snapshots test the host
checker only, not emulated CPU execution. Actual execution uses local 1984,
CPC 6128, 512 KiB and M4. No physical CPC or other emulator result is claimed.

## Recorded results

The final positive M4/1984 run passed: 50 rounds, **2,450 requests**, 24 exact
framebuffer checkpoints, 56 canonical saved bytes, intact resident code and
all guards. It observed 1,753 interrupts (the exact count varies because
interrupt-enabled calls can also be interrupted before/after their critical
section). Foreground/interrupt stack sentinel footprints were **16/256** and
**4/256 bytes**, respectively. Sentinel measurements are lower bounds for
this fixture, not production stack budgets. The last-round pointer counters
were nine saves and nine restores, with unchanged counters for duplicate
show/hide and unrelated drawing.

The three final negative runs all rejected the intended fault:

- ignored clipping: wrong byte at `C000` in `left-top-clip`;
- duplicate pointer save: stale byte at `C800` in `phase-1`;
- copy after bank switch: wrong returned request status, fixture failure 8.

The existing 3A runtime probe was re-run through the extended builder/harness
and passed with 1,450 interrupts; its raw hash remains exactly
`5ccdaf35f5142ac2d4a51648f6a99b6df0f14766f2d0cba256c586194105ada0`.

Positive graphics artifacts are in `/tmp/geobench-cpc-foundation-_b6aupe0/`:
`result.json`, emulator log, snapshots, screenshot and the image actually
booted. Graphics raw SHA-256:
`e722d7b4235241717e6d6124c51b62a1cf19684389d982abe589907b0ed2232e`.
Booted image SHA-256:
`3db72769a7241eec300b40fe8d197f2275b16828d8b2fcff09eb1301cf493f5b`.
Emulator SHA-256:
`0da2546308cd8e61ace50d55d1cc2b2dfb64fd3d13998dddf635a1265fba169d`.
The negative artifact-directory suffixes are `24zmk51c`, `a_ywjkan`, and
`pp6ow5dr`; the 3A recheck suffix is `kuqmbebg`. These are disposable local
evidence, not build dependencies. Commands above regenerate the evidence;
FAT timestamps can change image hashes without changing the raw executable.

## Remaining integration gates

The experimental ABI still exposes MSX-specific `C030`, `C039`, `C1EC` and
`C3CA` cells. This proof does not modify or legitimize those addresses on CPC.
Production adoption must update ABI authority/version/admission rules, SDK,
MSX2 service implementation and rebuilt universal applications together,
preserving the frozen GEMBENCH-1 contract and explicitly handling old GBAP v4
artifacts. Line/text parameters, pointed-to text data, and asynchronous timer
ownership/lifetimes must be covered, not just these rectangle fixtures.

The Screen-7 child COM has only two bytes of headroom in the current reference
build. Budget and locate the service/gate with the remaining step-2 resident
core work before appending production code; do not squeeze it in by removing
guards or borrowing screen RAM. The fixture's code and stack measurements
are not production cost estimates. Holding DI through a primitive here is
also not a validated desktop latency policy.

Runtime M4 transfers/failure returns (3C), real input acquisition, full
line/text rendering, and shared window/focus/damage/scheduling integration
remain unproved here. None of the universal applications is enabled on the
CPC release path by this package.
