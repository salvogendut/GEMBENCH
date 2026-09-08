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

CPC and PCW are not active release targets. Their earlier working tree is
preserved on `archive/cpc-pcw-targets`; the first CPC ABI experiment is preserved
on `feature/54-reintegrate-cpc` under issue #54.

The [CPC restart plan](CPC-RESTART-PLAN.md), begun in issue #63, proceeds through
five steps: define the MSX2 reference, extract shared policy on MSX2, prove the
CPC hardware/memory foundation, integrate that core, then migrate applications
and close the parity matrix. The [step-1 inventory](CPC-RESTART-MSX2-REFERENCE.md)
and [baseline results](CPC-RESTART-BASELINE.md) distinguish implemented features
from missing validation. PCW remains a later port under issue #62.

[Step 3A](CPC-RESTART-STEP3A.md), issue #65, independently tests CPC banking and
interrupt boundaries through M4/1984. Remaining shared-core extraction and
graphics/storage foundation packages are still required before integration.

See [MSX2-ONLY.md](MSX2-ONLY.md) and the
[universal ABI migration plan](UNIVERSAL-APPLICATION-ABI-MIGRATION.md) for target
status and the executable-format contract.
