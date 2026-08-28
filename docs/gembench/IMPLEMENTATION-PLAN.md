# GEMBENCH implementation plan

Status: **approved for bootstrap on 2026-08-28**.

This plan turns the goals in `DESIGN-ESTIMATE.md` into staged implementation
work. The first proof of concept is expected to take approximately six to nine
weeks for one experienced developer working substantially full-time.

## Fixed decisions

- GEMBENCH targets the Omega MSX2 with 512 KiB mapper RAM.
- Screen 7 on a V9938 is the video baseline; V9958-only features are optional.
- MSX-DOS2 or Nextor provides the storage and mapper environment.
- RainBIOS is a supported firmware and validation environment.
- GEMBENCH is licensed under the BSD 3-Clause License.
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
| 2. Baseline | Record kernel size, app headroom, mapper/VRAM use, stack and repaint timing | 3-5 days | Screen 7 boots with reproducible measurements |
| 3. GBR hardening | Add a binary verifier, golden files, and a target reader | 3-5 days | Z80 code safely validates and navigates the example resource |
| 4. Object runtime | Implement app-linked drawing, lookup, state, and hit testing | 1-2 weeks | Box, text, and button objects work on Screen 7 |
| 5. Vertical slice | Convert one representative dialog and add semantic theme roles | 1 week | Pointer and keyboard interaction require no custom object drawing |
| 6. Window kinds | Add append-only flags and messages for close, maximise, move, and resize | 1-2 weeks | The kernel owns the selected window furniture |
| 7. Banking decision | Prototype an auxiliary resource segment and resident renderer | 1 week | Measurements compare resident and app-linked implementations |
| 8. Review | Evaluate size, responsiveness, and maintainability | 2-3 days | The first resource and window ABI is frozen or deliberately revised |

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

- [ ] Both parent histories are visible from the bootstrap merge.
- [ ] `make check` includes the GBR compiler tests and passes.
- [ ] The GeoBench MSX distribution builds from the merged tree.
- [ ] Screen 7 remains the staged default.
- [ ] The upstream commit and reproduction commands are documented.
- [ ] Generated build products and local emulator dependencies remain ignored.
- [ ] No OpenGEM or FreeGEM implementation code or assets are imported.

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
