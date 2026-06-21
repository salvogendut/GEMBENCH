; m4detect.asm (#174): tiny BASIC-callable detector that decides which GEOBENCH
; kernel the unified GB.BAS loader should RUN" - GBM4 (M4 board) or GBALB (Albireo).
;
; We ask the FIRMWARE whether an M4-exclusive RSX command is installed, via
; KL_FIND_COMMAND (&BCD4): it searches every ROM's command table and sets carry if
; the name is found. The M4 firmware ROM (M4ROM, Duke) registers |HTTPGET (and the
; other M4 RSXs); UniDOS/Albireo do not. So carry-set == an M4 board is present.
;
; This is far safer than paging ROM slot 6 by hand: on an M4 machine M4ROM IS the
; active DOS, and manually selecting/deselecting its slot around the read corrupts
; the DOS state so the following RUN" silently fails (it boots fine on Albireo,
; where slot 6 is empty, which is exactly the asymmetry we hit). KL_FIND_COMMAND
; does the ROM walk internally and restores state, so it never disturbs M4ROM.
;
; Runs from RAM at #4000 (free at loader time - the kernel only loads later at #8000).
; Leaves 1 (M4 present) / 0 (not) in a fixed byte the loader PEEKs. Assembled by
; tools/stage_dist.sh; its bytes are embedded into GB.BAS as DATA.

M4RESULT        equ   #4030        ; the loader PEEKs this (1 = M4, 0 = Albireo)
KL_FIND_COMMAND equ   #BCD4        ; firmware: HL=name -> CF set if the RSX is installed

                org   #4000
                ld    hl,m4_rsx
                call  KL_FIND_COMMAND        ; CF set = |HTTPGET found = M4 ROM present
                ld    a,0
                jr    nc,store
                ld    a,1
store           ld    (M4RESULT),a
                ret
; RSX command name: ASCII, the LAST character has bit 7 set (firmware name format).
m4_rsx          defb  "HTTPGE"
                defb  'T'+#80
