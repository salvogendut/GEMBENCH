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

## Open integration step (next on #30)

The module compiles and is proven correct; it is **not yet wired into the
kernel**. Remaining work:

1. Pick the module's bank/load address and define the inter-bank entry ABI
   (an asm shim, placed first in the module image, that reads a transfer block —
   text ptr, length, two resident output ptrs — and calls `gb_cfg_parse`). The
   output buffers (`cfg_icons`/`cfg_font`) must be **resident** so they survive
   paging the module back out.
2. At boot, the nucleus `fs_load_file`s `GEOBENCH.CFG`, pages the module in,
   calls it, pages back.
3. Have `font_init`/`icon_init` build the `.FNT`/`.IST` filename from the parsed
   names (DEFAULT fallback = today's behavior, so default config is no
   regression), reconnecting the `ICONS=`/`FONT=` keys that went dead when the
   monolithic desktop was slimmed into the resident kernel.
