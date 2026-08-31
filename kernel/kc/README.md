# Kernel C modules

This directory contains branch-heavy policy modules compiled with SDCC and
paged into the MSX2 application window. The resident Z80 nucleus keeps banking,
the fixed API table, hardware leaves, and hot compositor paths.

Active modules include:

- `GBCFG.MOD` — bounded `GEOBENCH.CFG` parsing;
- `GBUI.MOD` — shared dialogs, prompts, menus, and file pickers;
- `GBAPICK.MOD` — application/icon resource selection;
- `GBWEB.MOD` — Browser capture, proxy, and launch helpers;
- `GBIMG.MOD` — bounded Browser image/table/form rendering;
- `GBFSCTX.MOD` — owner-safe MSX-DOS filesystem contexts.

Networking on MSX2 uses the TCP/IP UNAPI application/service path rather than a
kernel C hardware driver.

`run_tests.sh` compiles the pure host-side configuration parser tests. Module
transfer areas are fixed in `kernel/lowram.inc` and documented in
`kernel/lowram.tsv`; keep them bounded and non-overlapping.
