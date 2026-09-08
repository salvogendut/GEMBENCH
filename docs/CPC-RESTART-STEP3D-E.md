# Step 3D-E: native registration and managed chrome on CPC

Date: 2026-09-06. Issue [#77](https://github.com/salvogendut/GEMBENCH/issues/77),
branch `feature/77-cpc-production-adapters`, following 3D-D at `25143e6`.
Parent: [production adapter gate](CPC-RESTART-STEP3D.md).

Status: **native registration and plain managed chrome pass on M4/1984**.
The complete production-adapter gate remains open. This is not a CPC release,
public APP loader, interactive window manager or desktop. Root/worker setup,
menu sinks and application content are diagnostic fixtures; window registration,
kind selection, borders/gadgets/title drawing, focus/damage and close are shared
production code, not a second CPC implementation.

## Implementation and boundary

Five units are extracted from the production MSX kernel and included by both
targets: `window_register.asm`, `window_slot.asm`, `managed_window.asm`,
`window_chrome.asm` and `frame_draw.asm`. Their
[native contract](../kernel/core/window_registration_contract.inc) freezes the
existing 25-byte table entry, 12-byte legacy descriptor and explicitly selected
13-byte kind descriptor. No public ABI, resource format or APP byte changes.

Registration finds a dead slot, advances its generation, copies the descriptor
and launch argument, binds owner identity, then publishes focus and z-order.
Managed registration patches the descriptor/proc/flags and publishes geometry
and initial damage without prematurely drawing empty content. A full table
does not mutate live/count/order/generation/owner state. The raw registration
entry reports NC/A=FF; the managed native entry remains a void API.

The CPC provider now binds owner identity from the **registering slot**, before
focus changes. Earlier fixture-only checkpoints used focus as their publication
source; that shortcut is not valid for actual registration. Both owners in the
diagnostic retain their original primary windows while adding/removing siblings.

The drawing provider uses existing clipped Mode-1 fill/text routines and the
shared compositor's software-pointer lock. It preserves fill inputs across
stripe rows and copies title text before mapping the font page. The proc is
called only after the caller's page is restored, with `GB_MSG_DRAW` and the
painted window's published rectangle. IRQs run during locked fills without
letting a worker switch into another app page.

Native calls still require trusted descriptor pointers, valid owners and bounded
geometry. Public admission/validation and gesture dispatch are later bindings.
The diagnostic exercises the **existing plain furniture configuration**
(`TITLEBAR_TILE=0`, `THEMED_GADGETS=0`), including title, close, maximise and
resize grip selection. It does not claim title/gadget module loading, themed
bitmap rendering, hit-driven dragging/resizing or top-bar menu integration.
The normal MSX build retains its themed configuration.

## Shared corrections

- Kind lookup now reads the **painted entry's** opt-in flag, not `WM_FOCUS`.
  A legacy background window and an explicit foreground window can have
  different descriptor contracts. Reading the focused flag could incorrectly
  consult byte 12 of the legacy descriptor, or give an explicit background
  window legacy furniture. The M4 fault variant restores the old focus lookup
  and is rejected at the mixed-kind repaint checkpoint.
- Native titles are bounded to **23 characters plus NUL**. The MSX native title
  scratch is 24 bytes, but the previous call used the generic 48-character copy.
  The shared title path now supplies the correct bound to the provider's string
  loop. A 50-character source, exact terminator and adjacent guard are checked
  on CPC execution of this shared path. The generic text service is unchanged.

Both corrections are present in the rebuilt MSX kernels. MSX runtime checks
below are existing regression scenarios, not separate executions of the exact
CPC long-title/mixed-legacy fault cases.

## M4 qualification

Sixteen checkpoints cover initial repaint, legacy registration, titleless,
title/move, standard, close-only and resize-only kinds, both full-table entry
paths, legacy focus, movement, shrink, close, cross-owner reuse of slot 5,
tiny background-title damage and final sibling cleanup. Both C0 and C4 caller
pages contain real callback trampolines; the fixture validates mapped page,
message and published rectangle before drawing a small content mark.

An independent host model constructs per-surface pixels, then resolves topmost
ownership by brute force. It checks all sixteen full framebuffers (including
raster gaps), native records/procs/flags/arguments, owner links and counts,
generation advancement, publication damage, callback visibility, live z-order,
page accounting and final cleanup. Common checks cover linked code, font,
stack/state guards, pointer state, bank/ROM/IFF, real M4 bytes and keyboard/IRQ
activity, and 150 additional frames of stable RAM.

One root-owned page holds sixteen 1-KiB state records; sixteen more hold
framebuffers. Nine pool pages remain free. This is diagnostic capture overhead,
not desktop RAM consumption. The final live windows are the original root and
worker; added windows are removed through the actual shared lifetime path.

| Section | Measured bytes / allocation |
|---|---|
| Shared registration/chrome/frame units | 783 |
| Complete high diagnostic payload | 13,045 / 16,384; includes fixtures, unused older vectors and font, **not full-kernel usage** |
| Low support / scheduler / hardware | 1,673 / 1,437 / 1,055, unchanged |
| Shared focus/damage / lifetime cleanup | 648 / 851, unchanged |
| New registration/chrome and fixture state | guarded `3290..33FF`, before staging/stacks |

Final positive run `/tmp/geobench-cpc-production-19bd5g_k`, log
`/tmp/geobench-77e-registration-qualified.log`: 64 root/worker/I/O rounds,
665 M4 commands, 2,207 IRQs, main/IRQ/temporary stack use 30/4/6 bytes;
shared context high-water 26. These are workload measurements, not maximum
stack or latency bounds. Final framebuffer SHA-256:
`426de03c64f0a4d957e897a9daadd07b491cd473c39c10b74eca8daa7cfa2e26`.
M4 image SHA-256:
`837b4e23c5af953881bb4c9278ee4adc4a275cb768c62fa0018af8b2cb432967`.

Fault logs `/tmp/geobench-77e-registration-bad-{kind,owner}-final.log` reject
wrong-kind furniture and wrong-slot owner binding respectively. The owner fault
also breaks later cleanup; its rejection inspects the first actual registration
trace, not a generic timeout or abort. The preceding 3D-D lifetime scenario
still passes (`/tmp/geobench-77e-lifetime.log`). No floppy boots, snapshot
injection, emulator modifications, parked `QA/CPC/` changes or Albireo claim.

## MSX and host regressions

Full `make check` passes (exit 0) in isolated worktree
`/tmp/geobench-77e-check.OdeAUK`, with final sources and refreshed MSX media:
**166 Python tests without skips**, plus native C, SDK/ABI, layout and
distribution checks. Log `/tmp/geobench-77e-make-check-final.log`.
The isolated copy excludes the user's parked untracked `QA/CPC/` directory;
the retired-target audit is unchanged. Toolchain: RASM 3.2.1 and explicit
SDCC/SDAS 4.6.2 #16671 from `../sdcc/bin`.

The MSX hard-disk image and tracked distribution artifacts are rebuilt. openMSX,
UNAPI disabled and private Nextor images, passes window-kind/geometry tests,
PAINT multiwindow focus/movement/cleanup, and Desk/Clock/Calculator borders,
menus and close/relaunch in Screen 6 and Screen 7. Logs:
`/tmp/geobench-77e-msx-{kinds,paint,desk6,desk7}-final.log`.

Kernel sizes remain 13,956 and 15,534 bytes. SHA-256:

- Screen 6: `1f8f5d37e3350a1c07a8e17df947fa95a62dc97d0c78dfad6bb6eaeddeb4d59f`
- Screen 7: `68898fb51ccb4acfca696609fbddb8b5b2aaac426d572992cb837cb0f3d9dc71`

The 1,448-byte MSX scheduler and universal ABI Probe, Calculator and Clock
binaries retain their 3D-D reference hashes. The native layout assertions
reassemble both kernels byte-identically to the already runtime-tested images.
Floppy distribution files were rebuilt/audited, not used as test boot media.

The frozen ABI audit now follows the two extracted source units and verifies
their inclusion, opt-in selector, flag and kind offset. Mutation tests still
reject unsafe descriptor changes. New host tests also cover layout drift,
deterministic assembly, capture-checker corruption and frame/damage boundaries.

## Reproduce and next work

```sh
distrobox enter my-distrobox -- make diagnostic-cpc-registration-1984
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant registration-bad-kind
distrobox enter my-distrobox -- python3 tools/test_cpc_production_1984.py --variant registration-bad-owner
```

Build only: `make diagnostic-cpc-registration` in the container. M4 card,
image and source-hash manifest are under
`QA/Diagnostics/CPC-production/registration/`.

Follow-up [3D-F](CPC-RESTART-STEP3D-F.md) now validates shared deferred-message/
timer delivery and the bounded post-input root dispatch phase. Remaining:
public APP loader/admission, input, menu/themed graphics and
filesystem-context bindings. Whole-kernel/module placement, complete fixed
state, maximum stack, IRQ-off and M4-ACK responsiveness still need qualification.
Only then advance the main roadmap to a loaded shared-core window, Desktop,
and application parity. This checkpoint does not close issue #77.
