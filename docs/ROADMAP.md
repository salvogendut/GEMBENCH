# GEOBENCH roadmap

The active GEOBENCH release remains MSX2 while a common native application ABI
is designed for staged CPC and PCW reintroduction. Architectural depth and
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
5. Implement and validate the proposed GEOBENCH-2 universal SDK/package on MSX2.

## Medium term

- improve Screen 7 use beyond the four-pen base without weakening Screen 6;
- add richer declarative menus/forms and more GEM-like application conventions;
- reduce resident and child-COM pressure, especially the nearly full Screen 7
  kernel image;
- improve TCP/IP UNAPI service sharing and bounded asynchronous clients;
- expand hardware validation beyond the emulator reference environment;
- stabilize a documented third-party MSX2 application SDK.

## Platform restoration

CPC and PCW are not active build targets today. Their last working tree is
preserved on `archive/cpc-pcw-targets`. CPC restoration (issue #54) is paused
behind the universal application ABI (issue #55), then PCW is restored as the
third implementation. See [MSX2-ONLY.md](MSX2-ONLY.md) and the
[universal ABI migration plan](UNIVERSAL-APPLICATION-ABI-MIGRATION.md).
