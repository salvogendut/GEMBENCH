# openMSX reference validation

openMSX is the reference emulator for the MSX2 timing baseline. The newer 1983
emulator remains the automated integration target, but its timing results are
compared against openMSX before they are accepted.

## Setup

- openMSX 21.0 Flatpak
- Philips NMS 8250, PAL, V9938, 128 KiB VRAM
- 512 KiB mapper extension
- Sunrise IDE Nextor 2.1.1
- Screen 7 diagnostic image built with `GEMBENCH_BASELINE=1`, preemptive
  scheduling, and two auto-opened TASKDEMO workers
- RP-5C01 seconds-test clock sampled at 16,384 Hz

The diagnostic image was booted twice for 40 seconds of emulated time. Both
runs reached probe phase 4 with a 32-byte scheduler stack high-water mark and
zero stack faults.

| Emulator | Full repaint | Damage repaint (32,48,40,80) | Stack / fault |
| --- | ---: | ---: | ---: |
| openMSX run 1 | 41,244 ticks (2.517334 s) | 17,442 ticks (1.064575 s) | 32 / 0 |
| openMSX run 2 | 41,243 ticks (2.517273 s) | 17,442 ticks (1.064575 s) | 32 / 0 |
| 1983 | 36,866 ticks (2.250122 s) | 15,475 ticks (0.944519 s) | 32 / 0 |

The stack and completion telemetry agree. 1983 is about 10.6% faster for the
full repaint and 11.3% faster for the damage-limited repaint, so openMSX values
are the reference numbers for performance decisions.

## Input response

The diagnostic desktop arms its input probe only after the repaint samples are
complete and the desktop plus two non-yielding TASKDEMO workers are runnable.
The openMSX driver then injects real MSX keyboard-matrix events. Pointer timing
ends after the changed coordinates are written to the VDP sprite table;
keyboard timing ends after the desktop draws its visible acknowledgement.

| Emulator | Pointer response | Keyboard response | Tasks | Stack / fault |
| --- | ---: | ---: | ---: | ---: |
| openMSX run 1 | 86.290 ms | 56.967 ms | 3 | 32 / 0 |
| openMSX run 2 | 86.290 ms | 56.967 ms | 3 | 32 / 0 |
| 1983 | not captured | 2 PAL frames (40.00 ms) | 3 | 32 / 0 |

The stock 1983 headless interface can inject the keyboard event but does not
yet expose a scripted pointer-motion source. Its keyboard result is retained as
an integration check; the repeated openMSX runs are the reference input
measurements.

## Reproduce

Build the diagnostic image, then boot that staged image through the repository's
normal openMSX launcher with networking disabled. The diagnostic dump covers 96
bytes starting at page-3 address `0xC000`. The probe fields are documented in
`lib/msx/glue.inc`; phase 4 means both repaint samples completed and input flag
7 means the pointer and keyboard acknowledgements were observed.

```sh
make gembench-baseline-probes-1983
make gembench-baseline-input-1983
make gembench-baseline-input-openmsx
```

The diagnostic timer intentionally advances the visible RTC and should only be
used with a disposable emulator clock state.

## GBR object runtime

Milestone 4 was validated on 2026-08-28 with openMSX 21.0 using the normal
release `GBRDEMO.APP` (11,127 bytes, 5,001 bytes of load headroom) and the
network-free form of the generated IDE image. The Tcl driver uses real MSX
keyboard-matrix cursor and space events to:

1. open the first desktop drive;
2. double-click the root-level `HELLO.GBR` document in File Manager;
3. wait for the external resource to validate and draw in a third managed
   window; and
4. click the resource-defined `OK` button and capture the settled Screen 7
   repaint.

The clean release capture showed the `GBR Resource` window, external welcome
text, and selected red button outline over File Manager. A diagnostic-only run
also observed renderer result `GBR_RT_OK`, the expected four-byte call/return
stack delta, and button state `0x000A` (`outlined | selected`). The diagnostic
instrumentation was removed before the release build.

The corresponding 1983 integration run reached frame 6,001 with the Screen 7
register baseline matched, 25 free mapper segments at entry, and one idle busy
application page. 1983 remains the boot/integration check because its current
headless interface cannot drive pointer motion; openMSX is authoritative for
the visible association, hit-test, and state result.

To reproduce after building a network-free image with
`MSX_UNAPI_TSR= make gembench-msx`, choose writable absolute result paths (the
Flatpak cannot see the host `/tmp` namespace):

```sh
GEMBENCH_GBR_OUTPUT="$PWD/build/msx/gbr-openmsx.txt" \
GEMBENCH_GBR_SCREENSHOT="$PWD/build/msx/gbr-openmsx.png" \
MSX_UNAPI=0 MSX_MOUSE=0 \
MSX_SCRIPT=debug/gbr_object_openmsx.tcl tools/run_msx.sh

python3 debug/gembench_baseline_1983.py \
  --ide-image QA/MSX/GBMSX.IMG \
  --output-dir "$PWD/build/gbr-1983" \
  --frames 6000
```

## FormRef vertical slice

Milestone 5 was validated on 2026-08-28 with the normal 13,420-byte MSX2
`FORMREF.APP` (2,708 bytes of loader headroom). The app embeds a verified
306-byte GBR tree containing fields, buttons, labels, and actions. Its MSX2
draw callback delegates the form body to `gbr_draw_tree`; clicks use
`gbr_hit_test`, and Tab/Return use the shared focus and activation path.

The deterministic driver creates a disposable image with an `A.APP` alias for
the exact FormRef payload, launches it through File Manager, then uses real
keyboard-matrix events to select Compact, decrement Level from 3 to 2, traverse
to Save, and activate it. The trace requires the resource tree count, app entry,
first managed draw, modal renderer, Save commit, and modal restore, and checks
the committed style/level bytes. `build/msx/formref-focus.png` records the
complete resource-defined dialog with its red focus indication.

```sh
make formref
tools/test_formref_openmsx.sh
```

The driver waits for normal low-RAM mapping and an idle V9938 command engine
before capturing, avoiding BIOS-page and in-flight Screen-7 screenshots. CPC
and PCW FormRef builds remain 7,054 bytes and retain their inherited widget
implementation.

## Window kinds

Milestone 6 was validated on 2026-08-28 with the normal 13,244-byte MSX2
`FILEMGR.APP` (2,884 bytes of loader headroom) and the 12,260-byte Screen 7
kernel. File Manager uses `GB_WK_STANDARD`; the kernel draws its selected
furniture and owns maximise/restore, title dragging, and grip resizing.

The deterministic driver launches File Manager through the real desktop and
uses keyboard-matrix pointer input for every gesture. It observes the three new
messages at the application's actual relocated callback address. A reference
passing run produced:

```text
INITIAL=4 26 56 158
MAXIMIZED=0 8 128 204
RESTORED=4 26 56 158
MOVED=17 8 56 158
SIZED=17 8 85 204
MOVED_MESSAGES=1
SIZED_MESSAGES=1
MAXIMIZED_MESSAGES=2
```

The move and resize use continuous held input after deterministic pointer
placement, so this test covers the resident outline gesture rather than direct
geometry calls. `build/msx/window-kinds.png` records the final moved and resized
window with the black, white, grey, and red theme.

```sh
make gembench-msx
tools/test_window_kinds_openmsx.sh
```

The complementary 1983 run reached frame 6,001 with PC `0x247A`, SP `0xD8EA`,
the expected Screen 7 registers, 25 free mapper segments at entry, and one idle
busy application page. openMSX remains authoritative for the interactive
gesture result.

## Milestone 7 placement comparison

Milestone 7 changed the FormRef driver to derive every application address from
the current SDCC linker and listing outputs. The same interaction trace passed
for the selected 13,023-byte embedded/app-linked build and the opt-in 15,912-byte
mapper-resource build. The latter loaded the exact 306-byte `FORMREF.GBR` into
mapper segment 8 and restored the application bank for every bounded read.

The embedded run observed a 184-byte SP delta at instrumented renderer/accessor
boundaries, an 887.758 ms first modal draw, and 1,135.416 ms from the Style Return
key to completed redraw. The mapper-resource run observed 202 bytes, 668.618 ms,
and 915.880 ms respectively. Both committed Style 1 and Level 2 and completed the
modal restore. These are FormRef-path measurements; the desktop repaint and
three-task input baselines above remain the broader scheduler references.

The corresponding 1983 images both reached frame 6,001 with identical PC, SP,
VDP-register, and entry mapper telemetry. The final placement decision also
includes the resident candidate's hard fit result and is recorded in
[M7-BANKING-DECISION.md](M7-BANKING-DECISION.md).

## Milestone 8 ABI freeze

Milestone 8 was validated on 2026-08-29 with openMSX 21.0 and the normal
embedded/app-linked resource placement. GBR1 remains binary-compatible with the
Milestone 7 resource. The managed-window prototype was deliberately revised before
freezing: File Manager now calls `gb_wm_managed_kind()` with the 13-byte v1
descriptor, while every `gb_wm_managed()` call explicitly selects the legacy
12-byte contract. The kernel no longer probes bytes after a legacy descriptor.

The release FormRef trace passed with one resource tree, committed Style 1 and
Level 2, a completed modal restore, and a 184-byte observed stack delta. Its first
modal draw measured 887.767 ms and the input-to-redraw path measured 1,136.172 ms.
The explicit-window trace passed with:

```text
INITIAL=4 26 56 158
MAXIMIZED=0 8 128 204
RESTORED=4 26 56 158
MOVED=17 8 56 158
SIZED=17 8 86 204
MOVED_MESSAGES=1
SIZED_MESSAGES=1
MAXIMIZED_MESSAGES=2
```

`MSX_HEADLESS=1` runs the same interaction and trace assertions with screenshots
disabled for renderer-less CI. A normal rendered run additionally writes the
captures documented above. The window driver waits for File Manager's asynchronous
directory scan and post-list icon probes before beginning gestures, and rejects
transient BIOS/mapper views of low RAM before recording geometry.

This validation also exposed a pre-existing boot initialization hole. Nextor uses
the shared `0x142F` drag/drop byte while loading; the three platform boot paths now
clear the complete window, z-order, and drag/drop state through `WM_DRAGDIR+3`.
Changing the existing clear length adds no resident bytes and prevents File Manager
from mistaking loader residue for an active storage claim.

The complementary 1983 run reached frame 6,001 at PC `0x247A`, SP `0xD8EA`, with
VDP R0/R1 `0x0A`/`0x62`, 25 free mapper segments at entry, and the Screen 7 baseline
matched. The Screen 6 and Screen 7 kernels remain 10,682 and 12,260 bytes. Full
`make cpc` and `make pcw` builds also passed and regenerated their card/floppy media.

```sh
make gembench-abi-check
make check
make gembench-msx
MSX_HEADLESS=1 tools/test_formref_openmsx.sh
MSX_HEADLESS=1 tools/test_window_kinds_openmsx.sh
python3 debug/gembench_baseline_1983.py \
  --ide-image QA/MSX/GBMSX.IMG \
  --output-dir build/m8/1983 \
  --frames 6000
make cpc
make pcw
```

## Architecture Milestone 2 application/window ownership

Architecture Milestone 2 was validated on 2026-08-30 with openMSX 21.0 and a
disposable 512 KiB Nextor image. The extended SYSINFO diagnostic created a
second window in one application, checked owner/count/free-slot state, closed
it through its generation-tagged handle, rejected that stale handle, then
closed and reopened the application. The owner and primary window generations
both advanced from 1 to 2; the deliberately retained cache page and application
page were reclaimed on each close. The reference pool contained 25 pages.

The Paint trace launched a real 176x176 `LOGO.PIC` through the normal File
Manager document path. Toolchest/Preview/Canvas occupied window slots 2/3/4,
shared application owner `0x0103` and one code page, and reached three windows
inside Paint. Closing Canvas left two Paint windows, closing Preview released
the document while Toolchest remained, and closing Toolchest returned to the
two baseline windows/owners. Free mapper pages returned from 22 to 22.

The run also found and fixed Paint's launch-order bug: loading `PAINT.IST`
could replace the focused window argument before `.PIC` recognition. Paint now
claims the launch document first and restores its name after loading the tool
resource. Its MSX image is 15,710 bytes versus the imported 15,753-byte
single-workspace baseline. The preemptive Screen 6/7 kernels are
13,242/14,820 bytes; `GBSCHED.RAW` remains 503/512 bytes.

```sh
make gembench-msx
make gembench-m2-openmsx
make gembench-m2-paint-openmsx
```

## Milestone 9 resource forms

Milestone 9 was validated on 2026-08-29 with the normal embedded/app-linked
placement. The release `FORMREF.APP` is 15,656 bytes and embeds a compact
231-byte tree containing a dynamic Name field, Autosave checkbox, exclusive
Classic/Refined radios, and default Save plus Cancel exits. The shared form
engine owns pointer activation, checked state, radio exclusivity, Tab traversal,
default Return, Escape, and radio cursor policy; mutable state remains in the
application overlay.

The openMSX keyboard-matrix trace toggled Autosave off, selected Refined,
activated Save, and observed the compositor restore. It measured a 184-byte
instrumented stack delta, 776.960 ms for the first modal draw, and 1,049.452 ms
from the first Tab event to the completed redraw. The optional mapper build also
passed against the pinned Milestone 7 fixture: its 15,938-byte app loaded the
306-byte resource into segment 8, committed Style 1 and Level 2, and observed a
202-byte stack delta.

Calculator is the first production panel migrated to GBR. Its MSX2 build is
11,998 bytes; all twenty button labels and hit rectangles come from the
461-byte generated tree. CPC and PCW retain their existing application-owned
geometry. Host tests verify object order, default-key metadata, rendering, and
pointer identity, while the full normal MSX distribution and repository check
suite pass.

The complementary 1983 boot reached frame 6,001 at PC `0x247A`, SP `0xD8EA`,
with VDP R0/R1 `0x0A`/`0x62`, 25 free mapper segments at entry, and one idle
busy application page. The generated baseline reports 472 bytes of FormRef
loader headroom and 4,130 bytes for Calculator. openMSX remains authoritative
for the scripted form interaction.

```sh
make check
make gembench-msx
MSX_HEADLESS=1 tools/test_formref_openmsx.sh
python3 debug/gembench_baseline_1983.py \
  --ide-image QA/MSX/GBMSX.IMG --output-dir build/m9/1983 --frames 6000
make gembench-msx-banked
MSX_HEADLESS=1 tools/test_formref_openmsx.sh
```

## Milestone 10 resource menus

Milestone 10 was validated on 2026-08-29 with a 127-byte canonical File Manager
View resource and its generated 42-byte `GBRM` descriptor. The descriptor and
source-only `F`, `I`, and `L` shortcuts do not alter any GBR1 byte. The target
runtime compiles to 1,879 bytes with caller-owned state; malformed magic,
lengths, state bits, duplicate identities/shortcuts, and trailing bytes fail
before a menu title is registered.

The release MSX2 File Manager is 14,416 bytes (1,167 bytes over the Milestone 8
baseline, with its fit guard still passing). `GBUI.MOD` grows from 5,953 to
6,063 bytes; the Screen 6/7 kernels remain 10,682/12,260 bytes. The openMSX
trace opened View through the real pointer path, selected List, exercised the
Icons/List radio shortcuts and Fullscreen checkbox shortcut, restored the
window, then passed the existing maximise/move/resize sequence. Its menu trace
was `POINTER_LIST ICONS LIST FULLSCREEN RESTORED`.

1983 independently reached frame 6,002 at PC `0x247A`, SP `0xD8EA`, with VDP
R0/R1 `0x0A`/`0x62` and the expected mapper registers. Full MSX2, CPC card/disk,
and PCW disk builds passed. CPC and PCW retain their prior `gb_doc` File Manager
menu after their page budget rejected linking the MSX2 menu runtime.

```sh
make check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_window_kinds_openmsx.sh
python3 debug/gembench_baseline_1983.py --frames 6001
make cpc
make pcw
```

## Milestone 11 multi-event subscriptions

Milestone 11 was validated on 2026-08-29 with openMSX 21.0 using a disposable
Nextor image whose root-level `A.APP` is byte-identical to the built MSX2
`CLOCK.APP`. Clock owns the six-byte subscription and nine-byte result. The
app-linked runtime is 860 bytes and has no static or resident data; Clock is
11,288 bytes, versus 10,112 before migration. Its loaded code ends at `0x6C18`
with data beginning at `0x6D00`, leaving 232 bytes between them. The Screen 6/7
kernels remain 10,682/12,260 bytes.

The driver launches Clock through File Manager, records its draw/event entry
points only while its bank is mapped, holds the real MSX `S` matrix key, moves
the pointer to Clock's grip, and clicks it. The reference trace passed with 2
draw hits, more than 360 timer hits, one pointer-click hit, one combined
pointer/window hit, two key-class hits (the `S` toggle and the later fire/space
input), `show_seconds=1`, and final pointer position `(49,140)`.

The complementary 1983 run reached frame 6,002 at PC `0x247A`, SP `0xD8EA`,
with VDP R0/R1 `0x0A`/`0x62` and the expected mapper registers. Complete MSX2,
CPC card/disk, and PCW disk builds passed; CPC and PCW do not link `gbevent`.

```sh
make gbevent-check
make check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_multi_event_openmsx.sh
python3 debug/gembench_baseline_1983.py --frames 6001
make cpc
make pcw
```

## Milestone 12 visible-region repainting

Milestone 12 was validated on 2026-08-29 with openMSX 21.0 and a disposable
Nextor image containing `CLOCK.APP` as root-level `A.APP`. The real pointer path
opens File Manager, moves it, launches Clock, tops File Manager, and closes both
windows. Captures are delayed until the Desktop repaint returns and the V9938
command engine plus File Manager icon probes have drained. The moved, overlapped,
topped, File-Manager-closed, and final Desktop frames contain no holes or stale
pixels; the window count returns to one.

The four-rectangle helper compiles to 1,581 Z80 code bytes with no static or
resident data. Desktop owns 40 bytes of iterator state and is 14,517 bytes,
versus 12,909 before migration. Its loaded image ends at `0x78B5`, data/BSS at
`0x7A65`, and the preemptive stack snapshot remains reserved at
`0x7F00-0x7FFF`, leaving 1,179 bytes before that reserve. Screen 6/7 kernels
remain 10,682/12,260 bytes. CPC and PCW do not link the helper.

The reference move damaged `(4,8,70,176)`: 12,320 byte-column/line cells. Two
visible rectangles totalled 3,472 cells, skipping 8,848 covered cells (71.8%).
The complete trace contained two optimized passes, one fully covered no-draw
pass, and no capacity fallback. `gb_visible_begin()` peaked at 4.973 ms and 70
stack bytes below entry; the longest Desktop clipped-paint pass in the workflow
was 488.018 ms. Host tests separately force the deterministic four-piece and
capacity-exhausted fallback cases.

The complementary 1983 run reached frame 6,002 at PC `0x247A`, SP `0xD8EA`,
with VDP R0/R1 `0x0A`/`0x62`, 25 free mapper segments at entry, and one idle
busy application page. Complete MSX2, CPC card/disk, and PCW disk builds passed;
the portable targets retain their legacy repaint callback.

```sh
make gbregion-check
make check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  tools/test_visible_regions_openmsx.sh
python3 debug/gembench_baseline_1983.py --frames 6001
make cpc
make pcw
```

## Milestone 13 typed clipboard/scrap

Milestone 13 was validated on 2026-08-29 with openMSX 21.0 and a disposable,
network-free Nextor image containing byte-identical `A.APP` and `B.APP` aliases
of the release MSX2 Notepad. The real pointer path types `SCRAP13`, invokes
Edit > Select All and Edit > Copy in the source, moves that window, raises File
Manager, and opens a second Notepad.

The copied resident payload is type 1 (text), length 7, and exactly `SCRAP13`.
The driver changes only the private tag to type 2 (bitmap), invokes the
destination Paste action, and observes identical destination length and bytes
at `paste_clip()` entry and its common return. Restoring type 1 and invoking
Paste again appends exactly seven bytes. Both paste calls traverse the real
menu and application callback; the final window count is four. The driver
samples low RAM only in its normal primary-slot mapping and identifies Notepad
callbacks by their built image signature.

The full runtime compiles to 552 Z80 code bytes with no static data. Notepad's
compact set/type profile is 100 bytes; the release `NOTEPAD.APP` is 12,097
bytes, versus 11,975 before migration. Loaded code and initializers end at
`0x6F3D`, data begins at `0x6F48`, and the 4 KiB document buffer remains intact.
The Screen 6/7 kernels remain 10,682/12,260 bytes; the added private low-RAM
cell passes the MSX map overlap check.

```sh
make gbscrap-check
make check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_typed_scrap_openmsx.sh
python3 debug/gembench_baseline_1983.py --frames 6001
make cpc
make pcw
```

## Milestone 14 shell services

Milestone 14 was validated on 2026-08-29 with openMSX 21.0 and a disposable,
network-free Nextor image containing root-level `A.TXT` (`FIRST14`) and `B.TXT`
(`SECOND14`). The driver opens the first drive and both documents through the
real File Manager pointer path. The first lookup finds no text editor and
retains the legacy Notepad launch. Notepad registers service class `0x20`; after
File Manager is raised again, the second lookup resolves the live editor and
delivers one open request.

The passing trace observed one registration, two discoveries, one send, and one
target callback. The live window count stayed at three (Desktop, File Manager,
and one Notepad), focus returned to that original Notepad slot, its document
changed to exactly `SECOND14`, and both its per-window name and the synchronous
shell argument were `B       TXT`. The non-reentry guard returned to zero and
the final stack pointer was `0xD8EA`. Instrumentation measured `SP=0xD8E1` at
the `GB_SHELL` send entry and `SP=0xD8DD` at the real Notepad procedure, a
four-byte dispatch delta.

The release Screen 6/7 kernels are 10,938/12,516 bytes, exactly 256 bytes above
Milestone 13, and allocate one private MSX low-RAM guard byte at `0x133E`.
`FILEMGR.APP` is 14,506 bytes, with 182 bytes between its loaded image and data;
`NOTEPAD.APP` is 12,070 bytes, keeps its 4 KiB document buffer, has 34 bytes
between code/initializers and data, and ends data/BSS seven bytes below
`0x8000`. The request helper, client binding, and target registration binding
compile to 27, 16, and five Z80 bytes. No queue, retained mapper segment, or
additional window slot exists.

The complementary 1983 run reached frame 6,002 at PC `0x247A`, SP `0xD8EA`,
with VDP R0/R1 `0x0A`/`0x62`, 25 free mapper segments at entry, and the Screen 7
baseline matched. Full CPC Albireo/M4 card and floppy packaging plus all three
PCW disks also built successfully; those targets do not export or link the
MSX-only shell entry and retain their legacy document-launch behavior.

```sh
make gbshell-check
make check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_shell_service_openmsx.sh
python3 debug/gembench_baseline_1983.py --frames 6001
make cpc
make pcw
```

## Milestone 15 Desk accessories

Milestone 15 was validated on 2026-08-29 with openMSX 21.0 and a disposable,
network-free Nextor image. The driver used real keyboard-matrix pointer input to
open the generated `Desk` popup, launch Clock and Calculator, reselect
Calculator and Clock, close Clock through its title gadget, and select Clock
again after release.

The passing trace recorded registrations for stable IDs `1 2 1`, exact lookup
IDs `1 2 2 1 1`, and exactly two sends for the two live activations. Clock used
slot 1 and Calculator slot 2; the window count never exceeded three. Closing
Clock reduced busy mapper-pool pages from four to three (the Desktop wallpaper
owns the non-window page), and relaunch restored four. The final Clock retained
class `0xA0` and exact ID 1, the shell guard was zero, and the final SP was
`0xD8E5` in the reference run.

The release catalog contains two of four fixed slots. `DESKTOP.APP` is 14,679
bytes; loaded code and initializers end at `0x7957`, nine bytes before data at
`0x7960`, while data ends at `0x7AC6`, 1,082 bytes below the preemptive stack
reserve. `CLOCK.APP` is 11,377 bytes with image/data ends `0x6C71`/`0x6DE3`;
`CALC.APP` is 12,048 bytes with image/data ends `0x6F10`/`0x766C`. File Manager
and Notepad remain 14,506/12,070 bytes. The Screen 6/7 kernels are
11,194/12,772 bytes and still use only the Milestone-14 shell guard byte; exact
identity adds no low-RAM range.

The complementary 1983 run reached frame 6,002 at PC `0xEE54`, SP `0xD8F2`,
with VDP R0/R1 `0x0A`/`0x62`, 25 free mapper segments at entry, and one idle
busy application page. Full CPC Albireo/M4 card and floppy packaging plus all
three PCW disks built successfully; their application behavior remains
unchanged because Desk accessories are an MSX2-only shell extension.

```sh
make gbaccessory-check
make gbshell-check
make check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  MSX_HEADLESS=1 tools/test_desk_accessories_openmsx.sh
python3 debug/gembench_baseline_1983.py --frames 6001
make cpc
make pcw
```

## Milestone 16 VDI-lite Settings migration

Milestone 16 was validated on 2026-08-29 with openMSX 21.0 and a disposable,
network-free Nextor image. The driver copies the exact release
`SETTINGS.RAW` to root-level `A.APP`, waits for the initial managed-window paint
to return, moves the real keyboard-matrix pointer to Colours, and waits for the
compositor-owned colour-editor draw to complete before capturing.

The passing trace observed one VDI context initialization, five VDI fills, four
VDI frames, one completed editor draw, live picker state 1, and the expected
three-window z-order `0,1,2` with Settings focused in slot 2. The panel fill was
`18,24,58,184,1`; the four native swatches used semantic pens 0-3 and edge pen
2. The Settings code signature remained mapped throughout. The final capture at
`build/msx/settings-vdi.png` shows Desktop colours with black Paper, white Text,
grey Edge, and red Accent samples.

The compact VDI profile compiles to 586 bytes. The full core, raster, text, and
text-call profiles are 1,137, 1,078, 579, and 12 bytes. The graphics-enabled GBR
object runtime is 4,747 bytes and its host corpus proves atomic missing,
duplicate, unreferenced, truncated, dimension-mismatched, and misaligned
failure, semantic raster runs, and outlined ICON state.

`SETTINGS.APP` is 15,276 bytes. Loaded code and initializers end at `0x7BAC`,
148 bytes before data at `0x7C40`; data/BSS ends at `0x7FFA`. The loader has 852
bytes of raw-image headroom. Screen 6/7 kernels remain 11,194/12,772 bytes
because every VDI component is app-linked.

The complementary 1983 run reached frame 6,002 at PC `0xEE54`, SP `0xD8F2`,
with VDP R0/R1 `0x0A`/`0x62`, 25 free mapper segments at entry, and the Screen 7
baseline matched. CPC Settings builds its native path at 14,561 bytes and the
Albireo/M4 card plus floppy distribution completes. PCW Settings builds its
monochrome path at 12,957 bytes and all three PCW disks complete.

```sh
make gbvdi-check
make check
make gembench-msx
OPENMSX='flatpak run --command=openmsx org.openmsx.openMSX' \
  tools/test_settings_vdi_openmsx.sh
python3 debug/gembench_baseline_1983.py \
  --ide-image QA/MSX/GBMSX.IMG --output-dir build/m16/1983 --frames 6001
make cpc
make pcw
```
