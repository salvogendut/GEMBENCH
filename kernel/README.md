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
- **Window manager** — own the root event/compositor loop, focus/z-order,
  managed chrome, damage repaint, drag/drop, and top-bar dispatch.
- **Timing / input** — frame pacing, keyboard, pointer, and RTC readout.

## Design constraints

- Keep it **small**. Every byte resident is a byte applications can't use.
- Keep kernel, firmware, storage, modules, and drawing atomic. The release
  scheduler is carried by `DESKTOP.APP` and preempts only opted-in pure app
  workers; it adds no resident kernel feature code.
- Hardware addresses and firmware vectors live behind named constants and
  target backends so CPC/CPC+, MSX2, PCW, and memory-size differences stay
  contained.
- Absolute low-RAM ownership is explicit in `lowram.tsv`; validate it with
  `python3 tools/check_lowram_map.py`. The assembly equates live in `lowram.inc`.
- The app ABI is the fixed jump table at `GB_KERNEL` (`#8000`) in
  `api_table.inc`. Keep `../lib/gbapp.inc` and `../lib/gb/gblib.s` in sync.

## Status

Active on CPC, MSX2, and PCW. CPC ships no-ROM Albireo and M4 kernels, with
optional ROM/offload and recovery storage profiles still present in source.
Source-level
contracts and boot/assets/module boundaries now live in `api_table.inc`,
`lowram.inc`, `boot.asm`, `assets.asm`, `config_module.asm`, `modules.asm`, and
`app_pool.asm`; input polling lives in `input_api.asm`; clock/RTC and RAM probing
live in `clock.asm` and `memdetect.asm`. Continue splitting `gbkern.asm` by
 subsystem while keeping the generated kernel image unchanged.

Current documentation anchors:

- `../lib/gbapp.inc` — app-visible ABI contract.
- `lowram.tsv` — fixed low-RAM ownership map.
- `../docs/PREEMPTIVE_MULTITASKING.md` — current scheduler/root ownership
  contract.
- `../docs/KERNEL_ARCHITECTURE_REVIEW.md` — dated architecture review retained
  as audit history.

On MSX2, the managed-window path also accepts an optional tagged kind tail
after the unchanged 12-byte descriptor. It conditionally draws title, close,
maximise, and resize furniture, owns the enabled move/resize/maximise gestures,
and reports committed geometry through append-only messages. Untagged apps keep
the inherited `GB_MSG_DRAG` behavior. This adds no jump-table slots; File
Manager is the first tagged client and openMSX supplies the interaction test.
