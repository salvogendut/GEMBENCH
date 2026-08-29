# GEMBENCH implementation plan

Status: **Milestones 1-9 complete; Milestone 10 in progress; GEMBENCH-1 frozen on 2026-08-29**.

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
| 10. Resource menus ([#17](https://github.com/salvogendut/GEMBENCH/issues/17)) | Generate menu labels, actions, state, and shortcuts from GBR source metadata | 1 week | File Manager's MSX2 View popup is resource-driven; pointer and keyboard traces pass without changing GBR1 |

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
runtime.
