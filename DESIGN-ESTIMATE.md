# GEMBENCH: GEM Ideas and Improvements for GeoBench

## Project concept

**GEMBENCH** would combine GeoBench's native Z80 architecture and existing
applications with the best architectural and graphical ideas from Digital
Research GEM.

It should not begin as a literal port of GEM AES or as an attempt to run x86
GEM binaries. The more practical goal is a native evolution of GeoBench:

```text
GEM visual language and application concepts
                    +
GeoBench Z80 kernel, mapper model and applications
                    =
                 GEMBENCH
```

The intended upstream repository is:

```text
git@github.com:salvogendut/GEMBENCH.git
```

## Fixed target

GEMBENCH targets one platform only:

- Omega MSX2
- Z80 at approximately 3.58 MHz
- 512 KiB mapper RAM
- V9938 or V9958 with 128 KiB VRAM
- Screen 7 at 512 x 212 with sixteen colours
- MSX-DOS2 or Nextor
- RainBIOS as a supported firmware and validation environment

CPC and PCW support are explicitly outside the GEMBENCH scope. Code may be
borrowed from GeoBench's portable layers, but new GEMBENCH APIs, resources,
layouts and optimisations do not need fallbacks for those machines. Screen 6
compatibility can remain useful during early bring-up, but it should not
constrain the design unless it is deliberately retained as an optional mode.

## Existing GeoBench foundation

GeoBench already implements much of what made GEM useful:

- A desktop with icons, drives, a trash can, menus and file associations
- Overlapping, draggable, resizable and co-resident application windows
- A kernel-owned window manager with focus and z-order
- Per-application menu bars
- Window draw, click, frame, close, drag and drop messages
- Common buttons, fields, selectors, sliders, scrollbars and modal forms
- Standard document File/Edit/View behaviour
- File selectors, prompts, alerts and shared dialogs
- A shared 510-byte clipboard
- Rectangle-clipped damage repainting
- Configurable fonts, icons, cursors, title bars, gadgets and backgrounds
- A stable native jump-table ABI for banked applications
- V9938-accelerated Screen 6 and Screen 7 drawing

GEMBENCH should preserve these working systems. The useful opportunity is to
make them more declarative, consistent and extensible.

## Recommended architecture

```text
GEMBENCH desktop, accessories and applications
------------------------------------------------
Object trees | Resources | Forms | Menus | Shell
Events       | Messages  | Window kinds | Scrap
------------------------------------------------
Existing GeoBench libgb and kernel jump table
------------------------------------------------
GeoBench mapper, VDP, input and filesystem backends
------------------------------------------------
MSX-DOS2 / Nextor on an Omega MSX2 with 512 KiB RAM
```

The new layer should extend the native GeoBench ABI. It should use familiar
GEM concepts without inheriting GEM's 8086 calling convention, global parameter
arrays, far pointers or binary resource format.

## Highest-value ideas to borrow

### 1. Compact object and resource trees

GEM's most valuable application-development idea is its declarative resource
tree. Dialogs, menus, icons, strings and controls are data rather than custom
drawing and hit-testing code in every application.

GEMBENCH should define a compact, bank-safe resource format, provisionally
called `.GBR`. A resource could contain:

- Object trees for dialogs, panels and menus
- Strings and editable text templates
- Native Screen 7 sixteen-colour icons and bitmaps
- Palette-role metadata for consistent themes
- Keyboard shortcuts and default/cancel actions
- Per-object flags and visual states

A compact object record could use 8-bit tree indices, 16-bit resource offsets,
8-bit vertical geometry and 9-bit horizontal pixel geometry. Approximately
12-16 bytes per object is realistic, compared with the pointer-heavy structure
used by 16-bit GEM. All references should be indices or offsets rather than live
pointers so a resource remains valid when its mapper segment is not currently
visible.

An application may own a code segment plus one or more resource segments. The
resident renderer can temporarily map a resource segment into page 1 while it
executes from the kernel in page 2, then restore the application's code segment
before returning. This turns the guaranteed 512 KiB mapper into a direct
advantage and keeps large dialogs and icons out of the 16 KiB application bank.

Suggested native operations are:

- `gb_rsrc_load()` and `gb_rsrc_tree()`
- `gb_obj_draw()` and `gb_obj_find()`
- `gb_obj_state()` and `gb_obj_offset()`
- `gb_form_run()` and `gb_form_key()`

Initial object types should stay small: box, text, string, button, editable
field, icon, image, check box, radio button and user-defined object. Useful
flags and states include selectable, default, exit, radio, hidden, disabled,
selected, checked, outlined and shadowed.

This is the single largest improvement for application consistency and future
development speed.

**Estimated effort:** 8-14 weeks for the format, runtime, tests and one host-side
compiler; longer if an interactive resource editor is included immediately.

### 2. GEM-style window kinds

GEM lets an application describe its window chrome using a bitmask. GeoBench's
managed windows already centralise much of the chrome, but their capabilities
are still comparatively fixed and some controls remain app-owned.

GEMBENCH should introduce window-kind flags such as:

- Title/name
- Close
- Maximise/restore
- Move
- Resize
- Information line
- Vertical arrows and slider
- Horizontal arrows and slider

The window manager would calculate the work area and draw and hit-test all
selected gadgets. Applications would receive standard messages instead of
implementing each scrollbar or title-bar interaction independently:

- redraw
- topped and untopped
- moved and sized
- closed and maximised
- arrow/page request
- horizontal or vertical slider change

This should extend the current `gb_mwin_t` and `GB_MSG_*` design rather than
replace it.

**Estimated effort:** 5-8 weeks, including migration of representative
applications.

### 3. A non-blocking multi-event model

GEM's `evnt_multi` unifies keyboard, pointer, timer and message activity. Its
exact blocking API is unsuitable for GeoBench because a blocked banked
application must not stop the root window-manager loop.

GEMBENCH should borrow the event-mask concept while retaining callback delivery.
An application would subscribe to event classes and receive a compact event
record containing any combination of:

- Key press
- Pointer button or double-click
- Pointer entering or leaving a watched rectangle
- Timer expiry
- Window-manager message
- Drag-and-drop
- Application-to-application message

This would reduce per-frame polling and give every application consistent
keyboard, mouse and timer semantics. Event queues must be fixed and bounded;
the kernel should merge redundant redraw and pointer-move events.

**Estimated effort:** 4-7 weeks.

### 4. Visible rectangles and repaint messages

GeoBench already supports one damage rectangle and clip-limited bottom-up
repainting. GEM's useful additional idea is visible-rectangle enumeration:
applications redraw only the portions of their work area that are exposed.

A Z80-friendly implementation should avoid GEM's dynamic linked rectangle
lists. Use a small fixed list, for example four to eight rectangles, and merge
regions when the list fills. Deliver a redraw message with the damage rectangle
and provide first/next visible-region iteration for applications that benefit
from it.

This would reduce VDP traffic when moving or closing overlapping windows. The
existing single-rectangle path should remain the fallback when region
subdivision costs more than repainting.

**Estimated effort:** 5-9 weeks, with performance measurement on real hardware.

### 5. Resource-driven menus and forms

GeoBench currently supports up to four short menu titles, with applications
building and dispatching their own popup item arrays. GEMBENCH resource trees
could add:

- Enabled and disabled items
- Check marks and radio groups
- Separators
- Keyboard shortcuts
- Consistent default File, Edit, View and Desk menus
- Automatic keyboard navigation
- Shared menu and dialog hit testing

Cascading submenus should be deferred until the simpler model is proven; they
are less comfortable on a 212-line display and add considerable state.

Forms should automatically manage focus, Tab/Shift-Tab movement, Enter for the
default object, Escape for cancel, editable field validation, radio groups and
pressed-state feedback. This builds naturally on the existing `gb_form_*` and
widget libraries.

**Estimated effort:** 5-8 weeks after the object-tree runtime exists.

### 6. A small VDI-inspired drawing context

The full GEM VDI API would add unnecessary complexity. A smaller drawing
context would nevertheless improve portability and resource rendering.

Useful features include:

- A clip rectangle owned by the current window draw callback
- Logical foreground, background, edge and accent pens
- Replace, transparent and XOR write modes
- Solid and dithered fill patterns
- Line styles
- Text alignment and measured text width
- Raster copy with explicit source and destination rectangles

These operations should wrap existing GeoBench primitives and V9938 commands.
New pixel-coordinate operations may use the full 0-511 Screen 7 horizontal
range instead of inheriting GeoBench's portable byte-column convention. They
should not reproduce VDI workstations, global arrays or the entire GEM opcode
table.

**Estimated effort:** 4-8 weeks.

### 7. Typed and persistent scrap/clipboard service

GEM's scrap directory complements GeoBench's existing in-memory clipboard.
GEMBENCH could retain the fast 510-byte buffer for small selections and add:

- A content type, such as text, bitmap, icon or file list
- A mapper-backed clipboard for medium-sized content
- Optional `SCRAP.TXT`, `SCRAP.PIC` or equivalent files for large content
- Clipboard ownership/change notification

This would make copy and paste useful between Notepad, Paint, ICONED, File
Manager and future applications without permanently reserving much more low
RAM.

**Estimated effort:** 2-4 weeks for typed and mapper-backed data; another 1-2
weeks for persistent scrap files and recovery behaviour.

### 8. Desk accessories

GEM desk accessories are a natural match for GeoBench's co-resident banked
applications. Clock, Calculator, system information and small configuration
tools could be discoverable accessories rather than ordinary desktop files.

A GEMBENCH accessory format should be a normal GeoBench application with a
small metadata header. The desktop would discover it at boot and add it to the
Desk menu. Accessories should be loaded on demand; only explicitly pinned
accessories should permanently consume a mapper segment.

**Estimated effort:** 3-6 weeks.

### 9. Shell services and application messages

GeoBench already routes file extensions to applications. GEMBENCH can turn
this into a central shell contract:

- Configurable file-type associations
- Open-document messages to an existing application instance
- Activate, close and quit messages
- Application discovery by name or capability
- A small bounded message queue per live window
- Standard launch arguments and recent-document handling

This avoids opening several copies of an editor merely to load additional
files and provides a foundation for accessories and automation.

**Estimated effort:** 3-6 weeks.

### 10. Host-side GEM resource importer

Once `.GBR` is stable, a host tool could import useful parts of OpenGEM `.RSC`
and definition files:

- Object hierarchy and geometry
- Strings and menu labels
- Monochrome or planar icons and bitmaps
- Object flags and states

The converter should produce native GEMBENCH resources at build time rather
than making the Z80 runtime parse historical pointer-based resource files.
Unsupported objects should fail with explicit diagnostics instead of silently
rendering incorrectly.

**Estimated effort:** 4-8 weeks after the `.GBR` specification stabilises.

## Graphical improvements

GeoBench is already visibly GEM-like. GEMBENCH should refine that identity with
consistent behaviour rather than merely copying a screenshot.

### Window presentation

- Distinct active and inactive title-bar states
- Standard dimensions and spacing for every chrome gadget
- Optional information line below the title
- Kernel-owned horizontal and vertical scroll furniture
- Consistent minimum sizes and work-area calculation
- Clear focus indication without relying on colour alone
- Optional window shadow only where its repaint cost is acceptable

### Controls and dialogs

- A dotted or contrasting focus rectangle
- Pressed, selected, disabled, checked and default-button states
- Radio buttons and check boxes with shared metrics
- Consistent alert icons and button order
- Tab navigation, keyboard mnemonics and visible shortcuts
- Automatic text-field caret and selection treatment

### Menus

- Highlight the active menu title and current item
- Render disabled items with a dithered or muted treatment
- Support check marks, separators and shortcut labels
- Use the same Desk/File/Edit/View ordering across applications
- Close menus on click-away, Escape or focus change

### Desktop and file manager

- Selected icon-label inversion or a bounded selection outline
- Rubber-band multi-selection
- Keyboard traversal of icons and file entries
- Consistent open, rename, information and delete commands
- A Desk menu containing accessories and system information
- A GEM-style configurable desktop grid while retaining GeoBench drag-and-drop

### Screen 7 rendering strategy

GEMBENCH can use all sixteen Screen 7 palette entries. The theme should define
semantic roles such as desktop, surface, text, edge, highlight, shadow,
selection, disabled text and alert colours rather than exposing fixed palette
numbers to applications. Native sixteen-colour icons and resources can replace
the portable four-pen asset boundary used by GeoBench.

The second portion of 128 KiB VRAM should be evaluated for:

- Menu and dialog save-under storage
- A cached clean desktop/background surface
- VDP-assisted block restoration

The V9938 command engine should handle fills, lines, copies, raster operations
and as much window movement as practical. A V9958 may expose additional
optimisations, but GEMBENCH should retain a V9938 baseline unless the Omega
build explicitly requires a V9958.

Full-screen double buffering or display-page flipping should only be adopted if
real-hardware timings show a clear improvement over damage repainting. A hidden
VRAM page may be more valuable as a clean-desktop cache and save-under pool than
as a continuously redrawn back buffer.

## Current-to-GEMBENCH architectural changes

| Current GeoBench approach | GEMBENCH improvement |
| --- | --- |
| Mostly hand-composed application UI | Compact resource and object trees |
| Fixed managed-window chrome | Window-kind flags and central gadget handling |
| Four-byte callback message | Typed events and richer standard WM messages |
| One global damage rectangle | Small merged damage list and visible regions |
| Simple title/popup menu arrays | Resource menus with states and shortcuts |
| App-owned form state and navigation | Common object focus and form engine |
| Primitive drawing calls | Small VDI-inspired drawing context |
| Untyped 510-byte clipboard | Typed RAM/mapper/file scrap service |
| File associations in application logic | Central shell association registry |
| Ordinary utility applications | Discoverable on-demand desk accessories |
| Separate theme assets | Coherent UI metrics and resource theme bundle |

## Memory and implementation constraints

The Omega's guaranteed 512 KiB mapper provides 32 physical 16 KiB segments, but
it does not remove the 64 KiB Z80 address-space limit. MSX-DOS2/Nextor and the
resident kernel also occupy address-space pages. GEMBENCH should follow these
rules:

- Keep only hot event, window and drawing primitives resident.
- Store resource references as offsets and indices, never raw banked pointers.
- Give applications optional auxiliary mapper segments for resources and data.
- Reserve mapper-backed clipboard and shared-service storage dynamically.
- Keep application-linked features optional so small apps remain small.
- Use fixed-capacity tables and degrade predictably when they fill.
- Merge redraw events and damage rectangles instead of growing queues.
- Do not load a disk module merely to repaint an ordinary control.
- Measure resident kernel size, app-bank headroom and stack use after every phase.

The object renderer creates an important placement decision. An app-linked
implementation is simple but duplicates code in each 16 KiB application bank.
A resident implementation saves app space and can map auxiliary resource
segments while executing safely from page 2, but increases pressure at
`#8000+`. The proof of concept should build and measure both before fixing the
ABI. For the fixed 512 KiB target, a small resident renderer plus banked resource
payloads is the leading design.

## Ideas not worth copying directly

Several historical GEM mechanisms are poor fits for the Z80 platform:

- The exact AES trap and global parameter-array ABI
- 8086 segmented and far-pointer data structures
- The historical binary `.RSC` layout at runtime
- A full VDI workstation implementation
- Blocking `evnt_multi` calls inside banked applications
- GEM's original process and desk-accessory memory model
- Exact pixel geometry designed for IBM PC display drivers
- Existing x86 `.APP` and `.ACC` executable formats

GEMBENCH should borrow semantics and interaction patterns, not accidental 8086
implementation details.

## Delivery estimate

The estimates assume one experienced developer working substantially full-time
and already familiar with the GeoBench codebase.

| Deliverable | Scope | Estimated effort |
| --- | --- | --- |
| Visual GEMBENCH prototype | Native Screen 7 theme, active/inactive windows, menu and control polish | 2-4 weeks |
| Architectural proof of concept | `.GBR`, banked resource segment, one object dialog, window kinds and messages | 4-7 weeks |
| GEMBENCH MVP | Desktop plus 2-3 migrated apps using resources and standard forms | 2-3 months |
| Useful first release | Resource UI, window kinds, events, menus and core app migration | 4-7 months |
| Mature hybrid desktop | Accessories, typed scrap, shell messages, importer and VDP optimisation | 7-12 months |
| Substantial GEM AES source compatibility | Separate compatibility project, not the initial goal | 18-30+ months |

These phases overlap, so the feature estimates should not simply be added
together. A part-time project should expect proportionally longer calendar
time.

## Recommended first milestone

Allocate 5-9 weeks to a bounded GEMBENCH proof of concept:

1. Define `.GBR` version 1 with strings, menus and a small object tree.
2. Implement object drawing, hit testing and state changes as an optional
   app-linked library.
3. Add window-kind flags for close, maximise, move, resize and one scrollbar.
4. Add redraw, moved, sized and slider messages to the current callback model.
5. Rebuild one existing Settings or Clock dialog entirely from a resource tree.
6. Apply a coherent native sixteen-colour GEMBENCH Screen 7 theme.
7. Evaluate hidden-VRAM caching for menus, dialogs and the clean desktop.
8. Test on openMSX and Omega/RainBIOS, recording repaint time, binary size,
   mapper use, VRAM use and stack headroom.

The milestone succeeds if the resource-built application is smaller or
materially easier to maintain and remains responsive on the 3.58 MHz Omega
MSX2. If it does not, the visual improvements can still ship independently
without committing GEMBENCH to a new application model.

## Suggested implementation order

1. Write the GEMBENCH UI metrics and interaction specification.
2. Implement the visual theme and active/inactive window states.
3. Prototype compact object/resource trees in an app-linked library.
4. Add window-kind flags and standard messages.
5. Add resource menus, form navigation and keyboard shortcuts.
6. Introduce event subscriptions and bounded message queues.
7. Improve damage handling and visible-region repainting.
8. Add typed scrap, shell services and desk accessories.
9. Build the OpenGEM resource importer only after the native format stabilises.
10. Migrate applications incrementally, keeping old APIs operational during the
    transition.

## Licensing boundary

The local GeoBench source is BSD 3-Clause, while the examined FreeGEM AES source
directory carries the GNU GPL version 2. Architectural ideas and independently
implemented interaction patterns can be adopted without copying implementation
code. Directly translating FreeGEM source or incorporating its protected assets
requires preserving the applicable notices and reviewing the resulting GPL
obligations.

The project should decide early between:

- A BSD-licensed GEM-inspired implementation written against published
  behaviour and independently created artwork, or
- A GPL GEM derivative that intentionally reuses and translates FreeGEM code or
  assets.

This is a project-planning observation rather than legal advice.

## Local references

- `../geobench/docs/ARCHITECTURE.md`
- `../geobench/docs/DEVELOPMENT.md`
- `../geobench/lib/gb/gb.h`
- `../geobench/kernel/api_table.inc`
- `../geobench/kernel/gbkern.asm`
- `../geobench/lib/msx/screen7.asm`
- `../geobench/lib/msx/bank.asm`
- `../rainbios/README.md`
- `../rainbios/docs/ARCHITECTURE.md`
- `../omega/Mainboard.md`
- `source/OpenGEM-7-RC3-SDK/OpenGEM-7-SDK/GEM AES AND SOURCE CODE/FreeGEM AES 3.0 (source code)/GEMLIB.H`
- `source/OpenGEM-7-RC3-SDK/OpenGEM-7-SDK/GEM AES AND SOURCE CODE/FreeGEM AES 3.0 (source code)/OBDEFS.H`
