; Fixed CPC link of the same MSX focus/z-order and visible damage mechanisms.
; No registration, loader, lifetime teardown or application callbacks here.
                include "cpc_window_provider.inc"
cpc_window_policy_begin
                include "core/window_hit_test.asm"
                include "core/window_focus_click.asm"
                include "core/window_focus_map.asm"
                include "core/window_raise.asm"
                include "core/window_zorder.asm"
                include "core/window_damage.asm"
                include "core/window_focus_damage.asm"
                include "core/window_geometry.asm"
                include "core/window_repaint.asm"
cpc_window_policy_end
                include "../lib/cpc/window.asm"
