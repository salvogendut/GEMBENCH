; CPC implementation of GB_APP operation 8 (kernel-owned managed-window drag).
; Loaded on demand into the ordinary PAGE_DATA module window. Keeping it there
; avoids both the CPC resident stack gap and the #2200 title/validator workspace.

GB_POLL         equ   #801E
GB_FRAME        equ   #8021
GB_CURHIDE      equ   #8024
GB_WMSETPOS     equ   #8066
GB_WMSETSIZE    equ   #8099
GB_WMDAMAGE     equ   #80B4
GB_BACKDROP     equ   #80B7
GB_RESTPAR      equ   #8057
GB_CURSHOW      equ   #801B

POLL_MX         equ   #1306
POLL_MY         equ   #1307
POLL_FLAGS      equ   #1308
MW_RECT         equ   #1448
                ifndef PREEMPTIVE
PREEMPTIVE      equ   0
                endif
                if PREEMPTIVE
CPC_MAXED       equ   #3EB2
CPC_MAX_SAVE    equ   #3EB3
                else
CPC_MAXED       equ   #3CB2
CPC_MAX_SAVE    equ   #3CB3
                endif

                org   #6000
cpc_drag_entry
                ld    a,(MW_RECT)
                ld    hl,MW_RECT+2
                add   a,(hl)
                sub   4
                ld    b,a
                ld    a,(POLL_MX)
                cp    b
                jp    nc,cpc_maximize
                ld    hl,MW_RECT
                ld    de,drag_x
                ld    bc,4
                ldir
                ld    a,(POLL_MX)
                ld    hl,drag_x
                sub   (hl)
                ld    (drag_dx),a
                ld    a,(POLL_MY)
                ld    hl,drag_y
                sub   (hl)
                ld    (drag_dy),a
                xor   a
                ld    (drag_moved),a

drag_loop       call  GB_POLL
                ld    a,(POLL_FLAGS)
                bit   2,a
                jr    z,drag_done

                ld    a,(POLL_MX)
                ld    hl,drag_dx
                sub   (hl)
                jr    nc,drag_x_nonnegative
                xor   a
drag_x_nonnegative
                ld    b,a
                ld    a,80
                ld    hl,drag_w
                sub   (hl)
                cp    b
                jr    nc,drag_x_clamped
                ld    b,a
drag_x_clamped
                ld    a,(POLL_MY)
                ld    hl,drag_dy
                sub   (hl)
                jr    nc,drag_y_nonnegative
                xor   a
drag_y_nonnegative
                cp    8
                jr    nc,drag_y_below_bar
                ld    a,8
drag_y_below_bar
                ld    c,a
                ld    a,200
                ld    hl,drag_h
                sub   (hl)
                cp    c
                jr    nc,drag_y_clamped
                ld    c,a
drag_y_clamped
                ld    a,(drag_x)
                cp    b
                jr    nz,drag_changed
                ld    a,(drag_y)
                cp    c
                jr    z,drag_loop

drag_changed    push  bc
                call  GB_CURHIDE
                ld    a,(drag_x)
                ld    b,a
                ld    a,(drag_y)
                ld    c,a
                ld    a,(drag_w)
                ld    d,a
                ld    a,(drag_h)
                ld    e,a
                call  GB_BACKDROP
                pop   bc
                ld    a,b
                ld    (drag_x),a
                ld    a,c
                ld    (drag_y),a
                ld    a,(drag_w)
                ld    d,a
                ld    a,(drag_h)
                ld    e,a
                ld    a,3
                call  GB_FRAME
                ld    a,1
                ld    (drag_moved),a
                call  GB_CURSHOW
                jr    drag_loop

drag_done       ld    a,(drag_moved)
                or    a
                ret   z
                call  GB_CURHIDE
                ld    a,(drag_x)
                ld    b,a
                ld    a,(drag_y)
                ld    c,a
                ld    a,(drag_w)
                ld    d,a
                ld    a,(drag_h)
                ld    e,a
                call  GB_BACKDROP
                call  GB_CURSHOW
                ld    a,(drag_y)
                ld    l,a
                ld    a,(drag_x)
                call  GB_WMSETPOS
                call  GB_RESTPAR
                xor   a
                ret

; The compact resident CPC WM routes a title click through this module. A click
; in the rightmost four byte-columns toggles the standard maximize gadget. Its
; one saved rectangle matches the inherited resident implementation's contract.
cpc_maximize
                ld    a,(CPC_MAXED)
                or    a
                jr    nz,cpc_max_restore
                ld    hl,MW_RECT
                ld    de,CPC_MAX_SAVE
                ld    bc,4
                ldir
                ld    a,1
                ld    (CPC_MAXED),a
                xor   a
                ld    l,8
                call  GB_WMSETPOS
                ld    a,80
                ld    l,192
                call  GB_WMSETSIZE
                jr    cpc_max_repaint
cpc_max_restore
                xor   a
                ld    (CPC_MAXED),a
                ld    a,(CPC_MAX_SAVE)
                ld    hl,CPC_MAX_SAVE+1
                ld    l,(hl)
                call  GB_WMSETPOS
                ld    a,(CPC_MAX_SAVE+2)
                ld    hl,CPC_MAX_SAVE+3
                ld    l,(hl)
                call  GB_WMSETSIZE
cpc_max_repaint
                ld    b,0
                ld    c,8
                ld    d,80
                ld    e,192
                call  GB_WMDAMAGE
                call  GB_RESTPAR
                xor   a
                ret

drag_x          db    0
drag_y          db    0
drag_w          db    0
drag_h          db    0
drag_dx         db    0
drag_dy         db    0
drag_moved      db    0
cpc_drag_end
                save  "build/cpc/GBDRAG.RAW",cpc_drag_entry,cpc_drag_end-cpc_drag_entry
