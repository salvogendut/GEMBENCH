# GEMBENCH development

The repository combines the GeoBench runtime and build system with GEMBENCH
format contracts and host tooling. GeoBench-specific toolchain and emulator
details remain authoritative in `docs/DEVELOPMENT.md` and `docs/BUILDING.md`.

## Requirements

- Python 3.11 or newer
- GNU Make
- RASM and SDCC for target builds
- mtools and dosfstools for generated MSX media

The host resource compiler requires no third-party Python packages. The full
MSX distribution uses the in-tree GEMBENCH Paint source plus the sibling
GB-BASIC repository and the dependencies documented by the inherited GeoBench
build.

## Commands

Run all current validation and build the example resource:

```sh
make check
```

Run only the GBR compiler tests:

```sh
make gbr-check
```

This runs the compiler and golden-file tests, corruption checks, portable
target-reader and object-runtime tests, and SDCC Z80 compile/size checks. Verify
an individual binary with `python3 tools/gbrverify.py path/to/resource.gbr`.

Run the VDI-lite host behavior and Z80 profile-size checks independently:

```sh
make gbvdi-check
```

Applications opt into the full context with `GB_VDI=1`, and may add
`GB_VDI_RASTER=1` and `GB_VDI_TEXT=1`. `GBR_GRAPHICS=1` links the full context,
raster profile, reader, and object runtime together. A code-tight application
may instead use `GB_VDI_BASE=1`; it is mutually exclusive with the full profile.

Rebuild only the example resource:

```sh
make gbr-example
```

Generate the static pre-runtime size and headroom report from the staged MSX
distribution:

```sh
make gembench-baseline-report
```

Boot the generated 32 MiB IDE image through the Sunrise Nextor ROM in the
sibling `1983` checkout and add guarded mapper and VRAM boot telemetry:

```sh
make gembench-baseline-1983
```

The target first runs the normal `gembench-msx` build, then writes a
machine-readable JSON report, a Markdown report, the raw emulator log, and a
desktop screenshot under `build/baseline/`. Override `--sunrise-rom` or
`--ide-image` when invoking `debug/gembench_baseline_1983.py` directly if the
sibling checkout uses different paths. A non-zero emulator exit after the
telemetry line is tolerated because a read-only host configuration can prevent
RTC persistence after the guest has completed.

Capture the scheduler stack high-water mark and one full plus one
damage-limited repaint sample with:

```sh
make gembench-baseline-probes-1983
```

This target first records the ordinary release artifacts, then rebuilds the
desktop with `GEMBENCH_BASELINE=1` and the existing preemptive TASKDEMO stress
workers. The diagnostic timer uses the MSX2 RP-5C01 seconds-test clock at
16,384 Hz, giving a 5.27-second unambiguous measurement window. The target uses
a disposable RTC because the accelerated clock changes its visible time. The
diagnostic code and TASKDEMO apps are absent from a normal `make gembench-msx`
build.

Measure pointer and keyboard response with the same three runnable tasks:

```sh
make gembench-baseline-input-1983
make gembench-baseline-input-openmsx
```

The 1983 target injects a real keyboard-matrix event at a fixed frame and
records its visible desktop acknowledgement. Its current headless interface has
no scripted pointer-motion source. The openMSX target therefore performs two
reference runs, driving both pointer and keyboard through matrix events and
requiring visible VDP/UI changes before acknowledging either response.

Build the fixed-target distribution:

```sh
make gembench-msx
```

The MSX build stages `HELLO.GBR` in the drive root and `GBRDEMO.APP` in
`/GBENCH`. Open the first desktop drive, then double-click `HELLO.GBR` to test
the real File Manager association and external-resource path. Clicking the
resource-defined button toggles its selected state.

The same release path can be driven automatically in openMSX with
`debug/gbr_object_openmsx.tcl`; the complete command and reference result are
recorded in [OPENMSX-VALIDATION.md](OPENMSX-VALIDATION.md). Use absolute output
paths when openMSX is installed as a Flatpak.

Build and exercise the production VDI-lite migration with:

```sh
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  tools/test_settings_vdi_openmsx.sh
```

The test honors `OPENMSX`, builds a disposable network-free image, launches the
exact `SETTINGS.RAW`, opens Colours, and requires the VDI entry traces plus live
editor state. Its final capture is `build/msx/settings-vdi.png`;
`MSX_HEADLESS=1` skips only the screenshot.

Build and exercise the resource-driven FormRef vertical slice with:

```sh
make formref
tools/test_formref_openmsx.sh
```

The test makes a disposable IDE image whose root-level `A.APP` is byte-for-byte
identical to the built `/GBENCH/FORMREF.APP`. It launches the app through File
Manager, traverses the GBR-defined modal from Name through Autosave and the two
layout choices, and asserts the resource descriptor, keyboard focus actions,
checkbox toggle, exclusive radio selection, default Save commit, and modal
restore.
Set `MSX_HEADLESS=1` to run every logic assertion with renderer-dependent
screenshots disabled.

The release MSX2 Calculator is the first production panel migrated to GBR. Run
`make gembench-msx`, launch `CALC.APP`, and verify that pointer activation and
keyboard arithmetic agree; its twenty button labels and hit rectangles now come
from `apps/calculator/calculator.json`. CPC and PCW deliberately keep the prior
panel path as compatibility controls.

Exercise the first explicitly registered MSX2 window kind with:

```sh
make gembench-msx
tools/test_window_kinds_openmsx.sh
```

The openMSX driver opens File Manager through the real desktop, selects List
through the generated View popup, verifies `I`, `L`, and `F` shortcuts plus
checked/radio transitions, then uses MSX keyboard-matrix pointer input to
maximise and restore it, drag its title, and resize its kernel-drawn grip. It
verifies the live geometry and observes the
`GB_MSG_MOVED`, `GB_MSG_SIZED`, and `GB_MSG_MAXIMIZED` callbacks. The final
Screen 7 capture is written to `build/msx/window-kinds.png`.
`MSX_HEADLESS=1` retains the geometry and message assertions without requesting
the capture.

The menu source is `apps/filemgr/view_menu.json`. The MSX build compiles its
ordinary frozen `.GBR` for verification and a code-only `view_menu_gbr.h` for
the app-linked runtime. A malformed `GBRM` descriptor fails atomically before
registering a top-bar title. CPC and PCW retain their existing `gb_doc` menu
path because adding the MSX runtime would exceed their 16 KiB File Manager page.

Exercise the non-blocking multi-event production slice with:

```sh
make gbevent-check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_multi_event_openmsx.sh
```

The disposable-image driver launches the byte-identical built Clock through
File Manager. It verifies that timer frames continue, `S` reaches the keyboard
class and toggles seconds, pointer movement is observed, and a real pointer
click reaches Clock without losing the associated window callback. It then
raises File Manager, requires Clock redraws with zero additional focused
frames, verifies alternating hand/seconds damage and a continuously displayed
hardware pointer, and hashes their overlap before and after to prove the
foreground is preserved. `make gembench-m8-timer-openmsx` is the build-and-test alias. See
`ARCHITECTURE-M8-MSX.md` for the worker/root contract.

Use 1983 as the complementary boot, mapper, and image-layout integration check:

```sh
python3 debug/gembench_baseline_1983.py \
  --ide-image QA/MSX/GBMSX.IMG \
  --output-dir "$PWD/build/window-kinds-1983" \
  --frames 6000
```

The milestone-6 build measures 12,260 bytes for the resident Screen 7 kernel
and 13,244 bytes for the migrated File Manager, leaving 2,884 bytes of loader
headroom. The kernel increase is 768 bytes; File Manager is 1,401 bytes smaller
because it no longer links the app-owned window gesture helpers.

Generated files live under `build/` and are ignored by Git.

## Resource changes

The `.GBR` binary layout is a target ABI. When changing it:

1. update `docs/GBR-V1.md` and `include/gembench/gbr.h` together;
2. update the host compiler and tests in the same change;
3. keep output deterministic for identical source input;
4. reject unsupported or lossy input with a clear diagnostic; and
5. increment the format version for incompatible binary changes.

Do not silently reinterpret an existing object type, flag, state bit, or record
field.

## Object runtime

The first renderer is deliberately app-linked and does not change the resident
kernel jump table. Its public interface is `include/gembench/gbr_object.h`:

- the validated resource bytes remain immutable;
- callers provide one `unsigned int` state slot per resource object;
- tree roots are placed by the caller in Screen 7 pixel coordinates, while
  child coordinates are relative to their parents;
- visible box, text/string, and button objects draw through existing libgb
  primitives and semantic black/white/grey/red pen roles;
- hidden ancestors suppress drawing and hit testing, while disabled ancestors
  additionally suppress hits; and
- hit testing returns the deepest selectable object, resolving equal-depth
  overlap in resource order.

`GBRDEMO.APP` currently caps its external resource at 512 bytes and eight
objects. These are demonstration-app limits, not additions to the GBR v1 ABI.
Resident placement and mapper-backed resource storage were measured in
Milestone 7.

The release MSX2 FormRef embeds its compiler-verified 231-byte `FORMREF.GBR`
through the generated `apps/formref/formref_gbr.h`. `GBR_FORMS=1` enables field,
checkbox, and radio rendering plus live text and focus helpers;
`GBR_FORM_ENGINE=1` adds shared activation and navigation policy.
`GBR_EMBEDDED=1` selects the compact access-only reader after the host build has
verified the generated blob. The form-capable object runtime compiles to 5,339
bytes, the optional form engine to 1,561 bytes, and the embedded accessor to 769
bytes with the current SDCC. External files continue through the strict reader.

Milestone 7 retained that placement after measurement. Build the experimental
mapper-backed comparison and the non-installed resident candidate with:

```sh
MSX_UNAPI_TSR= make gembench-msx-banked
tools/test_formref_openmsx.sh
make gembench-m7-resident-probe
```

The optional banked build keeps Milestone 7's original 306-byte resource fixture
for reproducible comparison. The normal `make gembench-msx` does not install the
mapper service or stage `FORMREF.GBR`. See
[M7-BANKING-DECISION.md](M7-BANKING-DECISION.md) for the size, stack,
interaction, and emulator results.

## MSX2 window kinds

The public `gb_mwin_t` prefix remains the original 12-byte descriptor. Existing
applications therefore retain the legacy close/drag callback contract. An
MSX2 application opts into kernel-owned furniture and gestures with the
explicit v1 wrapper and registration call:

```c
static gb_mwin_kind_t window = {
    { x, y, w, h, min_w, min_h, window_proc, title, 0 },
    GB_WK_STANDARD
};

gb_wm_managed_kind(&window);
```

`GB_WK_TITLE`, `GB_WK_CLOSE`, `GB_WK_MAXIMIZE`, `GB_WK_MOVE`, and
`GB_WK_RESIZE` may be combined independently. Completed kernel gestures report
their committed geometry through `GB_MSG_MOVED`, `GB_MSG_SIZED`, and
`GB_MSG_MAXIMIZED`; the application should refresh any cached rectangle from
`gb_wm_x()`, `gb_wm_y()`, `gb_wm_w()`, and `gb_wm_h()`. File Manager is the
reference implementation. This extension is deliberately MSX2-only and does
not change the resident jump table. `gb_wm_managed()` always selects the legacy
12-byte contract and never causes the kernel to read the appended kind byte.
The frozen layout and compatibility rules are in [ABI-V1.md](ABI-V1.md).

Run the machine-readable compatibility audit independently with:

```sh
make gembench-abi-check
```

## Multi-event subscriptions

MSX2 applications opt in by building with `GB_EVENTS=1`, including
`gbevent.h`, and owning both pieces of state:

```c
static gb_event_subscription_t subscription;
static gb_event_t event;

gb_event_init(&subscription, GB_EVENT_ALL, 1);

if (gb_event_collect(&subscription, &event, m) & GB_EVENT_TIMER)
    update_clock();
```

Call `gb_event_collect()` once at the start of the existing window procedure.
On `GB_MSG_FRAME`, the adapter reads at most one buffered key, samples the
already-published pointer once, and decrements the subscription timer once.
Pointer movement and timer expiry are represented at most once in that output
record. A non-frame message may combine `GB_EVENT_POINTER` and
`GB_EVENT_WINDOW`, so inspect the class bits independently and apply the
application's explicit priority. The record is cleared on every call and must
be consumed before the next callback.

The subscription is six bytes and the event record nine bytes. The current
SDCC build emits 860 bytes of code and no static data. Its deepest generated
path uses 31 stack bytes below `gb_event_collect()` entry while calling the
leaf `gb_mx()`/`gb_my()` accessors. The adapter remains application-linked and
outside the frozen GEMBENCH-1 binary ABI. Clock enables it only for MSX2; CPC
and PCW retain the original callback switch.

## Visible-region repainting

Architecture Milestone 9 applies exact visible-region clipping to every MSX2
window in the kernel. Applications must not add their own covered-window loop.
A repaint callback can run several times with disjoint clips during one pass,
and it can be skipped entirely while its surface is fully covered. Keep setup
bounded and make all drawing obey the published clip.

Report the smallest semantic change with `gb_wm_damage()` before
`gb_restore_parent()`. The compositor intersects that damage with the window and
its exact visible region. Geometry operations need no app assistance: move uses
the old/new endpoint envelope to repair destructive drag outlines, while a focus
change repaints the complete old and new windows through an overlap-free
two-source union. Whole-window and whole-screen damage remain appropriate for
initial paint, document replacement, resize/fullscreen layout, and global
palette changes.

The older opt-in `gbregion` library remains available for source compatibility
and its host checks, but the release Desktop no longer builds with
`GB_REGIONS=1`:

```sh
make gbregion-check
```

After `make gembench-msx`, run the Clock occlusion and PAINT multi-window
workflows through the compatibility entry point:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  tools/test_visible_regions_openmsx.sh
```

Set `MSX_HEADLESS=1` for automated runs. The aggregate result is written to
`build/msx/visible-regions-openmsx.txt`; detailed traces are in
`build/msx/multi-event-openmsx.txt` and `build/msx/m2-paint-openmsx.txt`.

## Typed clipboard/scrap

MSX2 applications build the complete bounded API with `GB_SCRAP=1` and include
`gbscrap.h`:

```c
unsigned int copied;
char text[80];

if (gb_scrap_get(GB_SCRAP_TEXT, text, sizeof text, &copied) == GB_SCRAP_OK)
    consume_text(text, copied);
```

`gb_scrap_set()` accepts text, bitmap, icon, or file-list payloads. It reports
truncation above `GB_SCRAP_CAPACITY` (510) and publishes the type only after the
payload is complete. `gb_scrap_get()` copies nothing on a type mismatch and
always initializes the caller's copied count. `GB_SCRAP_ANY` accepts typed or
legacy untyped data. Use `gb_scrap_clear()` to clear both payload and metadata.

`GB_SCRAP_TEXT_ONLY=1` requires `GB_SCRAP=1` and links the 100-byte
set/type-only adapter instead of the full runtime. It is for tight clients such
as Notepad that label their own writes, call `gb_scrap_type()` before paste, and
then use the existing resident `gb_clip_len()`/`gb_clip_get()` path. This profile
does not export query/get/clear. Both flags are MSX2-only; CPC and PCW continue
to compile their raw clipboard path unchanged.

Run the host semantics and target footprint gate with:

```sh
make gbscrap-check
```

The suite covers empty, typed, raw, stale, exact-capacity, oversized,
truncated-read, invalid-argument, mismatch, clear, and corrupt-length cases.
After `make gembench-msx`, exercise two independent Notepad windows through the
real pointer and Edit menus with:

```sh
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_typed_scrap_openmsx.sh
```

The driver copies `SCRAP13` as typed text, verifies a bitmap-tagged paste leaves
the destination unchanged from function entry to return, restores the text tag,
and verifies the seven-byte append. Its disposable image removes `UNAPINET.COM`
and runs with `MSX_UNAPI=0`, so the check does not require the optional
`unapinet` extension.

## Shell services

MSX2 applications include `gbshell.h` and link one of two deliberately small
profiles. `GB_SHELL_TARGET=1` adds only service registration; a provider calls it
after normal window registration and handles `GB_MSG_SHELL` in its existing
procedure. `GB_SHELL_CLIENT=1` adds discovery, send, and the combined request
helper. Both flags are MSX2-only.

Desk accessories use two additional isolated profiles so existing File Manager
and Notepad binaries do not grow. `GB_SHELL_ACCESSORY_TARGET=1` adds exact
registration; `GB_SHELL_ACCESSORY_CLIENT=1` adds exact discovery and the
argument-free request helper and requires the ordinary client for send. Clock
and Calculator use the target profile, while the MSX2 Desktop uses the client.

```c
unsigned char result = gb_shell_request(
    GB_SHELL_CLASS_TEXT_EDITOR, GB_SHELL_OPEN, name11);

if (result == GB_SHELL_NOT_FOUND)
    launch_editor();
```

Handles are opaque and short-lived; prefer `gb_shell_request()` to storing one.
Delivery is synchronous and non-reentrant. During `GB_SHELL_OPEN`, the target
may read the fixed 11-byte name through `gb_shell_argument` and returns a status
in `gb_msg.p1`. A busy or dirty editor should reject without changing its
document. `GB_SHELL_ACTIVATE`, `GB_SHELL_CLOSE`, and `GB_SHELL_QUIT` carry no
argument. There is no background queue to drain.

File Manager enables the client profile and Notepad the target profile in the
release MSX2 build. To exercise host contracts and the real reuse path:

```sh
make gbshell-check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_shell_service_openmsx.sh
```

The disposable openMSX image omits `UNAPINET.COM`, creates `A.TXT` and `B.TXT`,
opens both through File Manager, and requires one Notepad slot to load first
`FIRST14` and then `SECOND14`. It checks registration, two discoveries, exactly
one send/callback, the final target argument, cleared re-entry guard, restored
stack, and unchanged window count. For a manual check, build and boot normally,
open two `.TXT` files in succession from File Manager, and verify that the same
Notepad is raised and changes documents rather than creating a second window.
Then edit the document and try another `.TXT`: the same dirty Notepad should be
raised with its current contents unchanged, proving rejection is atomic.

## Desk accessory catalog

Edit `apps/desktop/accessories.json` to change the bounded MSX2 Desk catalog.
Every entry needs a unique nonzero ID, uppercase symbol, printable label, and
uppercase 1-8 character `.APP` name. Capacity is explicit and cannot exceed ten
popup rows. Regenerate or verify the committed header with:

```sh
python3 tools/gen_desk_accessories.py apps/desktop/accessories.json \
  --output include/gembench/gbdesk_catalog.h
make gbaccessory-check
```

The release catalog has capacity four and currently contains Clock and
Calculator. Both are ordinary apps and consume no mapper page until selected.
For the authoritative lifecycle check:

```sh
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_desk_accessories_openmsx.sh
```

The driver launches both rows through the real popup, selects each again to
prove exact activation with no duplicate, closes Clock through the window
gadget, observes one busy mapper page return, and relaunches Clock. A manual
check follows the same sequence from the Desktop's `Desk` title. The existing
Clock desktop icon is another route through the same exact activation helper.

## Deferred application messages

MSX2 applications opt in with `GB_DEFER=1` and include `gbdefer.h`. Register one
application handler after normal window/application publication, discover or
retain a short-lived `gb_owner_t`, and enqueue a fixed inline message:

```c
static void on_deferred(void)
{
    const gb_defer_message_t *message = gb_defer_current();
    if (message && message->type == MY_MESSAGE) handle(message->p0);
}

gb_defer_send_t message = { target, MY_MESSAGE, value, 0, 0 };
gb_defer_register(on_deferred);
if (gb_defer_send(&message) == GB_DEFER_ERR_FULL) retry_later();
```

Send copies six caller bytes and returns; the root loop invokes at most one
recipient on a later turn. The handler must return promptly and may enqueue a
reply. It must not poll or retain the pointer returned by
`gb_defer_current()`. `gb_defer_cancel_all()` cancels the caller's queued
outbound messages. Closing/unregistering cancels both directions.
The send structure may be ordinary mapped data or a C local on the fixed MSX
stack; the kernel range-checks and copies it during the call.

Desk accessory activation is the production example. `gb_defer_activate()` is
valid only inside a deferred handler and asks the root to raise/repaint the
application's primary window after the callback returns.

```sh
make gbdefer-check
make gembench-m3-openmsx
make gembench-m3-boot-openmsx  # Screen 6/7 loader smoke without the API diagnostic
MSX_HEADLESS=1 tools/test_desk_accessories_openmsx.sh
```

## Explicit filesystem contexts

MSX2 applications opt in with `GB_FSCTX=1` and include `gbfsctx.h`. Allocate a
context, set its path and raw 11-byte name explicitly, and retain the opaque
handle only for the current application lifetime:

```c
gb_fsctx_t context = gb_fsctx_open(gb_get_drive());
gb_fsctx_set_path(context, "\\DOCS");
gb_fsctx_set_name(context, "NOTES   TXT");
while ((got = gb_fsctx_read(context, buffer, sizeof(buffer))) != 0)
    consume(buffer, got);
gb_fsctx_close(context);
```

Reads and writes are sequential and bounded to 512 bytes per call. Directory
enumeration is also context-owned: interleaving another client cannot replace
the saved FIB. `gb_fsctx_dir_batch()` fetches up to four packed entries per
module call; its fixed-buffer result is valid until the next context call.
Calls are root-task operations and must not be issued by a preemptible compute
worker. Applications should test the stable sysinfo prefix plus `GB_CAP_FS_CONTEXTS`
before depending on the appended kernel jump.

File Manager is the first production client. It uses the directory-only
binding profile and activates its explicit path immediately before inherited
legacy copy/file calls. Build the release image and run the complete ownership,
offset, stale-handle, cleanup, and live File Manager test with:

```sh
make gbfsctx-check
make gembench-msx
make gembench-m4-openmsx
```

For a manual check, open two File Manager windows on the same drive, enter a
subdirectory in one, and let both listings finish. Refresh or navigate either
window; the other must retain its own path and enumeration. CPC and PCW do not
support `GB_FSCTX=1` yet.

## GBAP v3 application manifests

Set `APP_MANIFEST=path/manifest.json` together with `APP_ICON` on an MSX2 C
application build. The JSON declares the stable application ID, profile,
platform mask, minimum ABI/sysinfo, required capabilities, lifecycle, and page
policy. The builder emits the typed primary descriptor, validates the finished
package, and links the standard pre-publication guard.

```sh
make gembench-m5-manifest
python3 tools/embed_app_icon.py check build/msx/FORMREF.RAW
make gembench-m5-openmsx
```

The final command launches both a valid FormRef and an incompatible copy under
openMSX. The latter must reach the guard but not `main`, publish no window, and
restore the pending owner and free-page count. See
`docs/gembench/ARCHITECTURE-M5-MSX.md` and `docs/APP_ICON_FORMAT.md` for the
binary contract. Do not mark an application `portable-z80` merely because its
source builds on several targets: one binary also needs the frozen common ABI,
runtime geometry/capability decisions, portable resources, and a common fixed
memory layout.

## MSX2 GBAP v3 secondary code

Add a `secondary_code` object to an MSX2 v3 manifest and pass its assembled raw
image as `APP_SECONDARY`. The secondary must be fixed at `0x4000`, start with
the `GBS3` v1 prefix, own no data in the replaced page, and communicate through
`gb_secondary_transfer()` rather than primary/secondary pointers.

```sh
bash tools/build_secondary.sh apps/formref/secondary.s build/msx/FORMREF.SEC
make gembench-m6-manifest
make gembench-m6-openmsx
```

Call `gb_secondary_open()` before publishing the first window and retain its
opaque handle for `gb_secondary_call()`. Calls are synchronous and root-only;
busy, stale, foreign, invalid-entry, and terminating-app cases return explicit
status codes. There is no manual close: generation-tagged owner teardown
reclaims the secondary page. See
`docs/gembench/ARCHITECTURE-M6-MSX.md` for the complete ABI and budgets.

## MSX2 shared services

Use `GB_SERVICE_CLIENT=1` for clients, `GB_SERVICE_PROVIDER=1` for a windowless
provider, or `GB_SERVICE_COLLECTOR=1` only for the Desktop/root policy. All
three profiles are MSX2-only and imply sysinfo plus deferred-message bindings.
Applications must test `GB_CAP_SERVICE_MANAGER`; v5 keeps the v4 record size and
reserved bytes unchanged.

Clients register a deferred handler, acquire by functional ID and provider
name, send bounded requests, and release every successful handle. A provider
registers after its deferred handler, publishes windowlessly, validates each
sender with `gb_service_provider_accept()`, replies asynchronously, and quits
only when `gb_service_provider_should_stop()` is true. Do not send application
pointers or bulk data in the three request bytes.

```sh
python3 -m unittest tests.test_service_manager -v
make gembench-msx
make gembench-m7-service-openmsx
```

For a manual production check, run a network-enabled image, open Telnet, and
choose **Telnet > Connect (UNAPI)...**. The provider is launched and probed
before the host dialog appears. Cancelling or disconnecting releases the lease;
after the final client, the windowless provider unloads. See
`ARCHITECTURE-M7-MSX.md` for lifecycle, memory layout, and limitations.
