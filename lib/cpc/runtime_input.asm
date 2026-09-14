; CPC keyboard matrix -> the inherited ASCII/control set, no firmware calls.
; One character per press/change; no repeat timer yet. Joystick bits are not
; text. Cursor keys drive the pointer by default; the private document receiver
; delivers them to explicit text windows, with Ctrl restoring pointer access.
; Private launcher F2..F7 controls consume their keypad aliases too. They must
; not type digits into a focused APP before the root handles the command.
cpc_key_previous equ #3356
cpc_key_modifiers equ #3357
cpc_getkey
                call cpc_input_scan
                ifdef PORTABLE_FS_HANDOFF
                ; Text windows use the window manager's close/cancel event.
                ; Never claim Escape here: a scan can see the press between
                ; POLL and GB_MSG_FRAME, when EDIT would discard ASCII 27.
                ld a,(CPC_KEYS+8)
                bit 2,a
                jr nz,cpc_key_escape_ready
                call cpc_text_focus
                or a
                jr z,cpc_key_escape_ready
                ld hl,CPC_KEYS+8
                set 2,(hl)
cpc_key_escape_ready
                endif
                ld a,(CPC_KEYS+2)
                ld (cpc_key_modifiers),a
                ld hl,CPC_KEYS
                ld de,cpc_key_plain
                bit 5,a
                jr nz,cpc_key_scan
                ld de,cpc_key_shift
cpc_key_scan
                ld b,10
cpc_key_row
                ld a,(hl)
                inc hl
                ld c,8
cpc_key_bit
                rrca
                jr c,cpc_key_next
                push af
                ld a,(de)
                or a
                jr nz,cpc_key_found
                pop af
cpc_key_next
                inc de
                dec c
                jr nz,cpc_key_bit
                djnz cpc_key_row
                xor a
                jr cpc_key_publish
cpc_key_found
                pop bc
                ld b,a
                ld a,(cpc_key_modifiers)
                bit 7,a
                ld a,b
                jr nz,cpc_key_publish
                and #DF
                cp 'A'
                jr c,cpc_key_original
                cp 'Z'+1
                jr nc,cpc_key_original
                and #1F
                jr cpc_key_publish
cpc_key_original
                ld a,b
cpc_key_publish
                ifdef PORTABLE_FS_HANDOFF
                push af
                call cpc_text_mode
                or a
                pop bc
                ld a,b
                jr nz,cpc_text_key_ready
                cp 28
                jr c,cpc_text_key_ready
                cp 32
                jr c,cpc_text_key_drop      ; arrows belong to pointer outside text focus
                jr nz,cpc_text_key_ready
                ld a,(cpc_key_modifiers)
                bit 7,a
                ld a,b
                jr nz,cpc_text_key_ready
                push bc
                call cpc_text_focus
                or a
                pop bc
                ld a,b
                jr z,cpc_text_key_ready     ; preserve native Ctrl+Space behavior
cpc_text_key_drop
                xor a                      ; Ctrl+Space clicks, never types
cpc_text_key_ready
                endif
                ld b,a
                ld a,(cpc_key_previous)
                cp b
                ld a,b
                ld (cpc_key_previous),a
                ret nz
                xor a
                ret
cpc_key_plain
                ifdef PORTABLE_FS_HANDOFF
                db 30,28,31,'9',0,0,13,'.'
                db 29,0,0,'8',0,'1',0,'0'
                else
                db 0,0,0,'9',0,0,13,'.'
                db 0,0,0,'8',0,'1',0,'0'
                endif
                db 127,'[',13,']',0,0,92,0
                db '^','-','@','p',';',':','/','.'
                db '0','9','o','i','l','k','m',','
                db '8','7','u','y','h','j','n',' '
                db '6','5','r','t','g','f','b','v'
                db '4','3','e','w','s','d','c','x'
                db '1','2',27,'q',9,'a',0,'z'
                db 0,0,0,0,0,0,0,8
cpc_key_shift
                ifdef PORTABLE_FS_HANDOFF
                db 30,28,31,'9',0,0,13,'.'
                db 29,0,0,'8',0,'1',0,'0'
                else
                db 0,0,0,'9',0,0,13,'.'
                db 0,0,0,'8',0,'1',0,'0'
                endif
                db 127,'{',13,'}',0,0,'|',0
                db '~','=','|','P','+','*','?','>'
                db '_',')','O','I','L','K','M','<'
                db '(','\'','U','Y','H','J','N',' '
                db '&','%','R','T','G','F','B','V'
                db '$','#','E','W','S','D','C','X'
                db '!',34,27,'Q',9,'A',0,'Z'
                db 0,0,0,0,0,0,0,8
