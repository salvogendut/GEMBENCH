# GEOBENCH roadmap

GEOBENCH now develops one MSX2 system rather than maintaining several hardware
targets. The immediate roadmap is therefore architectural depth, performance,
and application quality on the fixed 512 KiB mapper / 128 KiB VRAM baseline.

## Near term

1. Continue reducing full-screen and full-window redraws through exact component
   damage and visible-region callbacks.
2. Move more application UI descriptions into deterministic GBR resources and
   VDI-lite semantic drawing.
3. Harden multi-window ownership, deferred delivery, timer coalescing, service
   lifecycle, and close/reuse paths.
4. Expand automated openMSX workflows for Paint, File Manager, Clock, Settings,
   Browser/Telnet, and bundled GB-BASIC.
5. Audit the remaining inherited code and documentation for assumptions that no
   longer apply to the fixed MSX2 target.

## Medium term

- improve Screen 7 use beyond the four-pen base without weakening Screen 6;
- add richer declarative menus/forms and more GEM-like application conventions;
- reduce resident and child-COM pressure, especially the nearly full Screen 7
  kernel image;
- improve TCP/IP UNAPI service sharing and bounded asynchronous clients;
- expand hardware validation beyond the emulator reference environment;
- stabilize a documented third-party MSX2 application SDK.

## Retired ports

CPC and PCW are not active roadmap targets. Their last working tree is preserved
on `archive/cpc-pcw-targets`. A future port effort would begin from that branch
and must be proposed as a new project decision rather than constraining current
MSX2 work. See [MSX2-ONLY.md](MSX2-ONLY.md).
