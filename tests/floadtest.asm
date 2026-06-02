; floadtest - read a named file's contents off the AMSDOS floppy via the real
; lib/fs_amsdos.asm fsam_load_file, and print it. The test file TFILE.BIN is
; saved onto the same .dsk (with an AMSDOS header, which the reader must strip).

SCR_SET_MODE    equ   #BC0E
TXT_OUTPUT      equ   #BB5A

                org   #4000
start
                ld    a,1
                call  SCR_SET_MODE
                xor   a
                ld    (fsam_unit),a           ; drive A

                ld    hl,want
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,buf
                ld    (fs_load_dst),hl
                call  fsam_load_file
                jr    nc,nf

                ld    hl,(fs_ent_size)
                ld    de,buf
ploop           ld    a,h
                or    l
                jr    z,done
                ld    a,(de)
                push  hl
                push  de
                call  putc
                pop   de
                pop   hl
                inc   de
                dec   hl
                jr    ploop
nf              ld    hl,nfmsg
nfl             ld    a,(hl)
                or    a
                jr    z,done
                push  hl
                call  TXT_OUTPUT
                pop   hl
                inc   hl
                jr    nfl
done            jr    done

putc            cp    32
                jr    nc,pc1
                cp    13
                jr    z,pc1
                cp    10
                jr    z,pc1
                ld    a,'.'
pc1             jp    TXT_OUTPUT

want            db    "TFILE   BIN"
nfmsg           db    "NOT FOUND",0

; the file contents, saved onto the .dsk as TFILE.BIN below
tfdata          db    "Hello from the floppy file reader!",13,10
                db    "Second line of the AMSDOS test file.",13,10
tfend

; --- symbols the library expects from lib/fs.asm ------------------------
fs_ent_name     defs  11
fs_ent_attr     defb  0
fs_ent_size     defs  4
fs_req_name     defs  11
fs_load_dst     defw  0
buf             defs  1024

                include "../lib/fs_amsdos.asm"
prog_end
                save  "FLTEST",start,prog_end-start,DSK,"build/floadtest.dsk"
                save  "TFILE.BIN",tfdata,tfend-tfdata,DSK,"build/floadtest.dsk"
                save  "build/FLOADTEST.RAW",start,prog_end-start
