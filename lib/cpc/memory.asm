; Explicit 512-KiB admission, before any app/page allocation. Probe all 29
; distinct aperture mappings through the production bank gate, not shadows.
; Destructive to the first two bytes of these unallocated pages. IRQ excluded.
; CF=1 admitted, CF=0 alias/missing memory; always restores C0.
cpc_memory_admit
                ld ix,cpc_memory_pages
                ld e,29
cpc_memory_seed
                ld a,(ix+0)
                call foundation_bank_set
                ld (#4000),a
                cpl
                ld (#4001),a
                inc ix
                dec e
                jr nz,cpc_memory_seed
                ld ix,cpc_memory_pages
                ld e,29
cpc_memory_check
                ld a,(ix+0)
                call foundation_bank_set
                ld d,a
                ld a,(#4000)
                cp d
                jr nz,cpc_memory_fail
                cpl
                ld d,a
                ld a,(#4001)
                cp d
                jr nz,cpc_memory_fail
                inc ix
                dec e
                jr nz,cpc_memory_check
                ld a,#C0
                call foundation_bank_set
                scf
                ret
cpc_memory_fail
                ld a,#C0
                call foundation_bank_set
                or a
                ret
cpc_memory_pages
                db #C0,#C4,#C5,#C6,#C7,#CC,#CD,#CE,#CF
                db #D4,#D5,#D6,#D7,#DC,#DD,#DE,#DF
                db #E4,#E5,#E6,#E7,#EC,#ED,#EE,#EF,#F4,#F5,#F6,#F7
