# GEOBENCH libraries

The active runtime libraries are split into three groups:

- `msx/` — V9938/V9958 Screen 6/7 drawing, font rendering, hardware-sprite
  cursor, input, MSX-DOS 2 filesystem calls, and mapper banking;
- `gb/` — the public application ABI, SDCC crt0, assembly trampolines, documents,
  dialogs, widgets, sound, networking stubs, and managed-window helpers;
- `gembench/` — GBR resources, VDI-lite, typed scrap, shell discovery, deferred
  messages, filesystem contexts, services, secondary resources, timers, and
  exact region handling.

`gbapp.inc` defines the fixed kernel jump-table addresses used by assembly
clients. `screen_clip.asm` is shared by the two MSX video modes. The root icon
ASM files are canonical four-pen resources packaged into `DEFAULT.IST`.

GEOBENCH no longer contains CPC or PCW runtime backends. Their final working
versions are preserved on `archive/cpc-pcw-targets`.
