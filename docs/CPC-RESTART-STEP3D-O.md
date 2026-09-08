# Restart step 3D-O: shared accessory service and unchanged Calculator

Date: 2026-09-06. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`. Follows
[3D-N shared Desktop bar/menus](CPC-RESTART-STEP3D-N.md).

Status: **Calculator runs unchanged on CPC/M4, with exact accessory discovery,
deferred activation, menu/input/drag support and owner cleanup**. The complete
Desktop and its Desk menu are not enabled yet. Clock remains gated pending
its real worker/background-timer integration.

## Shared code and CPC bindings

`kernel/core/shell_service.asm` extracts the existing MSX shell dispatcher,
registration and synchronous delivery around the already-shared service lookup.
Only two MSX storage names become their existing `CORE_*` equivalents; machine
instructions and MSX addresses are unchanged. CPC links this same code and
binds `GB_SHELL` at `80C0`. Its provider uses native fixed low RAM for the busy
guard (`133E`) and 11-byte synchronous argument (`1423..142D`), outside the
framebuffer. A small CPC entry guard rejects worker calls as busy. Registration
retains owner-level service/accessory identity and the native window mirrors.

The only added low-word capability is the frozen `shell` bit `0008`:
`0F83 -> 0F8B`. The ABI version and jump-table positions do not change. The
native page allocator, legacy filesystem, resources and background-timer
capabilities remain gated. Calculator's manifest and source are untouched.

`apps/desktop/core/accessory_open.inc` is the existing Desktop activation code.
It first discovers the exact generation-tagged accessory owner, queues an
activation if present, and only checks capacity/launches when absent. A failed
send is not treated as absence. Both the real MSX Desktop and the temporary CPC
root binding compile this fragment with the same generated accessory catalog.
The Desktop build cache now tracks it.

The CPC runtime's F7 test control calls that shared code in root C0. Its local
capacity leaf checks window slots and free pages; the not-yet-linked UI's
full-capacity indication is a private status byte. This is a service integration
control, not a second Desktop or a replacement Desk menu. Root state is explicitly
zeroed once at boot, separately from bar invalidation during repaint.

The deferred-message provider previously allowed six-byte send records only in
the APP aperture. The unchanged Desktop code uses a normal C stack local. CPC
now admits complete spans in `3510..360F` as well as `4000..7EFF`, after the
existing root-context check. The last valid starts are `360A` and `7EFA`.
Guard crossings, IRQ/temporary stacks and wrapping addresses remain invalid;
callback pointers still require executable APP memory below `7F00`. No shared
queue/owner policy or MSX validation instruction changes.

The private launcher reserves F3..F7 from ASCII input too, including their CPC
keypad aliases. Thus F7 does not type an unwanted `7` into Calculator before
activating it. The main keyboard number row remains usable. These diagnostic
reservations are not a proposed keyboard policy for the final Desktop.

## Executable identity and budgets

The M4 builder uses the existing MSX Calculator profile:
`UNIVERSAL_WINDOW_KIND=1 UNIVERSAL_ACCESSORY=1 UNIVERSAL_MENU=1 DATA_LOC=0x7600`.
The actual loaded `CALC.APP` is **7,825 bytes**, SHA256:

`5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5`

This matches the MSX release APP byte for byte. No platform define, weaker
manifest or CPC-specific Calculator implementation is used.

| Allocation | Used | Budget |
|---|---:|---:|
| Resident kernel, including root helper reservation | 12,900 | 16,384 |
| Bar/accessory root helper within that total | 927 | 1,536 |
| Root C0 helper state | 13 | 32 |
| Low support | 1,832 | 3,072 |
| Hardware leaves | 1,130 | 1,536 |
| Scheduler | 1,437 | 1,536 |
| F7 filesystem module | 4,502 | 7,168 |

The main stack remains 256 bytes. The Calculator run observes **103 bytes**
maximum use, IRQ 4, temporary 0, with all guards intact. The filesystem regression
still reaches 127 bytes. Root-helper padding is included in the resident total.

## Validation

- Nineteen exact-framebuffer M4 checkpoints: ordinary APP, Calculator launch,
  pointer/keyboard `72 + 3 = 75`, repeated activation, focus away/return,
  Edit popup/cancel/clear, title dragging and continued input, full window table,
  activation while full, teardown and fresh-generation relaunch.
- The run checks the loaded APP bytes, window geometry/z-order, service class,
  exact ID, deferred sender/receiver/payload, the actual C-stack request pointer,
  drained FIFO, immutable code/font/module bytes and stack/bank/mode invariants.
  Its read-only M4 image is unchanged. The pixel oracle independently constructs
  all twenty button labels, display, furniture, menus and exposed surfaces.
- The existing ten menu checkpoints, eleven ordinary window checkpoints and
  46 portable-filesystem checks pass on the same composed image.
- The 16-checkpoint M4 deferred/timer fixture passes with six added invalid
  stack-span checks: below the main stack, a one-byte overrun, the stack top,
  IRQ stack, temporary stack and `FFFF`. It never writes those invalid spans.
- MSX Desktop remains byte-identical to the 3D-N baseline: 15,144 bytes,
  SHA256 `69eb5134b1326aaa42465a9c2fff94eaf522d286cf60a62d3b9cc89327baf302`.
  The Screen-7 kernel is likewise unchanged: 15,534 bytes,
  SHA256 `fd2503a22c56cde6d5de53e916058eead5906d06f6571ac722521620928e9b4d`.
  Build profiles are recorded in 3D-N. The existing MSX Desk/Clock/Calculator
  reference regression passes in openMSX Screen 6 and 7 using private disk copies.
- Full `make check` passes in an isolated worktree: **208 Python tests without
  skips**, plus native C, ABI/SDK and distribution checks. New host tests execute
  the actual Desktop fragment for exact identity, full capacity, failed send,
  normal launch and out-of-range catalog index.

Logs: `/tmp/geobench-77o-{accessories-final,services,menus,runtime,fs}.log`,
`/tmp/geobench-77o-desk{6,7}.log`, `/tmp/geobench-77o-check.log`,
`/tmp/geobench-77o-{desktop,kernel}.log`. Emulator: the existing 1984 main
`0851004`, executable SHA256
`00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`.
No emulator changes, floppy tests, guest RAM injection or release MSX media
updates were needed. The user-owned `QA/CPC/` tree is preserved.

The Calculator scenario exercises registration/discovery and **deferred**
activation. Binding the unchanged synchronous shell dispatcher is not a claim
that full document handoff between CPC File Manager and editors is qualified;
those native application workflows remain in the Desktop/application gates.

## Manual test

The current private M4 image is rebuilt. From the repository:

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Press **F7** to open Calculator. Use arrows and Space to operate its buttons,
or the main number row for numeric entry. Try its `Edit > Clear` menu. Hold
Space on the title while moving the pointer to drag it. Focus ABI Probe, then
press F7 again: the same Calculator should return with its value retained.
Escape closes it; F7 then opens a fresh instance. F6 still opens the menu probe.

Rebuild/automate using the installed toolchain:

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-accessories-1984
```

`make diagnostic-cpc-runtime` builds without running the automated test.
Media remain under `QA/Diagnostics/CPC-runtime`, not the old CPC distribution.

## Next

Follow-up: [3D-P](CPC-RESTART-STEP3D-P.md) now implements and tests the Clock
integration described below; this document retains 3D-O's historical budgets
and binary identities.

Connect the existing Clock worker and shared timer collector to this same
composed runtime; prove focused/partial/fully covered behavior, cleanup and
exact reactivation before advertising `background-timers` or staging Clock.
Then continue the real Desktop's root/UI, assets and File Manager bindings.
The full production-adapter gate (#77), Desktop integration, Albireo qualification
and wider application parity are still open; PCW is not enabled.
