; Opt-in boot composition. All code runs in resident page 2; the child COM at
; #0100 is dead. No application/IRQ may use these modules before this returns C.
; Exact sizes and versioned headers reject absent, mixed or truncated modules.
package_modules_load
                ld hl,package_modules
package_modules_next
                ld a,(hl)
                or a
                jr z,package_modules_complete
                ld de,fs_req_name
                call copy11
                ld de,fs_load_dst
                ld bc,4                        ; descriptor destination + capacity
                ldir
                push hl                        ; expected signature, then next record
                call fs_load_sys
                pop de
                ret nc
                push de
                ld hl,(fs_ent_size+2)
                ld a,h
                or l
                jr nz,package_modules_size_bad
                ld de,(fs_load_max)             ; loader leaves request fields intact
                ld hl,(fs_ent_size)
                or a
                sbc hl,de
package_modules_size_bad
                pop de
                jr nz,package_modules_bad
                ld hl,(fs_load_dst)
                ld a,(hl)
                cp #C3
                jr nz,package_modules_bad
                inc hl
                inc hl
                inc hl
                call package_module_signature
                ret nc
                ex de,hl                       ; comparison advanced past signature
                jr package_modules_next
package_modules_complete
                ; The high image also contains the existing data-page module.
                ld a,(MSX_DATA_PAGE_ENTRY)
                cp #C3
                jr nz,package_modules_bad
                ld hl,MSX_DATA_PAGE_ENTRY+3
                ld de,package_data_signature
package_module_signature
                ld b,5
package_module_compare
                ld a,(de)
                cp (hl)
                jr nz,package_modules_bad
                inc hl
                inc de
                djnz package_module_compare
                scf
                ret
package_modules_bad
                xor a
                ret
package_modules
                db "GBAPV4  MOD"
                dw MSX_GBAP4_GATE,MSX_GBAP4_GATE_SIZE
                ifdef PORTABLE_FS_HANDOFF
                db "GBV4",7
                else
                db "GBV4",5
                endif
                db "GBPKFIX MOD"
                dw MSX_PACKAGE_IO_BASE,MSX_PACKAGE_IMAGE_SIZE
                db "GBIO",3
                db "GBPKLOADMOD"
                dw MSX_PACKAGE_ENTRY,MSX_PACKAGE_CODE_SIZE
                db "GBPK",2
                db "GBPKWM  MOD"
                dw MSX_PACKAGE_ROUTE_BASE,MSX_PACKAGE_ROUTE_SIZE
                ifdef PORTABLE_FS_HANDOFF
                db "GBWM",#60|MSX_SCREEN_MODE
                else
                db "GBWM",#40|MSX_SCREEN_MODE
                endif
                db 0
package_data_signature db "GBDP",1
