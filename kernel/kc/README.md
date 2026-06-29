# Kernel C modules

The honest answer to "rewrite the kernel in C" (issue #30): you can't, fully.
An irreducible **asm nucleus** must stay — the fixed jump table at `#8000`,
banking / inter-bank trampolines, the hardware/firmware leaf routines, and the
hot-path compositor. What *can* move to C is the branchy **logic**, and the
resident region around `#8000` is tight, so that logic lives in **paged bank
modules** the nucleus loads and calls through the trampoline — the SymbOS model.

This directory holds those modules. Each is pure logic: no I/O, no firmware
calls, no globals if avoidable. The nucleus owns memory and devices and hands
the module pointers (or a fixed low-RAM transfer area). The modules are loaded
into a bank page and `call`ed exactly like an app; only one is live at a time, so
several share the same low-RAM transfer/buffer overlays.

## Modules

| Built module | Sources | Build script | Role |
|------|---------|--------------|------|
| `GBCFG.MOD` | `kcfg.c` + `kcfg_mod.c` wrapper | `tools/build_cfgmod.sh` | Parse `GEOBENCH.CFG` KEY=VALUE text into the `ICONS=`/`FONT=`/`CURSOR=` set names, the `BACKDROP=` tile name (+ its `A:`/`B:` drive prefix), and the `INKS=` palette (4 pens + border). |
| `GBUI.MOD` | `gbui_mod.c` dispatcher + `lib/gb/gbdlg.c`, `gbprompt.c`, `gbpick.c` | `tools/build_uimod.sh` | The shared `gb_doc` dialog/menu renderer (#142): File/Edit/View menus, the Open/Save file dialog, and prompts — paged so it isn't duplicated into every app bank. |
| `GBNET.MOD` | `gbnet_mod.c` dispatcher + `w5100.c`, `net.c`, `udp.c`, `dns.c`, `gbnet_init.c` | `tools/build_netmod.sh` | The W5100S/Net4CPC socket driver behind a one-entry op-selector (#238): init, TCP connect/send/recv, UDP, and DNS resolve, used by `TELNET.APP` on Albireo/Net4CPC systems. |
| `GBNETM4.MOD` | `gbnet_m4_mod.c` | `tools/build_m4netmod.sh` | The M4ROM TCP command backend (#259) for the same `gb_net_*` API. It uses M4 `C_NET*` commands and `sock_info`; M4 has TCP plus host lookup, not the W5100 UDP path. It preserves the caller's active video mode/hint around M4ROM paging so fullscreen Mode 2 clients stay stable. |

The `.c`/`.h` pairs `net`, `udp`, `dns`, `w5100` (plus `netinit.h`) are the
Net4CPC stack compiled into `GBNET.MOD`; `gbnet_m4_mod.c` is intentionally
separate so M4 does not carry W5100 register code.

## Why C costs more here

A C routine compiled with SDCC is roughly **4–5×** the size of the hand-written
Z80 it mirrors (overhead-heavy at small sizes). That is the size argument for
**banking** these modules rather than keeping the logic resident, and the reason
the migration is per-subsystem, not a big-bang rewrite. Resident SDCC code is
expensive; C belongs in a paged module unless the routine is tiny and cold.

## Verifying the logic

`run_tests.sh` builds `kcfg.c` with the host `cc` and runs `test_kcfg.c`, which
encodes the parser's behavior (defaults, comments, CR/LF vs LF, value cap,
key-at-line-start only, empty value, repeated keys, the `A:`/`B:` drive prefix).
The C must pass these before the asm it replaced is retired — "prove parity, then
delete the asm," not "rewrite and hope."

```
kernel/kc/run_tests.sh                 # host parity tests (no emulator)
tools/build_kmod.sh kernel/kc/kcfg.c   # SDCC -mz80 + size report for one .c
```

## How it is wired into the kernel

Each module is built crt0-first (so `_start` is at `#4000`), packaged on the disk
with a `.MOD` extension, and loaded into a bank page + `call`ed like an app. No
inter-bank argument ABI is needed: a module reads/writes a **fixed resident
transfer area in low RAM** (which stays main RAM under banking), so `crt0` enters
with a plain `call _main`. The cells are named in `kernel/lowram.inc`; for
`GBCFG.MOD` the config text is at `KCFG_TEXT` (`#1000`), its length at `KCFG_LEN`
(`#1200`), and the parsed outputs follow — `KCFG_ICONNAME`, `KCFG_FONTNAME`,
`KCFG_CURSORNAME`, `KCFG_INKS`, `KCFG_BDPNAME`, and the backdrop drive byte
`KCFG_BDDRIVE`.

Boot flow for the config module lives in `kernel/config_module.asm` (split out of
`gbkern.asm`): it seeds the outputs with `DEFAULT`, `fs_load_file`s
`GEOBENCH.CFG` into the transfer area (length 0 if absent), then pages
`GBCFG.MOD` into a bank and calls it — the C parser fills the outputs.
`assets.asm` then builds `<FONT>.FNT` / `<ICONS>.IST` / `<CURSOR>.SPR` /
`<BACKDROP>.BDP` from the parsed stems, so the config keys select what loads.

## Follow-ups

- **DEFAULT fallback** when a configured `.FNT`/`.IST` is missing (a bad value
  loads nothing and draws garbage). Deferred because the retry costs resident
  bytes; it pairs with trimming the nucleus.
- Retire `lib/config.asm` once nothing else references it (it is already
  orphaned — `GBCFG.MOD` is the live parser).
- Continue moving branchy policy into paged modules following this pattern, per
  `docs/KERNEL_ARCHITECTURE_REVIEW.md`.
