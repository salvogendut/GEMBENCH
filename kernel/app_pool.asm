; kernel/app_pool.asm - detected bank-page pool for resident windows and modules.

                ifdef PLATFORM_MSX
                include "msx_page_pool.asm"
                else

; app_pool_init (#84): build the app-page pool from the detected bank count
; (md_banks). Index 0..2 = bank 0 blocks 1..3 (#C5..#C7; block 0 is PAGE_DATA);
; then each further bank contributes all four blocks (&C4 + bank*8 + block), the
; same value lib/bank.asm's bank_page forms. Appends until the list reaches
; WM_MAXWIN entries or RAM runs out. Sets APP_NPAGES; zeroes APP_BUSY. So the
; desktop (first claim) always lands in APP_PAGES[0] = PAGE_APP0 = #C5, and a
; plain 128K machine yields exactly 3 pages (desktop + 2), as before.
                ifndef PLATFORM_MSX           ; (the MSX pool is built from DOS 2 mapper
                ifndef PLATFORM_PCW           ;  segments - kernel/boot_msx.asm, #287; the
app_pool_init                                  ;  PCW pool is fixed blocks - boot_pcw.asm, #331)
                ld    hl,APP_PAGES
                ld    (hl),#C5               ; bank 0 block 1
                inc   hl
                ld    (hl),#C6               ; bank 0 block 2
                inc   hl
                ld    (hl),#C7               ; bank 0 block 3
                inc   hl
                ld    c,3                      ; C = entries so far
                ld    a,(md_banks)
                ld    b,a                      ; B = detected bank count
                ld    d,1                      ; D = bank index, from 1
api_bank        ld    a,d
                cp    b
                jr    nc,api_done             ; bank index >= count -> done
                ld    a,d
                add   a,a
                add   a,a
                add   a,a                      ; A = bank*8
                add   a,#C4                     ; A = &C4 + bank*8 (this bank's block 0)
                ld    e,a                       ; E = current port value
                add   a,4
                ld    (api_end),a              ; sentinel = base + 4 (one past block 3)
api_blk         ld    a,c
                cp    WM_MAXWIN
                jr    nc,api_done             ; list full -> stop
                ld    (hl),e                    ; store this block's port value
                inc   hl
                inc   c
                inc   e
                ld    a,(api_end)
                cp    e
                jr    nz,api_blk               ; more blocks in this bank
                inc   d                          ; next bank
                jr    api_bank
api_done        ld    a,c
                ld    (APP_NPAGES),a
                ld    hl,APP_BUSY              ; mark every page free
                ld    de,APP_BUSY+1
                ld    bc,WM_MAXWIN-1
                ld    (hl),0
                ldir
                ret
api_end         db    0
md_banks        db    0
                endif                          ; (ifndef PLATFORM_PCW around app_pool_init)
                endif                          ; (ifndef PLATFORM_MSX around app_pool_init)

; wm_alloc_page: claim the lowest free app page -> A = its port value, or 0 if all
; APP_NPAGES pages are in use. wm_free_page: A = the port value to release. The pool
; serves co-resident WM windows and the initial desktop boot page.
wm_alloc_page
                ld    a,(APP_NPAGES)
                or    a
                ret   z                         ; (defensive) no pages at all
                ld    b,a                        ; B = page count
                ld    hl,APP_BUSY
                ld    de,APP_PAGES
wap_scan        ld    a,(hl)
                or    a
                jr    z,wap_take                ; busy flag clear -> free slot
                inc   hl
                inc   de
                djnz  wap_scan
                xor   a                          ; none free
                ret
wap_take        ld    (hl),1                     ; mark busy
                ld    a,(de)                      ; A = its port value
                ret
wm_free_page                                     ; A = port value to release
                ld    b,a                         ; B = target port
                ld    a,(APP_NPAGES)
                or    a
                ret   z
                ld    c,a                          ; C = page count
                ld    hl,APP_PAGES
                ld    de,APP_BUSY
wfp_scan        ld    a,(hl)
                cp    b
                jr    z,wfp_hit
                inc   hl
                inc   de
                dec   c
                jr    nz,wfp_scan
                ret                                ; not found (defensive)
wfp_hit         xor   a
                ld    (de),a                       ; clear the parallel busy flag
                ret
                endif                          ; PLATFORM_MSX
