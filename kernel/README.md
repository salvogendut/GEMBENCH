# GEOBENCH kernel

`gbkern.asm` is the shared resident kernel. It assembles with the fixed jump table
at `0x8000`, the window manager/compositor, mapper ownership, resource/module
dispatch, and the `lib/msx/` hardware and DOS backends.

Important split units include:

- `boot_msx.asm` — MSX-DOS/Nextor startup and shutdown;
- `input_api_msx.asm` — frame-paced input and event publication;
- `clock_msx.asm`, `clock_msx_rtc.asm` — software clock and RTC seed;
- `msx_page_pool.asm` — generation-safe mapper/application ownership;
- `scheduler.asm`, `scheduler_image.asm` — app-worker scheduling;
- `assets.asm`, `config_module.asm`, `modules.asm` — resource loading;
- `app_pool.asm`, `gbr_bank.asm` — application and auxiliary resource pages;
- `api_table.inc`, `lowram.inc` — frozen calls and fixed shared contracts.

Build the production target through `tools/build_kernel_msx.sh` (normally
`make geobench-msx`) and the Gate-3 CPC reference through
`tools/build_kernel_cpc.sh` (`make cpc`). The source rejects a PCW platform
define and defaults to MSX2 when no target is selected. PCW sources remain on
`archive/cpc-pcw-targets`.
