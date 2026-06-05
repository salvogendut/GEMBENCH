# Kernel C modules

The honest answer to "rewrite the kernel in C" (issue #30): you can't, fully.
An irreducible **asm nucleus** must stay — the fixed jump table at `#8000`,
banking / inter-bank trampolines, the hardware/firmware leaf routines, and the
hot-path compositor. What *can* move to C is the branchy **logic**, and the
resident region (`#8000`–`~#A67B`) is nearly full (~175 bytes free over the
9676-byte kernel), so that logic lives in **paged bank modules** the nucleus
calls through the trampoline — the SymbOS model.

This directory holds those modules. Each is pure logic: no I/O, no firmware
calls, no globals if avoidable. The nucleus owns memory and devices and hands
the module pointers.

## Modules

| File | Replaces | Role |
|------|----------|------|
| `kcfg.c` | `lib/config.asm` (`cfg_parse`/`cfg_keymatch`/`cfg_copyval`) | Parse `GEOBENCH.CFG` KEY=VALUE text into the `ICONS=`/`FONT=` set names. |

## Why C costs more here

`kcfg.c` is **673 bytes** of Z80 (`tools/build_kmod.sh`); the asm it mirrors is
~140 bytes. ~4.8× on a small routine — overhead-heavy at this size. That is the
size argument for banking modules rather than keeping them resident, and the
reason the migration is per-subsystem, not a big-bang rewrite.

## Verifying the logic

`run_tests.sh` builds `kcfg.c` with the host `cc` and runs `test_kcfg.c`, which
encodes every behavior of the original asm (defaults, comments, CR/LF vs LF,
8-char value cap, key-at-line-start only, empty value, repeated keys). The C must
pass these before the asm is retired — the migration is "prove parity, then
delete the asm," not "rewrite and hope."

```
kernel/kc/run_tests.sh        # host parity tests (no emulator)
tools/build_kmod.sh kernel/kc/kcfg.c   # SDCC -mz80 + size report
```

## How it is wired into the kernel

`kcfg_mod.c` is the loadable wrapper: built by `tools/build_cfgmod.sh` into
`build/GBCFG.RAW` (crt0 first, so `_start` is at `#4000`), packaged on the disk
as `GBCFG.BIN`, and loaded into a bank page + `call`ed exactly like an app. No
inter-bank argument ABI was needed: the module reads/writes a **fixed resident
transfer area in low RAM** (`#1000` text, `#1200` length, `#1202` ICONS out,
`#120C` FONT out) which stays main RAM under banking, so `crt0` enters with a
plain `call _main`.

Boot flow (`kernel/gbkern.asm`):

1. `cfg_boot` seeds the outputs with `DEFAULT`, `fs_load_file`s `GEOBENCH.CFG`
   into the transfer area (length 0 if absent), then `run_cfgmod` pages
   `GBCFG.BIN` into `PAGE_APP0` and calls it — the C parser fills the outputs.
2. `font_init` / `icon_init` build `<FONT>.FNT` / `<ICONS>.IST` from the parsed
   stems via `name_from_stem`, so `ICONS=`/`FONT=` select the set loaded (these
   keys had gone dead when the monolithic desktop was slimmed into the kernel).

Verified three ways in 1984 (`--memory=128`): no cfg → defaults → clean desktop;
`ICONS=DEFAULT`/`FONT=DEFAULT` → identical (cfg load + parse + filename build all
correct); `ICONS=NONE` → icons fail to load (the parsed value really selects the
file). The resident kernel grew 9676 → **9839 bytes** for the boot glue, leaving
~12 bytes under the `~#A67B` ceiling — proof that *further* migration must move
logic into modules, not add resident asm.

## Follow-ups

- **DEFAULT fallback** when a configured `.FNT`/`.IST` is missing (today a bad
  `ICONS=`/`FONT=` value loads nothing and draws garbage). Deferred because the
  retry costs resident bytes we do not currently have — it pairs with trimming
  the nucleus.
- Retire `lib/config.asm` once nothing else references it (it is already
  orphaned; left in place for this PR to keep the diff to the migration).
- Next subsystem (directory parsing) follows the same module pattern.
