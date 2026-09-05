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
- `core/window_zorder.asm`, `core/window_raise.asm`, `core/window_focus_*.asm`,
  `core/window_hit_test.asm` — shared stacking, click-to-focus, hit-testing and
  focus/menu switching, with `msx_window_focus.inc` table/driver bindings;
  see the [step-2C report](../docs/CPC-RESTART-STEP2C.md);
- `scheduler.asm`, `scheduler_image.asm` — app-worker context/IRQ machinery;
- `core/visibility_prepare.asm`, `core/visible_regions.asm`,
  `core/window_visibility.asm`, `core/worker_select.asm` — shared damage-source
  iteration, visibility ranking and worker priority, bound through
  `msx_visibility.inc`; see the [step-2D report](../docs/CPC-RESTART-STEP2D.md);
- `core/window_geometry.asm`, `core/window_focus_damage.asm`,
  `core/window_damage.asm`, `core/window_repaint.asm` — shared move/resize/focus
  damage, clip construction and repaint dispatch, with `msx_window_damage.inc`
  record, pointer, bank, IRQ and drawing hooks;
  see the [step-2E report](../docs/CPC-RESTART-STEP2E.md);
- `core/deferred_*.asm` — shared deferred endpoint/FIFO/cleanup/delivery policy,
  with `msx_deferred.inc` pointer/context and activation bindings. The shared
  timer collector remains app-linked in `lib/gembench/core/timer_collect.inc`
  (SDAS dialect), behind `lib/gembench/msx_timer_collect.inc`;
  see the [step-2F report](../docs/CPC-RESTART-STEP2F.md);
- `core/fsctx_policy.inc` — shared paged filesystem-context policy, with
  `kc/msx_fsctx.h` fixed state/Nextor hooks; `core/fsctx_cleanup.asm` retains
  storage-free resident owner cleanup. App-linked service bookkeeping uses
  `lib/gembench/core/service_internal.h` and `lib/gembench/msx_service.h`;
  see the [step-2G report](../docs/CPC-RESTART-STEP2G.md);
- `core/parameters.asm` — shared receiving-side `GB_PARAMS` validation/copy and
  timer policy, with `msx_parameter_provider.inc` state/geometry/rendering and
  critical-section hooks. Native filesystem-client and timer-publisher policy
  live in `lib/gembench/core/{fsctx_client,timer_publish}.inc`;
  see the [step-2H report](../docs/CPC-RESTART-STEP2H.md);
- `assets.asm`, `config_module.asm`, `modules.asm` — resource loading;
- `app_pool.asm`, `gbr_bank.asm` — application and auxiliary resource pages;
- `api_table.inc`, `lowram.inc` — frozen calls and fixed shared contracts.

Build only through `tools/build_kernel_msx.sh` (normally `make geobench-msx`).
The source rejects a PCW platform define and defaults to MSX2 when assembled.
CPC/PCW kernel sources are preserved on `archive/cpc-pcw-targets`.
