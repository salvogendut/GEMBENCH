;; Fixed-slot installer and trampoline for the MSX2 M6 secondary-code gate.
        .module gbsecondary_gate
        .globl  _gb_secondary_install_copy_gate
        .globl  _gb_secondary_install_call_gate
        .globl  _gb_secondary_gate

        .area   _CODE

_gb_secondary_install_copy_gate::
        ld      hl, #copy_gate_template
        ld      de, #0xC8E0
        ld      bc, #copy_gate_end-copy_gate_template
        ldir
        ld      hl, (0xC014)          ; DOS2 PUT_P1 entry
        ld      (0xC8E4), hl          ; first CALL operand
        ld      (0xC8F7), hl          ; restore CALL operand
        ret

_gb_secondary_install_call_gate::
        ld      hl, #call_gate_template
        ld      de, #0xC8E0
        ld      bc, #call_gate_end-call_gate_template
        ldir
        ld      hl, (0xC014)
        ld      (0xC8EB), hl
        ld      (0xC8FB), hl
        ret

;; Tail-call the installed gate so its RET returns directly to the C caller.
_gb_secondary_gate::
        jp      0xC8E0

;; 26-byte load stub. BANK_CUR deliberately remains the primary page while no
;; mapped code executes; the root-task-only copy then restores that page.
copy_gate_template:
        ld      a, (0xC3E5)           ; target native mapper segment
        call    0x0000                ; patched PUT_P1
        ld      hl, #0xC400           ; fixed transfer source
        ld      de, (0xC3E0)          ; destination in secondary page
        ld      bc, (0xC3DA)          ; bounded byte count
        ldir
        ld      a, (0x134F)           ; primary BANK_CUR shadow
        call    0x0000                ; patched PUT_P1
        ret
copy_gate_end:

;; 31-byte call stub. The primary segment is retained on the fixed stack and
;; BANK_CUR follows the mapped secondary so kernel services restore it. The
;; reverse mapper call is atomic: an IM1 tick must not observe a primary shadow
;; with the secondary page still mapped (or vice versa).
call_gate_template:
        ld      a, (0x134F)
        push    af
        ld      a, (0xC3E5)
        ld      (0x134F), a
        call    0x0000                ; patched PUT_P1
        ld      hl, #0xC8F5           ; fixed return below
        push    hl
        ld      hl, (0xC3DC)          ; validated secondary entry
        jp      (hl)
        pop     af                    ; 0xC8F5: restore primary segment
        di
        ld      (0x134F), a
        call    0x0000                ; patched PUT_P1
        ei
        ret
call_gate_end:
