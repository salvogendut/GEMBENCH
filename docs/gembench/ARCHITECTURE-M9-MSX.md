# Architecture Milestone 9: visibility-aware compositor and scheduling

Architecture Milestone 9 makes visibility a kernel-wide MSX2 policy. It
supersedes the earlier Desktop-only `gbregion` experiment: every managed and
legacy window now passes through the same exact opaque-region compositor, and
task-enabled applications are scheduled according to the combined visibility
of all windows owned by that application.

This milestone is MSX2-only. CPC and PCW retain their existing compositor and
scheduler paths.

## Surface visibility

The compositor refreshes one state byte for every live window whenever a
repaint pass begins:

| Value | State | Meaning |
|---:|---|---|
| 0 | hidden | no pixel is visible after subtracting higher opaque windows |
| 1 | partial | some, but not all, pixels are visible |
| 2 | full | the complete surface is visible and it is not focused |
| 3 | focused | the focused surface |

`MSX_WM_VISIBILITY` stores the surface states. `MSX_TASK_VISIBILITY` begins as
a copy, then folds every window belonging to an application into the
application's designated worker slot. PAINT therefore receives one scheduling
rank derived from Canvas, Toolchest, Preview, and work-window visibility rather
than from only one pane.

The scheduler alternates application workers with the root task. From the root
it selects workers in this order: focused owner, fully visible owner, partially
visible owner. Round-robin order is retained within a tier. A fully hidden
visual worker keeps its saved context but is not selected, so it consumes no
application CPU until one of its windows becomes visible again. Root-owned
kernel, input, storage, network, and compositor services remain runnable.

## Exact visible damage

The fixed-RAM engine intersects the source damage with each target surface and
subtracts every higher opaque rectangle. It splits at higher-window top and
bottom edges, then emits maximal uncovered horizontal runs in each band. The
representation has no rectangle pool, allocator, overflow fallback, or
whole-window escape path. A fully covered target produces no callback and no
VDP operation; a partially visible target receives one callback per disjoint
visible fragment with the ordinary clip installed.

This policy is global. Applications do not opt in or link compositor code.
Existing repaint callbacks continue to draw through the normal clipped drawing
primitives. The old `gbregion` library remains source-compatible for historical
clients and host tests, but the release Desktop no longer links or invokes it.

Two common window-manager operations receive tighter source damage as well:

- A move uses the bounding envelope of its old and new rectangles. Window drag
  feedback is a destructive outline: each intermediate outline is erased with
  the backdrop pen. The envelope therefore repairs the route between the
  endpoints as well as the old and new window footprints.
- A focus change uses the complete old and new focus rectangles as two source
  regions. Their overlap is subtracted once, then both are clipped against the
  post-focus stack. Both windows therefore redraw active/inactive furniture and
  content immediately, while unrelated areas between disjoint windows remain
  untouched. Desktop is omitted when it is one endpoint.

An explicit `gb_wm_damage()` replaces pending geometry damage. This preserves
intentional whole-window or whole-screen operations such as initial paint,
fullscreen transitions, document replacement, and palette/theme changes while
preventing stale move/focus regions from leaking into a later pass.

## Background timers and the pointer

The Milestone 8 timer collector validates both the source surface and the exact
component damage before entering the compositor. If the component is entirely
occluded, the request is acknowledged through `MSX_TIMER_DROPPED` and cleared
without a draw callback. Clock advances only the snapshots corresponding to
that component, so another independently visible component can be considered
on the next worker slice. A later ordinary exposure reconstructs the face from
the current time; hidden ticks are not replayed.

MSX uses hardware sprites for the pointer. The compositor holds the normal
paint lock but does not erase, save, restore, or redraw the sprite for every
fragment. Consequently small Clock updates do not make the pointer flash.

## Fixed-RAM placement

The Screen 7 child COM was nearly full before this work. The geometry and
scheduling engine therefore lives in the app-carried page-3 scheduler image at
`0xC900-0xCEFF`; `MSX_APP_FIXED_BOTTOM` moves to `0xCF00`.

| Range | Purpose |
|---|---|
| `0xC1C0-0xC1C7` | per-surface visibility |
| `0xC1C8-0xC1CF` | owner-aggregated task visibility |
| `0xC1D0-0xC1E7` | band iterator and classifier scratch |
| `0xC1E8-0xC1EB` | immutable primary damage |
| `0xC1EC` | fully occluded timer acknowledgement |
| `0xC1ED-0xC1F3` | exact secondary source and iterator state for focus unions |
| `0xC1F4-0xC1F7` | available fixed-RAM bytes |
| `0xC900-0xCEFF` | 1.5 KiB scheduler/compositor slot |

The normal scheduler is 1,448/1,536 bytes. The diagnostic baseline variant is
1,457/1,536 bytes. The release Screen 6 and Screen 7 child COMs are 14,548 and
16,126 bytes, leaving 1,580 and 2 bytes in their 16 KiB child windows.

## Application damage audit

All release applications now receive visibility clipping at the kernel
boundary. No application-specific covered-area loop remains. Damage requests
fall into three categories:

1. Component updates, such as Clock hands and seconds, request tight content
   rectangles and are skipped when that component is hidden.
2. Move damage covers the destructive drag-outline endpoint envelope; focus
   damage is generated as an exact old/new union by the window manager for every
   application.
3. Full-window or full-screen requests remain only where the operation really
   changes that complete area: first publication, resize/fullscreen geometry,
   document replacement, or global palette/theme changes.

New incremental drawing code should call `gb_wm_damage()` with the smallest
changed content rectangle before `gb_restore_parent()`. The global compositor
then further intersects that source with the exact visible region. It cannot
infer a smaller semantic change than the rectangle an application reports.

## Validation

The host reference model checks 500 deterministic random rectangle stacks
against pixel-by-pixel subtraction. It also verifies that move damage covers
every rectangle between its endpoints and that focus sources are disjoint and
equal to their exact old/new union:

```sh
python3 -m unittest tests.test_visibility_compositor -v
python3 -m unittest tests.test_background_timer -v
```

The openMSX Clock workflow verifies partial occlusion, full occlusion, restore,
generation-safe timer damage, pointer stability, and task parking. Its fully
hidden phase records zero worker, draw, and damage deltas and a bit-identical
foreground hash. The PAINT workflow verifies three independent pane moves,
clean old positions, and complete old/new pane repaint callbacks at every
focus change:

```sh
OPENMSX='distrobox enter my-distrobox -- openmsx' \
  MSX_HEADLESS=1 tools/test_multi_event_openmsx.sh
OPENMSX='distrobox enter my-distrobox -- openmsx' \
  MSX_HEADLESS=1 tools/test_m2_paint_openmsx.sh
```

`tools/test_visible_regions_openmsx.sh` remains as the compatibility entry
point and runs both global compositor workflows.
