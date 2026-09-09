; Internal provider interface; not public APP memory or an advertised ABI.
; PKG_STATE: 22 fixed bytes. PKG_BUFFER: 512 disjoint fixed bytes.
; PKG_CURRENT, PKG_LOCK, PKG_MAPPED: fixed scheduler/bank cells.
; PKG_CAPS_LOW/PKG_CAPS_HIGH: addresses of the receiver's live capability words.
; PKG_MAP(A) updates native bank and shadow, preserves IX/IY.
; PKG_READ(HL=fixed buffer, BC<=512) -> A=0 success, BC=actual; no overrun.
; PKG_CLOSE -> A=0 success. Always releases the private stream, even on error.
; Providers preserve IX/IY and return the original bank, IFF and lock.
; Uses existing core owner/page routines plus streamed app_admission.asm.
PKG_BUSY equ PKG_STATE
PKG_STATUS equ PKG_STATE+1
PKG_OWNER equ PKG_STATE+2
PKG_PAGE equ PKG_STATE+4
PKG_NATIVE equ PKG_STATE+6
PKG_BACK equ PKG_STATE+7
PKG_TOTAL_SIZE equ PKG_STATE+8
PKG_PRIMARY_SIZE equ PKG_STATE+10
PKG_SECONDARY_SIZE equ PKG_STATE+12
PKG_ENTRY equ PKG_STATE+14
PKG_REMAIN equ PKG_STATE+16
PKG_DEST equ PKG_STATE+18
PKG_COUNT equ PKG_STATE+20
PKG_OK equ 0
PKG_ERR_FORMAT equ 1
PKG_ERR_IO equ 2
PKG_ERR_NOMEM equ 3
PKG_ERR_CONTEXT equ 4
PKG_ERR_NESTED equ 5
                assert PKG_STATE+22<=PKG_BUFFER | PKG_BUFFER+512<=PKG_STATE,"package state/transfer overlap"
                assert ((PKG_STATE>=0)&(PKG_STATE+22<=#4000))|((PKG_STATE>=#8000)&(PKG_STATE+22<=#10000)),"package state must remain fixed"
                assert ((PKG_BUFFER>=0)&(PKG_BUFFER+512<=#4000))|((PKG_BUFFER>=#8000)&(PKG_BUFFER+512<=#10000)),"package transfer must remain fixed"
                assert ((PKG_CAPS_LOW>=0)&(PKG_CAPS_LOW+2<=#4000))|((PKG_CAPS_LOW>=#8000)&(PKG_CAPS_LOW+2<=#10000)),"package low capabilities must remain fixed"
                assert ((PKG_CAPS_HIGH>=0)&(PKG_CAPS_HIGH+2<=#4000))|((PKG_CAPS_HIGH>=#8000)&(PKG_CAPS_HIGH+2<=#10000)),"package high capabilities must remain fixed"
