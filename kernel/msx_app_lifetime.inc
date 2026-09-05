; #69 MSX bindings for shared application/window lifetime. No state allocation.
; Macros keep the old inlined sequences at the same addresses (no extra CALLs).
; The shared owner/page provider supplies the remaining CORE_* arrays.
CORE_APP_SLOT equ MSX_APP_SLOT
CORE_APP_REMAIN equ MSX_APP_REMAIN
CORE_WINDOW_SLOT equ MSX_WINDOW_SLOT
CORE_WINDOW_HANDLE equ MSX_WINDOW_HANDLE
CORE_WIN_GEN equ MSX_WIN_GEN
CORE_CLOSE_OWNER equ MSX_CLOSE_OWNER
CORE_CALLER_BANK equ MSX_CALLER_BANK
CORE_MAPPED_NATIVE equ bank_cur
CORE_FOCUS_SLOT equ WM_FOCUS
CORE_PREVIOUS_FOCUS equ WM_FPREV
CORE_LIVE_WINDOWS equ WM_NWIN

LIFETIME_CURRENT_OWNER equ owner_current
LIFETIME_CLOSE_WINDOW equ app_window_close_slot
LIFETIME_SET_BANK equ bank_set
LIFETIME_REMOVE_Z equ wm_z_remove
LIFETIME_FOCUS_TOP equ wm_focus_top
LIFETIME_MAP_FOCUS equ wm_map_focus
LIFETIME_REPAINT equ wm_repaint_all

                macro LIFETIME_TEST_WINDOW_ALIVE
                ld    a,c
                call  wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   0,(hl)
                mend

                macro LIFETIME_REGISTER_SLOT
                ld    a,(wm_slot)
                mend

                macro LIFETIME_PREPARE_CLOSE
                call  wm_set_clip            ; damage rectangle; B=code tag, HL=entry+4
                ld    a,b
                ld    (CORE_ALLOC_NATIVE),a
                ld    de,WM_FR_FLAGS-4
                add   hl,de                  ; HL=flags, retained through worker hook
                mend

                macro LIFETIME_DROP_WORKER
                if PREEMPTIVE_CONTEXT
                bit   3,(hl)
                jr    z,mkwc_not_task
                push  hl
                ld    hl,SCHED_RUNNABLE
                dec   (hl)
                pop   hl
mkwc_not_task
                endif
                mend

                macro LIFETIME_DRAG_CURRENT
                ld    a,(CORE_FOCUS_SLOT)
                call  wm_entry
                call  mw_publish
                call  mw_move_silent          ; caller records geometry before repaint
                mend
