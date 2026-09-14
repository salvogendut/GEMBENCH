; Private Nextor/MSX-DOS 2 stream leaves for package_stream.asm (#84).
; Installed only by the opt-in package profile. The caller owns the scheduler
; lock, fixed stack, and resolved absolute ASCIIZ path for open (DE). One
; successful open identifies the complete package; read/close never reopen it.
; Naming/boot-drive fallback belongs to the outer launch, not these leaves.
; MSX_PKG_STATE: three fixed zero-initialized bytes, disjoint from PKG_BUFFER.
; Reads/close use private state, not a legacy FS context or directory iterator.
; The opt-in launch router may adopt the legacy resolver's open descriptor;
; after adoption it is closed here, never by both loaders.
; A=0 success; nonzero DOS error, #FF invalid state/arguments. Read returns
; BC=actual, including short/EOF; the common transaction enforces exact reads.
; A failed close poisons this private stream until explicit recovery/restart:
; never overwrite the uncertain hardware handle with another open.
MSX_PKG_ACTIVE equ MSX_PKG_STATE
MSX_PKG_HANDLE equ MSX_PKG_STATE+1
MSX_PKG_POISON equ MSX_PKG_STATE+2
                assert ((MSX_PKG_STATE>=#100)&(MSX_PKG_STATE+3<=#4000))|((MSX_PKG_STATE>=#8000)&(MSX_PKG_STATE+3<=#10000)),"MSX package stream state must remain fixed"
                assert (MSX_PKG_STATE+3<=PKG_BUFFER)|(PKG_BUFFER+512<=MSX_PKG_STATE),"MSX stream state/transfer overlap"
                assert (MSX_PKG_STATE+3<=PKG_STATE)|(PKG_STATE+22<=MSX_PKG_STATE),"MSX stream/package state overlap"
msx_pkg_open
                call msx_pkg_context
                ret nz
                ld a,(MSX_PKG_POISON)
                or a
                jr nz,msx_pkg_bad
                ld a,(MSX_PKG_ACTIVE)
                or a
                jr nz,msx_pkg_bad
                ld c,_DOPEN
                call msx_pkg_bdos
                or a
                ret nz
                ld a,b
                ld (MSX_PKG_HANDLE),a
                ld a,1
                ld (MSX_PKG_ACTIVE),a
                xor a
                ret
msx_pkg_read
                call msx_pkg_require_open
                ret nz
                push de
                ld de,PKG_BUFFER
                or a
                sbc hl,de
                pop de
                jr nz,msx_pkg_bad
                ld hl,512
                or a
                sbc hl,bc
                jr c,msx_pkg_bad
                ld a,b
                or c
                jr z,msx_pkg_bad
                ld h,b
                ld l,c
                ld de,PKG_BUFFER
                ld a,(MSX_PKG_HANDLE)
                ld b,a
                ld c,_READ
                call msx_pkg_bdos
                ld b,h
                ld c,l
                cp #C7                        ; DOS _EOF, not a transport error
                ret nz
                ld a,b
                or c
                ld a,#C7
                ret nz                        ; do not hide an inconsistent result
                xor a                         ; common stream EOF = success, zero bytes
                ret
msx_pkg_close
                call msx_pkg_require_open
                ret nz
                ld a,(MSX_PKG_HANDLE)
                ld b,a
                ld c,_DCLOSE
                call msx_pkg_bdos
                ld (MSX_PKG_POISON),a          ; nonzero means descriptor uncertain
                ld b,a
                xor a
                ld (MSX_PKG_ACTIVE),a
                ld a,b
                ret
msx_pkg_require_open
                call msx_pkg_context
                ret nz
                ld a,(MSX_PKG_ACTIVE)
                cp 1
                ret z
msx_pkg_bad     ld a,#FF
                or a
                ret
msx_pkg_context
                ld a,(PKG_CURRENT)
                or a
                jr nz,msx_pkg_bad
                ld a,(PKG_LOCK)
                or a
                jr z,msx_pkg_bad
                xor a
                ret

; DOS needs IRQs even if the caller entered with DI. Keep root serialization
; and restore the entry IFF afterwards. Map restoration must precede any
; caller instruction touching APP_BASE; DOS may leave its TPA page selected.
; Mode A=1 is read-only for OPEN and unused by READ/CLOSE. BC/HL are DOS
; results; bank_set may clobber BC. Preserve both index registers explicitly.
msx_pkg_bdos
                push ix
                push iy
                ld a,i
                push af
                ei
                ld a,1
                call BDOS
msx_pkg_bdos_return
                di
                push af
                push bc
                push hl
                ld a,(PKG_MAPPED)
                call PKG_MAP
                pop hl
                pop bc
                pop af
                ld d,a
                pop af
                ld a,d
                pop iy
                pop ix
                ret po
                ei
                ret
msx_pkg_end
                assert ((msx_pkg_open>=#100)&(msx_pkg_end<=#4000))|((msx_pkg_open>=#8000)&(msx_pkg_end<=#10000)),"MSX stream provider must execute in fixed memory"
