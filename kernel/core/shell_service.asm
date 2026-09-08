; k_shell (GB_SHELL): bounded synchronous shell services for the shared kernel.
; A selects the operation:
;   0 register: B = encoded service class (#20..#E0), current focus opts in
;   1 find:     B = service class, returns A = opaque slot+1 handle or zero
;   2 send:     B = handle, C = request, HL = optional 11-byte open argument
;   3 accessory register: C = nonzero stable accessory ID, current focus opts in
;   4 accessory find:     C = accessory ID, returns exact handle or zero
;
; Delivery is deliberately queue-free.  A one-byte guard rejects re-entry, the
; target is raised and mapped, and its normal window callback receives
; GB_MSG_SHELL with request in p0 and a writable response in p1.  The caller's
; bank is restored before returning even though focus remains on the target.
GB_SHELL_REGISTER equ 0
GB_SHELL_FIND     equ 1
GB_SHELL_SEND     equ 2
GB_SHELL_REGISTER_ACCESSORY equ 3
GB_SHELL_FIND_ACCESSORY equ 4
GB_SHELL_ACCESSORY_CLASS equ #A0
GB_SHELL_OPEN     equ 1
GB_SHELL_QUIT     equ 4
GB_SHELL_OK       equ 0
GB_SHELL_STALE    equ 2
GB_SHELL_BUSY_RES equ 3
GB_SHELL_BAD      equ 4
GB_SHELL_NOHANDLER equ 5

k_shell
                or    a
                jr    z,ksh_register
                dec   a
                jr    z,ksh_find
                dec   a
                jp    z,ksh_send
                dec   a
                jr    z,ksh_register_accessory
                dec   a
                jr    z,ksh_find_accessory
ksh_bad         ld    a,GB_SHELL_BAD
                ret

; Register one of seven encoded service classes in the current window's unused
; flag bits.  The existing alive/managed/task/kind bits remain unchanged.
ksh_register
                ld    a,b
                and   WM_SHELL_MASK
                jr    z,ksh_bad
                ld    (wm_slot),a                  ; app-owned class; window flags stay a mirror
                ld    a,(WM_FOCUS)
                call  wm_entry
                push  hl
                ld    de,WM_FR_EVENT
                add   hl,de
                ld    a,(hl)
                inc   hl
                or    (hl)
                pop   hl
                jr    z,ksh_nohandler
                call  owner_current
                call  owner_validate
                jr    nc,ksh_bad
                ld    a,e
                dec   a
                ld    hl,CORE_APP_SERVICE
                add   a,l
                ld    l,a
                ld    a,(wm_slot)
                ld    (hl),a
                ld    c,a
                ld    a,(WM_FOCUS)
                call  wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    a,(hl)
                and   #1F
                or    c
                ld    (hl),a
                xor   a
                ret
ksh_nohandler   ld    a,GB_SHELL_NOHANDLER
                ret

; Exact accessory identity extends the coarse class without allocating a
; process table.  Accessory apps have no launch document, so byte 10 of their
; existing private per-window argument is available as a stable nonzero ID.
; Ordinary service registration never reads or modifies that byte.
ksh_register_accessory
                ld    a,c
                or    a
                jr    z,ksh_bad
                push  bc
                ld    b,GB_SHELL_ACCESSORY_CLASS
                call  ksh_register
                pop   bc
                or    a
                ret   nz
                push  bc
                call  owner_current
                call  owner_validate
                pop   bc
                jr    nc,ksh_bad
                ld    a,e
                dec   a
                ld    hl,CORE_APP_ACCESSORY
                add   a,l
                ld    l,a
                ld    (hl),c
                ld    a,(WM_FOCUS)
                call  wm_entry
                ld    de,WM_FR_ARG+10
                add   hl,de
                ld    (hl),c
                xor   a
                ret

; Search z-order from top to bottom so a class with several instances resolves
; to the most recently active compatible window.  Handles are slot+1; zero is
; therefore an unambiguous not-found result.
                include "service_lookup.asm"

; Send one standard request to a previously discovered handle.  Stale handles,
; invalid requests/arguments, and nested delivery fail before focus changes.
ksh_send
                ld    a,(SHELL_BUSY)
                or    a
                jp    nz,ksh_busy
                ld    a,c
                or    a
                jp    z,ksh_bad
                cp    GB_SHELL_QUIT+1
                jp    nc,ksh_bad
                ld    (GB_MSG+1),a               ; p0 = request; survives helper calls
                ld    a,b
                dec   a
                cp    WM_MAXWIN
                jp    nc,ksh_stale
                ld    (GB_MSG+3),a               ; private target slot until dispatch
                push  hl                         ; caller-page open argument
                call  wm_entry
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    a,(hl)
                bit   0,a
                jr    z,ksh_pop_stale
                ld    a,(GB_MSG+3)
                call  app_service_for_window
                or    a
                jr    z,ksh_pop_stale
                pop   hl
                push  hl
                ld    de,WM_FR_EVENT
                add   hl,de
                ld    a,(hl)
                inc   hl
                or    (hl)
                jr    z,ksh_pop_nohandler
                pop   hl                         ; discard saved target entry
                pop   de                         ; DE = optional caller argument
                ld    a,(GB_MSG+1)
                cp    GB_SHELL_OPEN
                jr    nz,ksh_deliver
                ld    a,d
                or    e
                jp    z,ksh_bad
                ex    de,hl                      ; HL = caller's selected 8.3 name
                ld    de,WM_DRAGNAME             ; shared synchronous shell argument
                call  copy11

ksh_deliver
                ld    a,1
                ld    (SHELL_BUSY),a
                ld    a,(bank_cur)
                push  af                         ; caller page restored after target callback
                ld    a,(GB_MSG+3)
                call  wm_raise                   ; focus + z-top target
                call  wm_map_focus               ; bank target and publish its callback/menu
                ld    a,(GB_MSG+3)
                call  wm_entry
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   1,(hl)
                pop   hl
                call  nz,mw_publish              ; target gb_wm_x/y/w/h must be current
                xor   a
                ld    (GB_MSG+2),a               ; p1 = target response, initially OK
                ld    (GB_MSG+3),a               ; p2 = reserved
                ld    a,GB_MSG_SHELL
                ld    (GB_MSG),a
                ld    hl,(APP_HANDLER)
                call  md_call
                ld    a,(GB_MSG+2)
                ld    b,a
                xor   a
                ld    (SHELL_BUSY),a
                pop   af                         ; caller page: its C callback is still active
                push  bc
                call  bank_set
                call  wm_repaint_all             ; reflect activation/open/close deterministically
                pop   bc
                ld    a,b
                ret

ksh_pop_stale
                pop   hl                         ; target entry
                pop   hl                         ; caller argument
ksh_stale      ld    a,GB_SHELL_STALE
                ret
ksh_pop_nohandler
                pop   hl                         ; target entry
                pop   hl                         ; caller argument
                jp    ksh_nohandler
ksh_busy       ld    a,GB_SHELL_BUSY_RES
                ret
