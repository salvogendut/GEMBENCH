; kernel/memdetect.asm - CPC expansion RAM probing.

; (fmt_mem migrated to the GBCFG C module: gb_fmt_mem in kernel/kc/kcfg.c. The
; kernel leaves the KB count in KCFG_MEMKB before cfg_boot; the module writes the
; "<decimal>K" string to KCFG_MEMSTR, which draw_topbar renders.)

; mem_detect: count present 64K expansion banks and return the total in A.
;
; Yarek (CPC4MB) banking (#138): a bank's 64K block 0 is paged into #4000-#7FFF
; by OUT (&7Fhi00),&C4|group<<3 (mode 4), where the port high byte selects the
; upper bank group INVERTED - &7F = banks 0-7 (DK'tronics), &7E = 8-15 (Yarek
; 1MB), &7D/&7C = 16-31. So bank b lives at port (&7F-(b>>3)), group (b&7);
; md_page forms that. We scan b=0.. writing a per-bank signature and reading it
; back, stopping at the first bank that is absent OR mirrors bank 0 (1984 and
; real Yarek alias absent banks down to the first expansion bank) - which keeps
; a 576K machine from being mis-counted as 1MB. MUST run resident and BEFORE
; PAGE_DATA is filled (it pokes every bank's #4000). Returns A = bank count.
mem_detect
                ld    hl,(#4000)             ; preserve the live #4000 word
                ld    (md_save),hl
                xor   a
                ld    (md_count),a
                ; --- 64K guard: confirm banked RAM is distinct from main memory.
                ; On a 64K machine the GA ignores banking, so every "bank" is just
                ; main #4000 and would be mis-counted; bail out reporting zero. ---
                ld    bc,#7FC0
                out   (c),c                  ; standard config: #4000 = main RAM
                ld    a,#A5
                ld    (#4000),a              ; marker in main memory
                xor   a
                call  md_page                ; page expansion bank 0 over #4000
                ld    a,#5A
                ld    (#4000),a              ; different marker into the bank
                ld    bc,#7FC0
                out   (c),c                  ; back to main
                ld    a,(#4000)
                cp    #A5                    ; main untouched -> banking works
                jr    nz,md_done             ; clobbered -> 64K, no expansion
                ; --- scan banks, writing/verifying a signature per bank.
                ; E = bank index (full_bg); md_page preserves D/E/H. ---
                ld    e,0
md_loop
                ld    a,e
                call  md_page                ; select bank E
                ld    a,e
                ld    (#4000),a              ; signature lo = index
                cpl
                ld    (#4001),a              ; signature hi = ~index
                xor   a
                call  md_page                ; re-select bank 0 (mirror reference)
                ld    a,(#4000)
                or    a                       ; bank 0 still holds its 0 ?
                jr    nz,md_done             ; corrupted -> bank E aliased bank 0
                ld    a,(#4001)
                inc   a                       ; bank 0 hi still #FF ? (inc #FF -> 0)
                jr    nz,md_done
                ld    a,e
                call  md_page                ; back to bank E
                ld    a,(#4000)
                cp    e                       ; bank E holds its own signature ?
                jr    nz,md_done
                ld    a,(#4001)
                ld    d,a
                ld    a,e
                cpl
                cp    d
                jr    nz,md_done
                ld    hl,md_count            ; bank E present and distinct
                inc   (hl)
                inc   e
                ld    a,e
                cp    16                      ; 16 banks = 1MB (Yarek/1984 cap)
                jr    nz,md_loop
md_done
                ld    bc,#7FC0               ; leave the standard 64K config selected
                out   (c),c
                ld    hl,(md_save)
                ld    (#4000),hl
                ld    a,(md_count)
                ret
; md_page: A = bank index (full_bg 0..15). Pages that 64K bank's block 0 into
; #4000-#7FFF (mode 4). Port hi = &7F-(idx>>3); value = &C4|(idx&7)<<3. Trashes
; A,B,C,L; preserves D/E/H so the scan loop's index survives.
md_page
                ld    c,a
                srl   a
                srl   a
                srl   a                       ; A = bank_high (idx>>3)
                ld    b,a
                ld    a,#7F
                sub   b                       ; A = &7F - bank_high (port high byte)
                ld    b,a
                ld    a,c
                and   7                        ; group = idx & 7
                add   a,a
                add   a,a
                add   a,a                       ; group<<3
                or    #C4                      ; value = %11 ggg 100 (mode 4)
                ld    l,a
                ld    c,0                       ; port lo = 00
                out   (c),l                    ; OUT (&7Fhi00), value
                ret
