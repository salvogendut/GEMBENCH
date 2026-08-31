# GEOBENCH roadmap

The active GEOBENCH release remains MSX2 while the common native application
ABI is proven by an experimental CPC reference target and prepared for PCW.
Architectural depth and
application quality continue on the 512 KiB MSX2 baseline without creating new
target-specific application binaries.

## Near term

1. Continue reducing full-screen and full-window redraws through exact component
   damage and visible-region callbacks.
2. Move more application UI descriptions into deterministic GBR resources and
   VDI-lite semantic drawing.
3. Harden multi-window ownership, deferred delivery, timer coalescing, service
   lifecycle, and close/reuse paths.
4. Expand automated openMSX workflows for Paint, File Manager, Clock, Settings,
   Browser/Telnet, and bundled GB-BASIC.
5. Harden the CPC Gate-3 bootstrap and migrate applications only through the
   GEOBENCH-2 universal SDK/package.

## Medium term

- improve Screen 7 use beyond the four-pen base without weakening Screen 6;
- add richer declarative menus/forms and more GEM-like application conventions;
- reduce resident and child-COM pressure, especially the nearly full Screen 7
  kernel image;
- improve TCP/IP UNAPI service sharing and bounded asynchronous clients;
- expand hardware validation beyond the emulator reference environment;
- stabilize a documented third-party MSX2 application SDK.

## Platform restoration

CPC Gate 3 is active as an experimental 512 KiB reference target with AMSDOS,
M4, and Albireo media. PCW remains preserved on `archive/cpc-pcw-targets` and
returns as Gate 5 after the common ABI is accepted. See
[MSX2-ONLY.md](MSX2-ONLY.md) and the
[universal ABI migration plan](UNIVERSAL-APPLICATION-ABI-MIGRATION.md).
