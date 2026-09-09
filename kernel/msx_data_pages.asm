; Optional boot-loaded fixed module. No kernel child-COM or app limit grows.
PLATFORM_MSX equ 1
                include "../lib/gbapp.inc"
                include "../lib/msx/glue.inc"
PREEMPTIVE equ 1
                include "lowram.inc"
CORE_APP_CODE_NATIVE equ MSX_APP_CODE_NATIVE
CORE_APP_FLAGS equ MSX_APP_FLAGS
CORE_PAGE_PURPOSE equ MSX_PAGE_PURPOSE
CORE_PAGE_NATIVE equ MSX_PAGE_NATIVE
DATA_CURRENT equ SCHED_CURRENT
DATA_MAPPED equ BANK_CUR
DATA_REQUEST equ MSX_FSCTX_REQ
DATA_TRANSFER equ MSX_FSCTX_TRANSFER
DATA_OWNER_CURRENT equ GB_OWNER
DATA_MAP equ msx_data_map
                org MSX_DATA_PAGE_ENTRY
                jp msx_data_pages
                db "GBDP",1
msx_data_pages
                push ix
                ld a,i
                push af
                di
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                call data_page_dispatch
                ld d,a
                di
                pop af
                ld (SCHED_LOCK),a
                pop af
                ld a,d
                pop ix
                ret po
                ei
                ret
; Reuse the existing resident owner/page operations; the module does not
; contain its own allocator. No dependence on scratch result registers.
page_alloc_owned
                xor a
                jp GB_PAGE
page_check_owned
                ld a,2
                jp GB_PAGE
page_free_owned
                ld a,1
                jp GB_PAGE
msx_data_map
                ld (BANK_CUR),a
                push ix
                push hl
                push de
                ld hl,(MSX_PUTP1)
                call data_jp_hl
                pop de
                pop hl
                pop ix
                ret
data_jp_hl      jp (hl)
                include "core/data_pages.asm"
data_module_end
                print "Data-page module bytes: ", {int}data_module_end-MSX_DATA_PAGE_ENTRY
                assert data_module_end<=MSX_DATA_PAGE_LIMIT,"data-page module exceeds reserved fixed RAM"
                assert data_module_end-MSX_DATA_PAGE_ENTRY==MSX_DATA_PAGE_SIZE,"update data-page module size"
                save "GBDPAGE.RAW",MSX_DATA_PAGE_ENTRY,MSX_DATA_PAGE_SIZE
