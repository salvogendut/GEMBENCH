                include "cpc_routing_provider.inc"
cpc_routing_begin
                include "core/root_loop.asm"
                include "core/window_frame.asm"
                include "core/window_gestures.asm"
                include "core/menu_dispatch.asm"
cpc_routing_end
                include "../lib/cpc/poll.asm"
; Solid-backdrop configuration only. The tiled desktop asset provider is later.
k_backdrop
                xor a
                ld (fb_val),a
                jp fill_xywh
