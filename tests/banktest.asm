; banktest - Phase 1 banking spike. Proves the co-resident model on 128K+:
;   1. data in an expansion bank's #4000 window is independent of main #4000
;   2. code copied into the bank EXECUTES there
;   3. bank code can write back to resident RAM (>= #8000)
;
; Loaded high at #8000 so the program itself, its stack and its data stay
; mapped while #4000-#7FFF is swapped to a bank (configs &C4..&C7 leave
; #8000-#BFFF main). Prints "BANK TEST PASS" / "FAIL" via firmware text.
;
; Build:  rasm tests/banktest.asm -eo   (after mkdir build)
; Run:    1984 --memory=128 --disk-a=build/banktest.dsk --autostart=BANKTEST

SCR_SET_MODE    equ   #BC0E
TXT_OUTPUT      equ   #BB5A

                org   #8000
start
                ld    a,1
                call  SCR_SET_MODE           ; mode 1, clears the screen

                di
                ld    hl,#5678               ; main #4000 marker
                ld    (#4000),hl
                xor   a                        ; clear the resident marker
                ld    (marker),a

                ld    a,0                     ; page expansion bank 0, block 0
                ld    c,0
                call  bank_page

                ld    hl,#1234               ; bank #4000 marker (different value)
                ld    (#4000),hl
                ld    hl,bank_routine         ; copy the routine into the bank
                ld    de,#4010
                ld    bc,bank_routine_end-bank_routine
                ldir
                call  #4010                  ; EXECUTE it from the bank

                ld    a,(marker)             ; (2)+(3): it ran and wrote the marker
                cp    #AA
                jr    nz,bt_fail
                ld    hl,(#4000)             ; (1a): bank still holds #1234
                ld    a,h
                cp    #12
                jr    nz,bt_fail
                ld    a,l
                cp    #34
                jr    nz,bt_fail

                call  bank_normal            ; back to all-main RAM
                ld    hl,(#4000)             ; (1b): main #4000 still #5678
                ld    a,h
                cp    #56
                jr    nz,bt_fail2
                ld    a,l
                cp    #78
                jr    nz,bt_fail2

                ei
                ld    hl,msg_pass
                jr    bt_print
bt_fail
                call  bank_normal
bt_fail2
                ei
                ld    hl,msg_fail
bt_print
                call  print_str
                jr    $                        ; freeze on the result

; print_str: HL = 0-terminated string -> firmware text output.
print_str
                ld    a,(hl)
                or    a
                ret   z
                call  TXT_OUTPUT
                inc   hl
                jr    print_str

; copied into the bank and run from there; writes the resident marker.
bank_routine
                ld    a,#AA
                ld    (marker),a
                ret
bank_routine_end

msg_pass        db    "BANK TEST PASS",0
msg_fail        db    "BANK TEST FAIL",0
marker          db    0

                include "../lib/bank.asm"
prog_end
                save  "BANKTEST.BIN",start,prog_end-start,DSK,"build/banktest.dsk"
                save  "build/BANKTEST.RAW",start,prog_end-start
