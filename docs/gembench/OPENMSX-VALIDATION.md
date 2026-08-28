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
