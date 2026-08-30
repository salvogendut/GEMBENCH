# GEMBENCH implementation plan

Status: **Milestones 1-16 complete; GEMBENCH-1 frozen on 2026-08-29**.

This plan turns the goals in `DESIGN-ESTIMATE.md` into staged implementation
work. The first proof of concept is expected to take approximately six to nine
weeks for one experienced developer working substantially full-time.

## Fixed decisions

- GEMBENCH targets the Omega MSX2 with 512 KiB mapper RAM.
- Screen 7 on a V9938 is the video baseline; V9958-only features are optional.
- MSX-DOS2 or Nextor provides the storage and mapper environment.
- RainBIOS is a supported firmware and validation environment.
- GEMBENCH is licensed under the BSD 3-Clause License.
- The MSX2 base visual identity uses black, white, grey, and red, with black as the
  desktop background; Screen 7 extensions must preserve those core roles.
- OpenGEM and FreeGEM are reference material only. Code, artwork, and resources
  must be independently implemented or have separately reviewed provenance.
- CPC and PCW compatibility do not constrain new GEMBENCH APIs or layouts.

## Foundation strategy

GEMBENCH preserves the complete GeoBench history rather than copying a source
snapshot or depending on an adjacent checkout. The GeoBench repository is
tracked as `upstream`, and the initial bootstrap is pinned to:

```text
6309ff3dc1414449b0234bcf7dc8a532975ade5c
```

The first merged build must behave like that GeoBench baseline on MSX2. CPC and
PCW code is retained during bootstrap so source removal cannot hide integration
regressions. Supported build and QA workflows may be narrowed after the MSX
baseline is recorded.

## Milestones

| Milestone | Scope | Estimate | Completion criterion |
| --- | --- | ---: | --- |
| 1. Bootstrap | Merge histories and reconcile builds and documentation | 1-2 days | Host checks and the unchanged MSX build pass |
| 2. Baseline (complete 2026-08-28) | Record kernel size, app headroom, mapper/VRAM use, stack, repaint, and input timing | 3-5 days | Screen 7 boots with reproducible measurements |
| 3. GBR hardening (complete 2026-08-28) | Add a binary verifier, golden files, and a target reader | 3-5 days | Z80 code safely validates and navigates the example resource |
| 4. Object runtime (complete 2026-08-28) | Implement app-linked drawing, lookup, state, and hit testing | 1-2 weeks | Box, text, and button objects work on Screen 7 |
| 5. Vertical slice (complete 2026-08-28) | Convert one representative dialog and add semantic theme roles | 1 week | Pointer and keyboard interaction require no custom object drawing |
| 6. Window kinds (complete 2026-08-28) | Add append-only flags and messages for close, maximise, move, and resize | 1-2 weeks | The kernel owns the selected window furniture |
| 7. Banking decision (complete 2026-08-29) | Prototype an auxiliary resource segment and resident renderer | 1 week | Measurements compare resident and app-linked implementations |
| 8. Review (complete 2026-08-29) | Evaluate size, responsiveness, and maintainability | 2-3 days | GEMBENCH-1 is frozen after an explicit window-ABI revision |
| 9. Resource forms (complete 2026-08-29; [#15](https://github.com/salvogendut/GEMBENCH/issues/15)) | Add checkbox/radio rendering, common form behavior, and a production resource panel | 1-2 weeks | FormRef exercises shared semantics and Calculator draws/routes its MSX2 panel from GBR |
| 10. Resource menus (complete 2026-08-29; [#17](https://github.com/salvogendut/GEMBENCH/issues/17)) | Generate menu labels, actions, state, and shortcuts from GBR source metadata | 1 week | File Manager's MSX2 View popup is resource-driven; pointer and keyboard traces pass without changing GBR1 |
| 11. Multi-event subscriptions (complete 2026-08-29; [#19](https://github.com/salvogendut/GEMBENCH/issues/19)) | Add bounded, opt-in keyboard, pointer, timer, and WM aggregation | 1 week | Clock consumes combined event records; host and openMSX interaction traces pass without changing GEMBENCH-1 |
| 12. Visible-region repainting (complete 2026-08-29; [#21](https://github.com/salvogendut/GEMBENCH/issues/21)) | Subtract opaque higher windows with a fixed-capacity, app-linked iterator | 1 week | Desktop redraws less covered area; deterministic fallback, host geometry, openMSX overlap, and portable builds pass without changing GEMBENCH-1 |
| 13. Typed clipboard/scrap foundation (complete 2026-08-29; [#23](https://github.com/salvogendut/GEMBENCH/issues/23)) | Add bounded text, bitmap, icon, and file-list identities over the existing shared clipboard | 1 week | Typed and raw callers interoperate; mismatch/truncation tests, two-window openMSX interaction, and portable builds pass without reducing the 510-byte raw payload |
| 14. Shell services and application messaging (complete 2026-08-29; [#25](https://github.com/salvogendut/GEMBENCH/issues/25)) | Add live service discovery and synchronous open, activate, close, and quit requests | 1 week | File Manager safely reuses and activates a live Notepad, preserves launch fallback, and host/openMSX plus portable builds pass without changing GEMBENCH-1 |
| 15. On-demand Desk accessories (complete 2026-08-29; [#27](https://github.com/salvogendut/GEMBENCH/issues/27)) | Generate a bounded Desk catalog and add exact accessory identity over the live shell table | 1 week | Clock and Calculator launch only when selected, exact selection raises the correct live instance, close releases its page, and relaunch works without historical `.ACC` parsing or a process table |
| 16. VDI-lite resource graphics (complete 2026-08-29; [#29](https://github.com/salvogendut/GEMBENCH/issues/29)) | Add caller-owned semantic drawing contexts and explicit GBR ICON/IMAGE raster bindings | 1 week | Settings uses the compact MSX2 profile; malformed/size/ownership tests, openMSX interaction, 1983 boot, and portable builds pass without changing GBR1 or resident jumps |

## Bootstrap work package

The bootstrap branch must contain only foundation work:

1. Preserve the GEMBENCH and GeoBench histories in one repository.
2. Keep the GEMBENCH README, design estimate, BSD licence, and resource tooling.
3. Keep the GeoBench runtime, application sources, assets, and build system.
4. Integrate GBR host tests into the normal validation entry point.
5. Document the upstream URL and exact imported commit.
6. Build the current MSX distribution without GEMBENCH runtime changes.
7. Record any baseline failure rather than fixing unrelated GeoBench behaviour
   during the history merge.

### Bootstrap acceptance checklist

- [x] Both parent histories are visible from the bootstrap merge.
- [x] `make check` includes the GBR compiler tests and passes.
- [x] The GeoBench MSX distribution builds from the merged tree.
- [x] Screen 7 remains the staged default.
- [x] The upstream commit and reproduction commands are documented.
- [x] Generated build products and local emulator dependencies remain ignored.
- [x] No OpenGEM or FreeGEM implementation code or assets are imported.

## First implementation slice after bootstrap

The first runtime slice is deliberately smaller than the complete GBR draft:

1. Validate the 24-byte header, section offsets, counts, and checksum.
2. Resolve a tree by name or index.
3. Navigate parent, first-child, and next-sibling object indices.
4. Draw box, text, and button objects through existing Screen 7 primitives.
5. Find the deepest selectable object at a pixel coordinate.
6. Toggle selected, disabled, and outlined state bits.
7. Rebuild the reusable FormRef dialog from a `.GBR` resource.

The initial renderer remains app-linked. A resident renderer and auxiliary
mapper-backed resource storage are measurement tasks, not assumptions baked
into the first ABI.

## Measurement gate

Before freezing any ABI, record at minimum:

- resident kernel bytes before and after each runtime addition;
- code and data headroom in the migrated application bank;
- mapper segments held at idle and while the resource dialog is open;
- stack high-water mark during nested resource drawing and callbacks;
- VRAM used for resources, save-under data, and caches;
- full and damage-limited repaint times on V9938 timing; and
- pointer and keyboard response while multiple applications are resident.

The proof of concept succeeds when the migrated dialog is materially easier to
maintain or smaller, remains responsive at approximately 3.58 MHz, and does not
consume unacceptable resident or mapper capacity.

The completed pre-runtime snapshot is recorded in [BASELINE.md](BASELINE.md).
Static sizing, guarded 1983 boot telemetry, and diagnostic-only stack, repaint,
pointer, and keyboard probes are reproducible. openMSX supplies the authoritative
input and repaint reference measurements, while 1983 remains the automated
integration target. Milestone 3 added strict canonical host validation, a golden
resource and corruption corpus, and an allocation-free target reader that SDCC
currently compiles to less than 4 KiB with no static data. Milestone 4 adds an
app-linked box/text/string/button renderer, caller-owned state overlays,
deepest-selectable-object hit testing, and a File Manager-launched external
`HELLO.GBR` demonstration. The object runtime also compiles below its 4 KiB
code budget with no static data. Milestone 5 adds shared semantic pen roles,
field rendering, live caller-owned text bindings, cyclic keyboard focus,
deterministic generated C identifiers, and a GBR-driven MSX2 FormRef dialog.
CPC and PCW retain their prior FormRef implementation and binary sizes.
Milestone 6 preserved the 12-byte managed-window descriptor, prototyped a tagged
MSX2-only kind tail and append-only geometry messages, and moved selected
furniture plus maximise, move, and resize gestures into the resident kernel.
File Manager is the representative migration: its MSX2 image shrank from
14,645 to 13,244 bytes while the Screen 7 kernel grew by 768 bytes to 12,260.
Milestone 7 added a safe, opt-in MSX2 auxiliary-segment transport and split the
renderer at the proposed resident boundary. The banked FormRef path is behaviorally
equivalent, but grows the app to 15,912 bytes, adds 256 resident bytes, holds one
mapper segment, and leaves only 216 bytes of loader headroom. The complete 6,242-byte
resident candidate cannot fit the banked kernel's 3,868-byte resident gap. The
first ABI therefore keeps small GBR resources embedded and rendering app-linked;
the measurements and reproduction commands are recorded in
[M7-BANKING-DECISION.md](M7-BANKING-DECISION.md). Milestone 8 leaves the GBR1
file grammar unchanged and freezes all resource
constants, layouts, validation rules, and reserved type identities. It deliberately
revises the pre-freeze 14-byte window prototype: `gb_mwin_t` remains 12 bytes,
while the MSX2-only `gb_mwin_kind_t` is now a 13-byte descriptor registered through
`gb_wm_managed_kind()`. The distinct entry point passes an explicit selector through
the existing kernel slot, so a legacy registration never reads beyond byte 11.
The authoritative manifest is `abi/gembench-v1.json`, checked by
`make gembench-abi-check` and `make check`; the compatibility rules are recorded in
[ABI-V1.md](ABI-V1.md). The release MSX2 kernel sizes remain 10,682/12,260 bytes,
File Manager grows five bytes to 13,249, and the complete MSX2, CPC, and PCW
distribution builds pass. openMSX passes the FormRef and explicit-window logic
traces, and 1983 reaches the healthy Screen 7 desktop at frame 6,001.
Milestone 9 completed the shared checkbox/radio form policy and migrated the
MSX2 Calculator panel. Milestone 10 keeps GBR1 frozen: source-only shortcuts and
object IDs generate a bounded `GBRM` application descriptor, while live menu
state remains caller-owned. File Manager is the first production menu slice on
MSX2; CPC and PCW retain `gb_doc` after their 16 KiB fit gate rejected the added
runtime. Milestone 11 adds an app-linked multi-event adapter without a resident
queue, kernel slot, or low-RAM cell. Its caller-owned subscription and result
occupy 6 and 9 bytes; pointer motion and timer expiry coalesce into the current
callback record, and at most one key is consumed per frame. The runtime compiles
to 860 bytes, and the migrated MSX2 Clock grows from 10,112 to 11,288 bytes.
The current SDCC output uses at most 31 additional stack bytes below
`gb_event_collect()` entry while sampling the leaf input accessors. Screen 6/7
kernels remain 10,682/12,260 bytes. CPC and PCW build the unchanged legacy Clock
event path and do not link the adapter.
Milestone 12 similarly stays outside the resident kernel and frozen ABI. The
MSX2 Desktop owns a 40-byte, four-rectangle iterator, subtracts higher opaque
windows from its active damage rectangle, and atomically restores the original
single clip if capacity or window identity is ambiguous. The helper compiles to
1,581 bytes with no static data. In the reference move, 3,472 of 12,320 damaged
byte-column/line cells remained visible, so 8,848 cells (71.8%) were skipped.
openMSX observed a 70-byte maximum stack delta below `gb_visible_begin()`, a
4.973 ms calculation, clean move/top/close captures, and a final one-window
Desktop. Screen 6/7 kernels remain 10,682/12,260 bytes; CPC and PCW retain the
legacy Desktop callback.
Milestone 13 preserves the exact `gb_clip_*` storage contract and its 510-byte
payload. MSX2 adds one private type byte at `0x133D`; raw writes clear it, typed
writes publish it only after the complete payload, and unknown or stale values
normalize to untyped. The full app-linked API compiles to 552 bytes with no
static data. Notepad uses a 100-byte set/type adapter because its 4 KiB document
buffer leaves only 11 bytes between loaded code and data after integration; its
image grows by 122 bytes to 12,097. The Screen 6/7 kernels remain
10,682/12,260 bytes. A disposable openMSX image launches two independent
Notepads and proves typed copy, atomic bitmap rejection, and typed text paste.
Mapper-backed payloads were deferred here because the original mapper allocator
was tied to application-window ownership. Architecture Milestone 1 in issue #31
subsequently adds lifecycle-neutral owned pages on MSX2; typed scrap still waits
for a bounded cross-page transfer/message contract before using them.
Milestone 14 adds the first bounded desktop service without a process table or
queue. A live MSX2 window advertises one coarse class in three previously unused
private window-flag bits; top-to-bottom discovery returns a short-lived opaque
handle, and one guarded synchronous dispatch raises/maps the target, calls its
existing window procedure, restores the caller bank, and repaints. Open,
activate, close, and quit have explicit result values; an editor that is busy or
dirty rejects replacement atomically. File Manager now asks a live text editor
before checking the mapper-page limit, while absence retains the existing
Notepad launch path. The release Screen 6/7 kernels grow by 256 bytes to
10,938/12,516 bytes and use one private MSX low-RAM guard byte. File Manager is
14,506 bytes; its request helper and client binding are 27 and 16 bytes.
Notepad's registration binding is five bytes, and the app remains a full 4 KiB
editor at 12,070 bytes after applying its existing size optimisation to helper
units. The openMSX trace observed a
four-byte stack delta from `GB_SHELL` entry to the Notepad procedure, one
delivery, unchanged window count, caller-bank recovery, and the requested
second document. The extension is MSX2-only and append-only: GBR1, the 12/13-byte
window descriptors, all old jump addresses, and CPC/PCW behavior remain intact.
Milestone 15 builds on that service without turning it into a process manager.
`apps/desktop/accessories.json` has a fixed capacity of four and currently emits
two stable entries, Clock ID 1 and Calculator ID 2. The MSX2 Desktop adds the
generated Desk popup, asks for an exact live ID before checking page capacity,
and launches the catalog's normal `.APP` only when no provider exists. Exact
registration and lookup append operations 3 and 4 to the existing `GB_SHELL`
jump. An explicitly registered accessory stores its nonzero ID in byte 10 of
its already private per-window launch argument after startup has consumed that
argument; ordinary services and document names are not changed. No low-RAM
cell, queue, process record, permanent mapper page, `.ACC` parser, or frozen
descriptor field is added.

The generated catalog is 2/4 entries. Desktop is 14,679 bytes with nine bytes
between loaded image and data and 1,082 bytes below its preemptive stack reserve;
Clock is 11,377 bytes and Calculator 12,048. File Manager and Notepad remain at
their Milestone-14 sizes of 14,506 and 12,070 bytes because accessory adapters
are separate opt-in objects. The accessory request, exact-find, and
exact-register adapters compile to 21, six, and six bytes. Exact registration
needs at most six stack bytes below `GB_SHELL` entry and exact lookup two;
synchronous delivery is the unchanged Milestone-14 send path. Screen 6/7
kernels are 11,194/12,772 bytes, one 256-byte resident allocation step above
Milestone 14. The openMSX lifecycle trace observed IDs `1 2 1`, five exact
finds, two sends, a maximum of three live windows, a one-page drop on Clock
close, restoration on relaunch, and a cleared dispatch guard.

Milestone 16 returns to GEM's graphics-device separation without introducing a
resident VDI. `gbvdi` is an app-linked, caller-owned clip and four-role pen map
over the existing drawing ABI. The full profile provides bounded fill, frame,
packed four-bit raster, and aligned text; a compact base profile exposes only
direct semantic fill/frame for code-tight applications. GBR ICON and IMAGE use
their frozen 16-bit `spec` as an application binding identity. Pixel storage,
mapping lifetime, and the binding table remain outside GBR1 and under the
caller's ownership.

Settings is the representative production migration. Its MSX2 colour editor
uses the compact profile and, in preemptive builds, now remains ordinary
managed-window state instead of entering a nested polling loop. CPC keeps its
native colour primitives, PCW keeps its monochrome panel, and cooperative
builds retain the existing modal implementation. No resident kernel entry,
low-RAM cell, mapper owner, GBR byte, or frozen window field is added.

The compact/core/raster/text/assembly-call profiles compile to
586/1,137/1,078/579/12 bytes, and the graphics-enabled GBR object runtime is
4,747 bytes. The migrated MSX2 Settings image is 15,276 bytes, leaves 148 bytes
between loaded initializers and data and 852 bytes below the loader guard, and
does not change the 11,194/12,772-byte Screen 6/7 kernels. openMSX observed one
editor draw with exact VDI arguments, live state, the expected three-window
z-order, and a clean Screen 7 capture. The complementary 1983 run reached frame
6,002 with the Screen 7 register baseline intact. CPC Albireo/M4 card plus
floppies and all three PCW disks also build successfully.

Architecture Milestone 2 in issue #32 implements the next SymbOS-review slice
on MSX2 only. The eight Milestone-1 owners are now application records with a
primary code page, live-window count, primary/worker slots, lifecycle flags,
and application-owned shell/accessory metadata. The frozen eight-entry window
table gains only parallel application and generation arrays in fixed page-3
RAM. `GB_APP` is appended at `0x80CC`; generation-tagged window close/check,
free-slot/count queries, bounded windowless publication, application quit, and
resident outline drag are opt-in through `SYS=1`. Sysinfo keeps its 20-byte v1
prefix and appends a four-byte v2 application-capacity suffix.

The in-tree MSX2 Paint is the production migration: Toolchest, Preview, and
Canvas are three real compositor windows sharing one application/code page.
Canvas closes alone, document close removes Preview/Canvas and its document
page, and Quit releases the remaining Toolchest and owner. Moving the shared
drag engine resident makes Paint 15,710 bytes, 43 bytes smaller than its
single-workspace baseline. Screen 6/7 kernels are 13,498/15,076 bytes and the
scheduler remains 503/512 bytes. The API and Paint openMSX tests validate stale
window rejection, owner/window generation reuse, three-window ownership,
independent close, document survival, application teardown, and mapper-page
restoration. CPC/PCW remain unchanged pending their planned backends.
