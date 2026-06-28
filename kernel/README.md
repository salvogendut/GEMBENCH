# kernel/

The resident GEOBENCH OS kernel: the code that stays in memory while the
desktop and banked apps are running.

## Responsibilities

- **Boot / init** — set up the memory map, video mode, and interrupt handling,
  then hand control to the desktop shell.
- **Memory management** — detect CPC RAM, build the bank-page pool, and hand
  pages to applications, modules, and large banked assets.
- **Application loading** — load app binaries from disk on demand and transfer
  control to them in the `#4000-#7FFF` bank window.
- **System services / API dispatch** — the call gate applications use to reach
  kernel routines for graphics, windowing, input, files, modules, clipboard,
  drive state, and networking.
- **Window manager** — own the cooperative master loop, focus/z-order, managed
  chrome, damage repaint, drag/drop, and top-bar dispatch.
- **Timing / input** — frame pacing, keyboard, pointer, and RTC readout.

## Design constraints

- Keep it **small**. Every byte resident is a byte applications can't use.
- Cooperative window/app model. There is no preemptive scheduler.
- All hardware addresses and firmware vectors live behind named constants so the
  CPC-vs-CPC+ and 64K-vs-128K differences stay contained.
- Absolute low-RAM ownership is explicit in `lowram.tsv`; validate it with
  `python3 tools/check_lowram_map.py`. The assembly equates live in `lowram.inc`.
- The app ABI is the fixed jump table at `GB_KERNEL` (`#8000`) in
  `api_table.inc`. Keep `../lib/gbapp.inc` and `../lib/gb/gblib.s` in sync.

## Status

Active. The shipped default target is the no-ROM Albireo kernel, with optional
ROM/offload and recovery storage profiles still present in source. Source-level
contracts and boot/assets/module boundaries now live in `api_table.inc`,
`lowram.inc`, `boot.asm`, `assets.asm`, `config_module.asm`, `modules.asm`, and
`app_pool.asm`; continue splitting `gbkern.asm` by subsystem while keeping the
generated kernel image unchanged.
