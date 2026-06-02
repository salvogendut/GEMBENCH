; libloadtest - exercise the real lib/fs_ide_fat.asm fside_load_file (loads a
; named file's contents off the FAT16/IDE volume). Confirms the library port,
; including the find-via-fside_dir_first/next path.

SCR_SET_MODE    equ   #BC0E
TXT_OUTPUT      equ   #BB5A

                org   #4000
start
                ld    a,1
                call  SCR_SET_MODE

                ld    hl,want                 ; fs_req_name = "BIG     TXT"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,buf
                ld    (fs_load_dst),hl
                call  fside_load_file
                jr    nc,nf

                ld    hl,(fs_ent_size)        ; print last 40 bytes (cluster 2)
                ld    de,40
                or    a
                sbc   hl,de
                ld    de,buf
                add   hl,de
                ex    de,hl
                ld    hl,40
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
nf              ld    hl,txtnf
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
                jr    nc,putc1
                ld    a,'.'
putc1           jp    TXT_OUTPUT

want            db    "BIG     TXT"
txtnf           db    "NOT FOUND",0

; --- symbols the library expects from lib/fs.asm ------------------------
fs_ent_name     defs  11
fs_ent_attr     defb  0
fs_ent_size     defs  4
fs_req_name     defs  11
fs_load_dst     defw  0
buf             defs  6144

                include "../lib/fs_ide_fat.asm"
prog_end
                save  "LIBLOAD",start,prog_end-start,DSK,"build/libload.dsk"
                save  "build/LIBLOAD.RAW",start,prog_end-start
