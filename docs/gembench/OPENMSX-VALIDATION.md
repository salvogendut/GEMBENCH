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
