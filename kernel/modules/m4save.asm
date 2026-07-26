; ---------------------------------------------------------------------------
; kernel/modules/m4save.asm - M4 board write path as a paged kernel module.
;
; The resident M4 backend keeps listing/loading in the kernel and stages save
; requests into low RAM before loading this module at DATA_MODTOP (#6000). Keeping
; C_OPEN/C_WRITE/C_CLOSE and C_ERASEFILE here preserves GEOBENCH.CFG persistence
; and Trash delete on M4 without spending those paths in resident kernel space.
;
; Transfer area, filled by lib/fs_m4.asm:
;   M4SV_LEN  (#1700, word)   bytes to write, #FFFF delete, #FFFE free,
;                              or #FFFC read chunk
;   M4SV_NAME (#1702, 11)     8.3 target name
;   M4SV_RES  (#170D, byte)   result: 1 = saved, 0 = failed
;   M4SV_PATH (#1710, 64)     current M4 path prefix ("" = root)
;   M4SV_DATA (#2200, <=7KB)  staged source bytes
; ---------------------------------------------------------------------------

M4SAVE_ORG     equ   #6000
M4SV_LEN       equ   #1700
M4SV_NAME      equ   #1702
M4SV_RES       equ   #170D
M4SV_PATH      equ   #1710
M4SV_DATA      equ   #2200

M4_DATA        equ   #FE00
M4_ACK         equ   #FC00
M4_RESP        equ   #E800
M4_ROMNUM      equ   6

M4C_OPEN       equ   #01          ; C_OPEN  (#4301)
M4C_WRITE      equ   #03          ; C_WRITE (#4303)
M4C_CLOSE      equ   #04          ; C_CLOSE (#4304)
M4C_SEEK       equ   #05          ; C_SEEK  (#4305)
M4C_READ2      equ   #12          ; C_READ2 (#4312)
M4C_FREE       equ   #09          ; C_FREE  (#4309)
M4C_ERASEFILE  equ   #0E          ; C_ERASEFILE (#430E)
M4C_FSIZE      equ   #11          ; C_FSIZE (#4311)
M4_READMODE    equ   #81          ; FA_READ | FA_REALMODE
M4_WRITEMODE   equ   #8A          ; FA_WRITE | FA_CREATE_ALWAYS | FA_REALMODE
M4_APPENDMODE  equ   #92          ; FA_WRITE | FA_OPEN_ALWAYS | FA_REALMODE
; M4ROM's own fwrite path uses #FC-byte C_WRITE payloads. Matching it cuts the
; number of command/ACK round trips for large APP saves without changing the
; resident M4 stub or the on-wire protocol.
M4_WRITECHUNK  equ   #FC
M4_READCHUNK   equ   #0800
M4SV_MAX       equ   #1C00
FS_LOAD_OFS    equ   #144C        ; 24-bit chunked-copy read offset
FS_XFLAGS      equ   #144F        ; bit1 = append-write, bit2 = chunk-save marker
fs_load_max    equ   #14F9

                org   M4SAVE_ORG

; entry: save M4SV_LEN bytes from M4SV_DATA to M4SV_PATH/M4SV_NAME, delete
; M4SV_PATH/M4SV_NAME when M4SV_LEN == #FFFF, return free KiB when #FFFE,
; or read a chunk at FS_LOAD_OFS when M4SV_LEN == #FFFC.
                xor   a
                ld    (M4SV_RES),a
                ld    hl,(M4SV_LEN)
                ld    a,h
                cp    #FF
                jr    nz,m4_save
                ld    a,l
                cp    #FF
                jr    z,m4_delete
                cp    #FE
                jr    z,m4_free
                cp    #FC
                jp    z,m4_read
                ret
m4_save
                call  m4_open_write
                ret   nc
                ld    hl,M4SV_DATA
                ld    (m4_src),hl
                ld    hl,(M4SV_LEN)
                ld    (m4_left),hl
m4s_loop        ld    hl,(m4_left)
                ld    a,h
                or    l
                jr    z,m4s_done
                ld    a,h
                or    a
                jr    nz,m4s_full
                ld    a,l
                cp    M4_WRITECHUNK
                jr    c,m4s_have
m4s_full        ld    a,M4_WRITECHUNK
m4s_have        call  m4_write_chunk
                jr    nc,m4s_fail
                jr    m4s_loop
m4s_done        call  m4_close_fd
                ld    a,1
                ld    (M4SV_RES),a
                ret
m4s_fail        call  m4_close_fd
                ret

; --- delete operation -------------------------------------------------------
m4_delete
                ld    a,M4C_ERASEFILE
                call  m4_cmd
                ld    de,M4SV_PATH
                ld    a,(de)
                or    a
                jr    z,m4d_slash
                call  m4_pstr
m4d_slash       ld    a,'/'
                call  m4_pb
                call  m4_p83
                xor   a
                call  m4_pb
                call  m4_send
                ld    a,(M4_RESP)
                cp    2
                jr    z,m4d_ok
                ld    a,(M4_RESP+3)
                or    a
                jr    nz,m4d_fail
m4d_ok          call  m4_io_end
                ld    a,1
                ld    (M4SV_RES),a
                ret
m4d_fail        call  m4_io_end
                ret

; --- free-space operation ---------------------------------------------------
; C_FREE returns ASCII in the response area ("NNNK free"). Parse the decimal KiB
; value into HL, saturating at #FFFF to avoid wrapping on larger host/card volumes.
m4_free
                ld    a,M4C_FREE
                call  m4_cmd
                call  m4_send
                ld    a,(M4_RESP)
                cp    3
                jr    c,m4f_fail
                sub   2                       ; response data bytes at M4_RESP+3
                ld    b,a
                ld    c,0                     ; C = have seen at least one digit
                ld    de,M4_RESP+3
                ld    hl,0
m4f_loop
                ld    a,(de)
                inc   de
                cp    '0'
                jr    c,m4f_nondigit
                cp    '9'+1
                jr    nc,m4f_nondigit
                sub   '0'
                push  bc
                ld    c,a                     ; C = digit
                ld    a,h                     ; reject HL*10+digit > #FFFF
                cp    #19
                jr    c,m4f_accum
                jr    nz,m4f_sat
                ld    a,l
                cp    #99
                jr    c,m4f_accum
                jr    nz,m4f_sat
                ld    a,c
                cp    6
                jr    nc,m4f_sat
m4f_accum
                push  de
                ld    d,h
                ld    e,l
                add   hl,hl                   ; *2
                add   hl,hl                   ; *4
                add   hl,de                   ; *5
                add   hl,hl                   ; *10
                ld    e,c
                ld    d,0
                add   hl,de                   ; + digit
                pop   de
                pop   bc
                ld    c,1
                djnz  m4f_loop
                jr    m4f_done
m4f_nondigit
                ld    a,c
                or    a
                jr    nz,m4f_ok               ; first nondigit after the number
                djnz  m4f_loop                ; skip leading CR/LF
m4f_done
                ld    a,c
                or    a
                jr    z,m4f_fail
m4f_ok
                call  m4_io_end
                ld    (M4SV_LEN),hl
                ld    a,1
                ld    (M4SV_RES),a
                ret
m4f_sat
                pop   bc
                ld    hl,#FFFF
                jr    m4f_ok
m4f_fail
                call  m4_io_end
                ret

; --- read operation ---------------------------------------------------------
m4_read
                call  m4_open_read
                ret   nc
                call  m4_seek_load_ofs
                jr    nc,m4r_fail_close
                ld    hl,M4SV_DATA
                ld    (m4_src),hl
                ld    hl,(fs_load_max)
                ld    (m4_left),hl
                ld    hl,0
                ld    (M4SV_LEN),hl
m4r_loop        ld    hl,(m4_left)
                ld    a,h
                or    l
                jr    z,m4r_done
                ld    de,M4_READCHUNK
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                jr    c,m4r_have
                ld    hl,M4_READCHUNK
m4r_have        push  hl
                call  m4_read_count
                pop   de
                jr    nc,m4r_fail_close
                ld    a,h
                or    l
                jr    z,m4r_done
                or    a
                sbc   hl,de
                jr    c,m4r_done
                jr    m4r_loop
m4r_done        call  m4_close_fd
                ld    a,1
                ld    (M4SV_RES),a
                ret
m4r_fail_close  call  m4_close_fd
                ret

; --- command transport ------------------------------------------------------
m4_io_end
                ld    bc,#DF00
                ld    a,7
                out   (c),a
                ei
                ret

m4_cmd
                ld    (m4_cmdbuf+1),a
                ld    a,#43
                ld    (m4_cmdbuf+2),a
                ld    hl,m4_cmdbuf+3
                ret

m4_pb           ld    (hl),a
                inc   hl
                ret

; Append the NUL-terminated string at DE to m4_cmdbuf, excluding the NUL.
m4_pstr
                ld    a,(de)
                or    a
                ret   z
                call  m4_pb
                inc   de
                jr    m4_pstr

; Append M4SV_NAME as a trimmed 8.3 path component.
m4_p83
                ld    de,M4SV_NAME
                ld    b,8
m4p83_nm        ld    a,(de)
                cp    ' '
                jr    z,m4p83_ext
                call  m4_pb
                inc   de
                djnz  m4p83_nm
m4p83_ext       ld    de,M4SV_NAME+8
                ld    a,(de)
                cp    ' '
                ret   z
                ld    a,'.'
                call  m4_pb
                ld    b,3
m4p83_e1        ld    a,(de)
                cp    ' '
                ret   z
                call  m4_pb
                inc   de
                djnz  m4p83_e1
                ret

; HL = end of m4_cmdbuf payload. Send [size][cmd_lo][#43][params...], then ACK.
m4_send
                ld    de,m4_cmdbuf+1
                or    a
                sbc   hl,de
                ld    a,l
                ld    (m4_cmdbuf),a
                di
                ld    bc,#7F85
                out   (c),c
                ld    bc,#DF00
                ld    a,M4_ROMNUM
                out   (c),a
                ld    a,(m4_cmdbuf)
                inc   a
                ld    hl,m4_cmdbuf
                ld    bc,M4_DATA
m4snd_loop      inc   b
                outi
                dec   a
                jr    nz,m4snd_loop
                ld    bc,M4_ACK
                out   (c),c
                ret

; --- save operations --------------------------------------------------------
m4_open_read
                ld    a,M4C_OPEN
                call  m4_cmd
                ld    a,M4_READMODE
                call  m4_pb
                ld    de,M4SV_PATH
                ld    a,(de)
                or    a
                jr    z,m4or_slash
                call  m4_pstr
m4or_slash      ld    a,'/'
                call  m4_pb
                call  m4_p83
                xor   a
                call  m4_pb
                call  m4_send
                ld    a,(M4_RESP+4)
                or    a
                jr    nz,m4or_fail
                ld    a,(M4_RESP+3)
                ld    (m4_fd),a
                call  m4_io_end
                scf
                ret
m4or_fail       call  m4_io_end
                or    a
                ret

m4_open_write
                ld    a,M4C_OPEN
                call  m4_cmd
                ld    a,(FS_XFLAGS)
                and   2
                ld    a,M4_WRITEMODE
                jr    z,m4ow_mode
                ld    a,M4_APPENDMODE
m4ow_mode
                call  m4_pb
                ld    de,M4SV_PATH
                ld    a,(de)
                or    a
                jr    z,m4ow_slash
                call  m4_pstr
m4ow_slash      ld    a,'/'
                call  m4_pb
                call  m4_p83
                xor   a
                call  m4_pb
                call  m4_send
                ld    a,(M4_RESP+4)
                or    a
                jr    nz,m4ow_fail
                ld    a,(M4_RESP+3)
                ld    (m4_fd),a
                call  m4_io_end
                ld    a,(FS_XFLAGS)
                and   2
                jr    z,m4ow_ok
                call  m4_seek_eof
                jr    c,m4ow_ok
                call  m4_close_fd
                or    a
                ret
m4ow_ok
                scf
                ret
m4ow_fail       call  m4_io_end
                or    a
                ret

m4_seek_eof
                ld    a,M4C_FSIZE
                call  m4_cmd
                ld    a,(m4_fd)
                call  m4_pb
                call  m4_send
                ld    a,M4C_SEEK
                call  m4_cmd
                ld    a,(m4_fd)
                call  m4_pb
                ld    de,M4_RESP+3
                ld    b,4
m4se_ofs        ld    a,(de)
                call  m4_pb
                inc   de
                djnz  m4se_ofs
                call  m4_send
                ld    a,(M4_RESP+3)
                push  af
                call  m4_io_end
                pop   af
                or    a
                ret   nz
                scf
                ret

m4_seek_load_ofs
                ld    a,M4C_SEEK
                call  m4_cmd
                ld    a,(m4_fd)
                call  m4_pb
                ld    a,(FS_LOAD_OFS)
                call  m4_pb
                ld    a,(FS_LOAD_OFS+1)
                call  m4_pb
                ld    a,(FS_LOAD_OFS+2)
                call  m4_pb
                xor   a
                call  m4_pb
                call  m4_send
                ld    a,(M4_RESP+3)
                push  af
                call  m4_io_end
                pop   af
                or    a
                ret   nz
                scf
                ret

m4_write_chunk
                ld    (m4_chunk),a
                ld    a,M4C_WRITE
                call  m4_cmd
                ld    a,(m4_fd)
                call  m4_pb
                ld    de,(m4_src)
                ld    a,(m4_chunk)
                ld    b,a
m4wc_copy       ld    a,(de)
                call  m4_pb
                inc   de
                djnz  m4wc_copy
                ld    (m4_src),de
                call  m4_send
                ld    a,(M4_RESP+3)
                or    a
                jr    nz,m4wc_fail
                call  m4_io_end
                ld    hl,(m4_left)
                ld    a,(m4_chunk)
                ld    e,a
                ld    d,0
                or    a
                sbc   hl,de
                ld    (m4_left),hl
                scf
                ret
m4wc_fail       call  m4_io_end
                or    a
                ret

m4_read_count
                ld    e,l
                ld    d,h
                ld    a,M4C_READ2
                call  m4_cmd
                ld    a,(m4_fd)
                call  m4_pb
                ld    a,e
                call  m4_pb
                ld    a,d
                call  m4_pb
                call  m4_send
                ld    hl,(M4_RESP+4)
                push  hl
                ld    a,h
                or    l
                jr    z,m4rc_done
                ld    bc,(M4_RESP+4)
                ld    hl,M4_RESP+8
                ld    de,(m4_src)
                ldir
                ld    (m4_src),de
                ld    hl,(M4SV_LEN)
                ld    de,(M4_RESP+4)
                add   hl,de
                ld    (M4SV_LEN),hl
                ld    hl,(m4_left)
                or    a
                sbc   hl,de
                ld    (m4_left),hl
m4rc_done      call  m4_io_end
                pop   hl
                scf
                ret

m4_close_fd
                ld    a,M4C_CLOSE
                call  m4_cmd
                ld    a,(m4_fd)
                call  m4_pb
                call  m4_send
                jp    m4_io_end

m4_fd           defb  0
m4_chunk        defb  0
m4_left         defw  0
m4_src          defw  0
m4_cmdbuf       defs  256

                save  "build/M4SAVE.RAW",M4SAVE_ORG,$-M4SAVE_ORG
