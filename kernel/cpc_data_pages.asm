; Called within serialized GB_PARAMS. Keep the hardware IRQ out of bank/copy
; boundaries and restore its incoming state; never call the pointer renderer
; while the data page replaces primary code. Transfer is at most 512 bytes.
DATA_CURRENT equ SCHED_CURRENT
DATA_MAPPED equ BANK_CUR
DATA_REQUEST equ #2400
DATA_TRANSFER equ #1500
DATA_OWNER_CURRENT equ owner_current
DATA_MAP equ bank_set
cpc_data_pages
                ld a,i
                push af
                di
                call data_page_dispatch
                pop af
                ret po
                ei
                ret
                include "core/data_pages.asm"
