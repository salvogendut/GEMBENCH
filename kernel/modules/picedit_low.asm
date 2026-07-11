; PICEDIT low-RAM helper (#288/#371). Loaded as the second half of shipped .SPR files
; at #1600, so the GB_PICEDIT ABI slot can jump here without growing the resident
; CPC kernel. It runs below #4000, therefore it can page picture banks into
; #4000-#7FFF while the code and stack remain visible. Operations 0/1 move Paint
; tiles, 2 reads a short bank chunk, and 3 writes one for Browser's page cache.

                org   #1600

BANK_PORT       equ   #7F00
PCW_BANK1       equ   #F1
PIC_PAGE        equ   #130B
PIC_WB          equ   #130C
PIC_EDIT_BUF    equ   #134B
PIC_EDIT_OFF    equ   #134D
BANK_CUR        equ   #134F
fs_save_len     equ   #14FD
PIC_TMP         equ   #2200
PIC_TILE_WB     equ   25
PIC_TILE_H      equ   100
PIC_TILE_SZ     equ   PIC_TILE_WB*PIC_TILE_H

picedit_start
                or    a
                jr    z,pe_get
                dec   a
                jr    z,pe_put
                dec   a
                jr    z,pe_chunk
                dec   a
                jr    z,pe_write
                xor   a
                ret

pe_get          ld    a,(BANK_CUR)
                push  af
                call  pe_pic_to_tmp
                ld    d,a
                pop   af
                call  pe_bank_set
                ld    a,d
                or    a
                ret   z
                ld    hl,PIC_TMP
                ld    de,(PIC_EDIT_BUF)
                ld    bc,PIC_TILE_SZ
                ldir
                ld    a,1
                ret

pe_put          ld    hl,(PIC_EDIT_BUF)
                ld    de,PIC_TMP
                ld    bc,PIC_TILE_SZ
                ldir
                ld    a,(BANK_CUR)
                push  af
                call  pe_tmp_to_pic
                ld    d,a
                pop   af
                call  pe_bank_set
                ld    a,d
                ret

pe_chunk        ld    a,(BANK_CUR)
                push  af
                ld    hl,(PIC_EDIT_OFF)
                ld    de,(PIC_EDIT_BUF)
                ld    bc,(fs_save_len)
                call  pe_seg_get16
                jr    pe_rw_done

; Generic write used by Browser's rendered-page and source caches (#371/#373).
; The source is always in low RAM and the requested range stays in one 16K page.
pe_write        ld    a,(BANK_CUR)
                push  af
                ld    hl,(PIC_EDIT_OFF)
                ld    de,(PIC_EDIT_BUF)
                ld    bc,(fs_save_len)
                call  pe_seg_put16
pe_rw_done
                ld    d,a
                pop   af
                call  pe_bank_set
                ld    a,d
                ret

pe_pic_to_tmp   ld    de,PIC_TMP
                ld    b,PIC_TILE_H
pe_gt_row       push  bc
                ld    hl,(PIC_EDIT_OFF)
                ld    c,PIC_TILE_WB
                call  pe_seg_get
                or    a
                jr    z,pe_row_fail
                pop   bc
                push  bc
                ld    hl,(PIC_EDIT_OFF)
                ld    a,(PIC_WB)
                ld    c,a
                ld    b,0
                add   hl,bc
                ld    (PIC_EDIT_OFF),hl
                pop   bc
                djnz  pe_gt_row
                ld    a,1
                ret

pe_tmp_to_pic   ld    de,PIC_TMP
                ld    b,PIC_TILE_H
pe_pt_row       push  bc
                ld    hl,(PIC_EDIT_OFF)
                ld    c,PIC_TILE_WB
                call  pe_seg_put
                or    a
                jr    z,pe_row_fail
                pop   bc
                push  bc
                ld    hl,(PIC_EDIT_OFF)
                ld    a,(PIC_WB)
                ld    c,a
                ld    b,0
                add   hl,bc
                ld    (PIC_EDIT_OFF),hl
                pop   bc
                djnz  pe_pt_row
                ld    a,1
                ret
pe_row_fail     pop   bc
                xor   a
                ret

pe_seg_get      ld    b,0
pe_seg_get16    bit   6,h
                jr    nz,pe_sg_2
                ld    a,(PIC_PAGE)
                set   6,h
                jr    pe_sg_map
pe_sg_2         ld    a,(PIC_PAGE+61)         ; PIC_PAGE2 at #1348, keeps a 2-byte load
pe_sg_map       push  bc
                call  pe_bank_set
                pop   bc
                ldir
                ld    a,1
                ret

pe_seg_put      ld    b,0
pe_seg_put16
                bit   6,h
                jr    nz,pe_sp_2
                ld    a,(PIC_PAGE)
                set   6,h
                jr    pe_sp_map
pe_sp_2         ld    a,(PIC_PAGE+61)         ; PIC_PAGE2 at #1348
pe_sp_map       push  bc
                call  pe_bank_set
                pop   bc
                ex    de,hl
                ldir
                ex    de,hl
                ld    a,1
                ret

pe_bank_set     ld    (BANK_CUR),a
                ifdef PLATFORM_PCW
                out   (PCW_BANK1),a
                else
                ld    bc,BANK_PORT
                out   (c),a
                endif
                ret

picedit_end
                assert picedit_end-picedit_start<=256,"PICEDIT low helper exceeds #1600..#16FF"
                ifdef PLATFORM_PCW
                save  "build/pcw/PICEDITL.RAW",picedit_start,picedit_end-picedit_start
                else
                save  "build/PICEDITL.RAW",picedit_start,picedit_end-picedit_start
                endif
