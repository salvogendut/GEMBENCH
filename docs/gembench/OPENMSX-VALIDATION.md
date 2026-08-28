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

## Reproduce

Build the diagnostic image, then boot that staged image through the repository's
normal openMSX launcher with networking disabled. At 40 emulated seconds, read
52 bytes starting at page-3 address `0xC018`. The probe fields are documented in
`lib/msx/glue.inc`; phase 4 means both repaint samples completed.

```sh
make gembench-baseline-probes-1983
MSX_UNAPI=0 tools/run_msx.sh
```

The diagnostic timer intentionally advances the visible RTC and should only be
used with a disposable emulator clock state.
