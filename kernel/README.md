# GEOBENCH kernel

`gbkern.asm` is the MSX2 resident kernel. It assembles with the fixed jump table
at `0x8000`, the window manager/compositor, mapper ownership, resource/module
dispatch, and the `lib/msx/` hardware and DOS backends.

Important split units include:

- `boot_msx.asm` — MSX-DOS/Nextor startup and shutdown;
- `input_api_msx.asm` — frame-paced input and event publication;
- `clock_msx.asm`, `clock_msx_rtc.asm` — software clock and RTC seed;
- `msx_page_pool.asm`, `msx_owner_page.inc` — MSX mapper/application adapter;
- `core/owner_*.asm`, `core/page_*.asm` — shared owner/page policy with a
  checked state/callback contract; see the [step-2A report](../docs/CPC-RESTART-STEP2A.md);
- `core/app_*.asm`, `core/window_*.asm`, `core/owner_context.asm` — shared
  application/window identity, attachment, validation and lifetime;
  `msx_app_lifetime.inc` supplies state and window-manager hooks without
  changing the MSX2 compositor; see the [step-2B report](../docs/CPC-RESTART-STEP2B.md);
- `scheduler.asm`, `scheduler_image.asm` — app-worker scheduling;
- `assets.asm`, `config_module.asm`, `modules.asm` — resource loading;
- `app_pool.asm`, `gbr_bank.asm` — application and auxiliary resource pages;
- `api_table.inc`, `lowram.inc` — frozen calls and fixed shared contracts.

Build only through `tools/build_kernel_msx.sh` (normally `make geobench-msx`).
The source rejects a PCW platform define and defaults to MSX2 when assembled.
CPC/PCW kernel sources are preserved on `archive/cpc-pcw-targets`.
