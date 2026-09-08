; Hardware-side clip/pointer helpers for shared window repaint callbacks.
; Serialized root work. Never modify the iterator's active clip or its sources.
; Return CF with rect_x/y/w/h intersected with physical Mode-1 bounds; NC empty.
cpc_window_clip
                ld a,(WM_CLIP_W)
                ld b,a
                ld d,0
                ld e,CPC_COLUMNS
                ld c,e
                ld a,(WM_CLIP_X)
                call clip_axis
                ret nc
                ld (rect_x),a
                ld a,b
                ld (rect_w),a
                ld a,(WM_CLIP_H)
                ld b,a
                ld d,0
                ld e,CPC_LINES
                ld c,e
                ld a,(WM_CLIP_Y)
                call clip_axis
                ret nc
                ld (rect_y),a
                ld a,b
                ld (rect_h),a
                ret
cpc_window_call
                ifdef CPC_RUNTIME
                ; Native chrome leaves may return DI. Root application code
                ; must run with time IRQs enabled BETWEEN primitives as well.
                ; Root cannot be preempted; IRQ never touches video/PPI scratch.
                ; Do not move this to PAINT_IRQ_ENTER: chrome runs after it.
                ei
                endif
                jp (hl)
cpc_window_pointer_hide
                ifdef CPC_RUNTIME
                ; Finish a due move BEFORE an explicit native transaction
                ; hides the pointer (e.g. the shared Desktop's minute label).
                ; Never override that hide or reenter an application callback.
                call cpc_pointer_service
                endif
                ld a,(CORE_POINTER_PAINTLOCK)
                or a
                ret nz
                jp pointer_hide
cpc_window_pointer_show
                ld a,(CORE_POINTER_PAINTLOCK)
                or a
                ret nz
                jp pointer_show
