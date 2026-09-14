; Bounded caller-primary -> resident configuration publication. HL=text,
; BC=length. k_shell has already rejected nested/worker calls. The span check
; keeps HL/BC intact; length is published only after complete validation.
config_publish
                ld a,b
                cp 2
                jr c,config_publish_valid
                jr nz,config_publish_bad
                ld a,c
                or a
                jr nz,config_publish_bad
config_publish_valid
                ld a,h
                cp #40
                jr c,config_publish_bad
                push hl
                add hl,bc
                jr c,config_publish_span_bad
                ld a,h
                cp #7F
                jr c,config_publish_span_good
                jr nz,config_publish_span_bad
                ld a,l
                or a
                jr nz,config_publish_span_bad
config_publish_span_good
                pop hl
                push bc
                ld a,b
                or c
                jr z,config_publish_copied
                ld de,CONFIG_PUBLISH_TEXT
                ldir
config_publish_copied
                pop bc
                ld (CONFIG_PUBLISH_LENGTH),bc  ; publish only after the copy completes
                xor a
                ret
config_publish_span_bad
                pop hl
config_publish_bad
                ld a,4                         ; GB_SHELL_BAD_REQUEST
                ret
