; memtest - detect total RAM on the machine by counting 64K expansion banks,
; adapted from llopis/amstrad-diagnostics (CheckUpperRAM / DetectAvailableUpperRAM).
;
; The gate-array RAM-config port (&7Fxx) value &C4..&C7 pages a 16K expansion
; block into &4000-&7FFF; bits 3-5 select the 64K bank (DK'tronics 512K scheme).
; We mark each bank's &4000, then page each in and count the ones that kept
; their mark (absent/mirrored banks read &FF or a duplicate).
;
; CRITICAL: paging swaps &4000-&7FFF, so the probe MUST run from outside that
; region. mem_detect is org'd at &8000 (RAM block 2, untouched by &C4..&C7) and
; only touches &4000-&4001 as a marker (saved/restored). Interrupts off.

SCR_SET_MODE    equ   #BC0E
TXT_OUTPUT      equ   #BB5A

                org   #4000
start
                ld    a,1
                call  SCR_SET_MODE
                di
                call  mem_detect             ; A = number of 64K expansion banks
                ei
                push  af

                ld    hl,txt_banks
                call  puts
                pop   af
                push  af
                add   a,'0'                   ; bank count (0..8)
                call  TXT_OUTPUT
                ld    a,13
                call  TXT_OUTPUT
                ld    a,10
                call  TXT_OUTPUT

                ld    hl,txt_total            ; total KB = 64 + banks*64
                call  puts
                pop   af
                ld    l,a
                ld    h,0
                add   hl,hl                    ; *2
                add   hl,hl                    ; *4
                add   hl,hl                    ; *8
                add   hl,hl                    ; *16
                add   hl,hl                    ; *32
                add   hl,hl                    ; *64
                ld    de,64
                add   hl,de                    ; + base 64K
                call  print_dec16
                ld    a,'K'
                call  TXT_OUTPUT
done            jr    done

; print null-terminated string (HL)
puts            ld    a,(hl)
                or    a
                ret   z
                push  hl
                call  TXT_OUTPUT
                pop   hl
                inc   hl
                jr    puts

; print HL as decimal, suppressing leading zeros
print_dec16     ld    de,10000
                call  pd_dig
                ld    de,1000
                call  pd_dig
                ld    de,100
                call  pd_dig
                ld    de,10
                call  pd_dig
                ld    a,l
                add   a,'0'
                jp    TXT_OUTPUT
pd_dig          ld    a,#FF                    ; digit-1
pd_loop         inc   a
                or    a
                sbc   hl,de
                jr    nc,pd_loop
                add   hl,de                    ; undo overshoot
                or    a
                jr    z,pd_done                ; leading zero -> skip (HL preserved)
                ld    (pd_seen),a
pd_emit         push  hl
                add   a,'0'
                call  TXT_OUTPUT
                pop   hl
                ret
pd_done         ld    a,(pd_seen)             ; once a nonzero digit was seen, print 0s
                or    a
                ret   z
                xor   a
                jr    pd_emit
pd_seen         db    0

txt_banks       db    "Banks: ",0
txt_total       db    "Total: ",0

; ---------------------------------------------------------------------------
; mem_detect (runs from &8000, safe while &4000-&7FFF is paged). Returns the
; count of present 64K expansion banks in A.
                org   #8000
mem_detect
                ld    hl,(#4000)             ; save main &4000-&4001
                ld    (md_save),hl

                ld    d,0                     ; clear each bank's marker to 0
md_clear
                ld    e,0
                call  md_port
                ld    bc,#7F00
                out   (c),l
                xor   a
                ld    (#4000),a
                ld    (#4001),a
                inc   d
                ld    a,d
                cp    8
                jr    nz,md_clear

                ld    bc,#7FC0               ; main marker = &FF&FF (config 0)
                out   (c),c
                ld    a,#FF
                ld    (#4000),a
                ld    (#4001),a

                xor   a
                ld    (md_count),a
                ld    a,#FF
                ld    (md_last),a
                ld    (md_last+1),a

                ld    d,0
md_detect
                ld    e,0
                call  md_port
                ld    bc,#7F00
                out   (c),l
                call  md_valid               ; NZ = present, Z = absent/mirror
                jr    z,md_next
                ld    hl,md_count
                inc   (hl)
                call  md_update
md_next
                inc   d
                ld    a,d
                cp    8
                jr    nz,md_detect

                ld    bc,#7FC0               ; back to normal config
                out   (c),c
                ld    hl,(md_save)           ; restore main &4000
                ld    (#4000),hl
                ld    a,(md_count)
                ret

md_port                                       ; D=bank E=block -> L=port value
                ld    a,d
                add   a,a
                add   a,a
                add   a,a                     ; bank*8
                or    #C4
                or    e
                ld    l,a
                ret

md_valid                                      ; read marker; NZ=present, Z=absent
                ld    a,(#4000)
                cp    #FF
                jr    z,md_invalid
                ld    e,a
                ld    a,(md_last)
                cp    e
                jr    z,md_invalid
                ld    a,(#4001)
                cp    #FF
                jr    z,md_invalid
                ld    e,a
                ld    a,(md_last+1)
                cp    e
                jr    z,md_invalid
                ld    a,1                      ; present
                or    a
                ret
md_invalid
                xor   a                        ; Z = absent
                ret

md_update                                      ; mark counted bank, remember it
                ld    a,#FF
                ld    (#4000),a
                ld    (#4001),a
                ld    (md_last),a
                ld    (md_last+1),a
                ret

md_save         dw    0
md_count        db    0
md_last         dw    0
prog_end
                save  "MEMTEST",start,prog_end-start,DSK,"build/memtest.dsk"
                save  "build/MEMTEST.RAW",start,prog_end-start
