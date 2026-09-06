; CPC keyboard matrix -> the inherited ASCII/control set, no firmware calls.
; One character per press/change; no repeat timer yet. Joystick bits are not
; text. Cursor keys drive the pointer and are not also typed (MSX behavior).
; Private launcher F3..F7 controls consume their keypad aliases too. They must
; not type digits into a focused APP before the root handles the command.
cpc_key_previous equ #3356
cpc_key_modifiers equ #3357
cpc_getkey
                call cpc_input_scan
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
                ld b,a
                ld a,(cpc_key_previous)
                cp b
                ld a,b
                ld (cpc_key_previous),a
                ret nz
                xor a
                ret
cpc_key_plain
                db 0,0,0,'9',0,0,13,'.'
                db 0,0,0,'8',0,'1','2','0'
                db 127,'[',13,']',0,0,92,0
                db '^','-','@','p',';',':','/','.'
                db '0','9','o','i','l','k','m',','
                db '8','7','u','y','h','j','n',' '
                db '6','5','r','t','g','f','b','v'
                db '4','3','e','w','s','d','c','x'
                db '1','2',27,'q',9,'a',0,'z'
                db 0,0,0,0,0,0,0,8
cpc_key_shift
                db 0,0,0,'9',0,0,13,'.'
                db 0,0,0,'8',0,'1','2','0'
                db 127,'{',13,'}',0,0,'|',0
                db '~','=','|','P','+','*','?','>'
                db '_',')','O','I','L','K','M','<'
                db '(','\'','U','Y','H','J','N',' '
                db '&','%','R','T','G','F','B','V'
                db '$','#','E','W','S','D','C','X'
                db '!',34,27,'Q',9,'A',0,'Z'
                db 0,0,0,0,0,0,0,8
