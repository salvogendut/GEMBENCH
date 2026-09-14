; Sealed computation-only secondary calls. Shared policy; no platform I/O.
; Table: eight bytes per owner slot: generation, page id/gen, entry, size, zero.
; Bind takes IX -> trusted completed-load record {owner,page,entry,size} (words).
; Public call takes HL=primary in/out bytes, BC=1..512; A=GB_PARAMS status, E=bool.
; A raw SECONDARY_CODE allocation is never executable through this gate.

secondary_seal_bind
                ld a,(SEC_BUSY)
                or a
                jp nz,sec_bind_bad
                ld a,(SEC_LOCK)
                or a
                ret z
                ld e,(ix+0)
                ld d,(ix+1)
                ld hl,(CORE_PENDING_OWNER)
                or a
                sbc hl,de
                jp nz,sec_bind_bad
                call sec_owner_context
                jp nc,sec_bind_bad
                ld a,e
                dec a
                call sec_table_slot
                push hl
                pop iy
                ld a,(iy+0)
                or a
                jp nz,sec_bind_bad             ; immutable until release/reset
                ld l,(ix+2)
                ld h,(ix+3)
                call page_check_owned
                or a
                jp nz,sec_bind_bad
                ld a,(ix+2)
                call sec_page_purpose
                jp nz,sec_bind_bad
                ld l,(ix+4)
                ld h,(ix+5)
                ld c,(ix+6)
                ld b,(ix+7)
                call sec_entry_bounds
                jp nc,sec_bind_bad
                push ix
                pop hl
                inc hl
                inc hl
                push iy
                pop de
                inc de
                ld bc,6
                ldir
                ld (iy+7),0
                ld a,(ix+1)
                ld (iy+0),a                    ; publish owner generation last
                scf
                ret
sec_bind_bad    or a
                ret

; C=owner slot; preserve BC/DE for owner_reset/reclaim callers.
secondary_seal_clear
                push bc
                push de
                ld a,c
                call sec_table_slot
                ld b,8
                xor a
sec_clear_byte  ld (hl),a
                inc hl
                djnz sec_clear_byte
                pop de
                pop bc
                ret

; C=page pool index, BEFORE freeing its owner/purpose fields. Invalidate even
; on raw/native frees: generation wrap must not resurrect an executable seal.
secondary_seal_page_release
                push bc
                push de
                ld hl,CORE_PAGE_OWNER
                ld a,c
                add a,l
                ld l,a
                ld a,(hl)
                dec a
                cp SEC_OWNER_MAX
                jr nc,sec_release_done
                ld e,a
                call sec_table_slot
                inc hl
                ld a,c
                inc a
                cp (hl)
                jr nz,sec_release_done
                ld c,e
                call secondary_seal_clear
sec_release_done
                pop de
                pop bc
                ret

secondary_call
                push ix
                push iy
                ld a,i
                push af
                di
                ld a,(SEC_LOCK)
                push af
                ld a,1
                ld (SEC_LOCK),a
                call sec_dispatch
                ld d,a
                di
                pop af
                ld (SEC_LOCK),a
                pop af
                ld a,d
                pop iy
                pop ix
                ret po
                ei
                ret
sec_dispatch
                ld a,(SEC_BUSY)
                or a
                jp nz,sec_busy_error
                ld a,(SEC_CURRENT)
                or a
                jp nz,sec_context
                ld a,b
                or c
                jp z,sec_bad
                push hl
                ld hl,512
                or a
                sbc hl,bc
                pop hl
                jp c,sec_bad
                ld a,h
                cp #40
                jp c,sec_bad
                push hl
                add hl,bc
                jr c,sec_span_bad
                ld de,#7F00
                or a
                sbc hl,de
                jr c,sec_span_ok
                jr z,sec_span_ok
sec_span_bad    pop hl
                jp sec_bad
sec_span_ok     pop hl
                ld (SEC_POINTER),hl
                ld (SEC_LENGTH),bc
                ; The root stack must stay mapped and have at least 256 bytes
                ; before an aperture boundary. No banked application stack.
                ld hl,0
                add hl,sp
                ld a,h
                cp #81
                jr nc,sec_stack_ok
                cp #40
                jp nc,sec_context
                cp 1
                jp c,sec_context
sec_stack_ok
                call SEC_OWNER_CURRENT
                call sec_owner_context
                jp nc,sec_context
                ld a,e
                dec a
                call sec_table_slot
                push hl
                pop ix
                ld a,(ix+0)
                cp d
                jp nz,sec_stale
                ld l,(ix+1)
                ld h,(ix+2)
                call page_check_owned
                or a
                jp nz,sec_stale
                ld a,(ix+1)
                call sec_page_purpose
                jp nz,sec_stale
                ld l,(ix+3)
                ld h,(ix+4)
                ld c,(ix+5)
                ld b,(ix+6)
                call sec_entry_bounds
                jp nc,sec_stale
                ld (SEC_ENTRY),hl
                ld a,(ix+1)
                dec a
                ld hl,CORE_PAGE_NATIVE
                add a,l
                ld l,a
                ld a,(hl)
                ld (SEC_NATIVE),a
                ld a,(SEC_MAPPED)
                ld (SEC_BACK),a
                ld a,1
                ld (SEC_BUSY),a
                ; Clear unused bytes too: no previous caller's data is visible
                ; to the leaf even when its command uses a short copied block.
                ld hl,SEC_TRANSFER
                ld de,SEC_TRANSFER+1
                ld bc,511
                ld (hl),0
                ldir
                ld hl,(SEC_POINTER)
                ld de,SEC_TRANSFER
                ld bc,(SEC_LENGTH)
                ldir
                ld a,(SEC_NATIVE)
                call SEC_MAP
                if SEC_ALLOW_IRQ
                ei                             ; fixed ISR only, scheduler remains locked
                endif
                call sec_invoke
                di
                ld a,(SEC_BACK)
                call SEC_MAP
                ld hl,SEC_TRANSFER
                ld de,(SEC_POINTER)
                ld bc,(SEC_LENGTH)
                ldir                           ; copy out only after primary restoration
                xor a
                ld (SEC_BUSY),a
                ld e,1
                ret
sec_invoke
                ld hl,(SEC_ENTRY)
                push hl                        ; target + fixed continuation on root stack
                ld hl,SEC_TRANSFER
                ld bc,(SEC_LENGTH)
                ret
sec_bad         ld a,1
                jr sec_error
sec_context     ld a,2
                jr sec_error
sec_stale       ld a,3
                jr sec_error
sec_busy_error  ld a,5
sec_error       ld e,0
                ret

; DE=owner, CF iff live, nonterminating, current root primary. Preserves IX/IY.
sec_owner_context
                ld a,(SEC_CURRENT)
                or a
                ret nz
                call owner_validate
                ret nc
                ld a,e
                dec a
                ld hl,CORE_APP_FLAGS
                add a,l
                ld l,a
                bit 2,(hl)
                jr nz,sec_owner_bad
                ld a,e
                dec a
                ld hl,CORE_APP_CODE_NATIVE
                add a,l
                ld l,a
                ld a,(SEC_MAPPED)
                cp (hl)
                jr nz,sec_owner_bad
                scf
                ret
sec_owner_bad   or a
                ret
sec_table_slot
                add a,a
                add a,a
                add a,a
                add a,SEC_TABLE & #FF
                ld l,a
                ld h,SEC_TABLE >> 8            ; integer byte, not rounded RASM division
                ret
sec_page_purpose
                dec a
                ld hl,CORE_PAGE_PURPOSE
                add a,l
                ld l,a
                ld a,(hl)
                cp 7
                ret
; HL=entry, BC=loaded secondary size. Preserve HL/BC, CF iff sealed range valid.
sec_entry_bounds
                push hl
                ld hl,#3F00
                or a
                sbc hl,bc
                jr c,sec_entry_bad
                pop hl
                push hl
                ld de,#4008
                or a
                sbc hl,de
                jr c,sec_entry_bad
                ld de,8
                add hl,de                      ; entry offset, must be < loaded size
                or a
                sbc hl,bc
                jr nc,sec_entry_bad
                pop hl
                scf
                ret
sec_entry_bad   pop hl
                or a
                ret

                assert (SEC_TABLE & #FF)+8*SEC_OWNER_MAX<=256,"seal table crosses index page"
                assert SEC_TRANSFER+512<=SEC_TABLE | SEC_TABLE+8*SEC_OWNER_MAX<=SEC_TRANSFER,"seal table/transfer overlap"
                assert SEC_STATE+12<=SEC_TRANSFER | SEC_TRANSFER+512<=SEC_STATE,"seal state/transfer overlap"
                assert SEC_STATE+12<=SEC_TABLE | SEC_TABLE+8*SEC_OWNER_MAX<=SEC_STATE,"seal state/table overlap"
