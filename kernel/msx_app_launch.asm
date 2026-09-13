; MSX opt-in normal launch. Keep the legacy drive/CWD resolver, but adopt its
; open descriptor when the first bounded read identifies a two-segment v4 APP.
; No reopen/seek between segments. The entire resolver is root-serialized.
msx_app_load
                call msx_app_context_ready
                ret nc                         ; no mutation of another active transaction
                ld a,(WM_OPEN_STRICT)
                ld c,a
                xor a
                ld (WM_OPEN_STRICT),a           ; accepted attempt consumes one-shot, even if load fails
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                ld (MSX_PACKAGE_LAUNCH),a
                ld hl,APP_LOAD_MAX
                ld (fs_load_max),hl
                ld hl,APP_BASE
                ld (fs_load_dst),hl
                ld a,c
                or a
                jr z,msx_app_system
                call fs_load_cur_sys
                jr msx_app_loaded
msx_app_system  call fs_load_sys
msx_app_loaded
                jr nc,msx_app_return
                ld a,(MSX_PACKAGE_LAUNCH)
                cp 2
                jr z,msx_app_streamed
                call MSX_GBAP4_GATE
                jr msx_app_return
msx_app_streamed
                ld a,(MSX_PACKAGE_RESULT)
                or a
                jr nz,msx_app_reject
                scf
                jr msx_app_return
msx_app_reject  or a                          ; NC; stream status is not publication
msx_app_return
                ld b,0
                rl b                          ; preserve CF across lock restoration
                di
                xor a
                ld (MSX_PACKAGE_LAUNCH),a
                ld (MSX_PACKAGE_PREFIX),a
                pop af
                ld (SCHED_LOCK),a
                rr b
                ret                            ; WM caller entered with DI

; HL = actual first-read count, C = already-open DOS handle. NC = ordinary
; file; C = stream took ownership and CLOSED it (even on failure). On C the
; caller must skip its legacy close and must not fall back to another file.
msx_app_probe
                ld a,(MSX_PACKAGE_LAUNCH)
                or a
                ret z
                ld a,(fsmx_total)
                ld b,a
                ld a,(fsmx_total+1)
                or b
                ret nz                         ; never classify later ordinary payload bytes
                ld a,h
                dec a
                or l
                ret nz                         ; only a complete 256-byte prefix
                ld hl,FSMX_IOBUF
                ld a,(hl)
                cp #C3
                jr nz,msx_app_not_package
                ld hl,FSMX_IOBUF+3
                ld de,msx_app_magic
                ld b,5
msx_app_match
                ld a,(de)
                cp (hl)
                jr nz,msx_app_not_package
                inc de
                inc hl
                djnz msx_app_match
                ld a,(hl)                      ; canonical one/two-icon manifest offset
                dec a
                cp 2
                jr nc,msx_app_not_package
                inc a
                add a,a
                add a,a
                add a,a
                add a,16+34                    ; manifest segment count, bounded in prefix
                ld l,a
                ld h,FSMX_IOBUF/256
                ld a,(hl)
                cp 2
                jr nz,msx_app_not_package
                ld a,c
                ld (MSX_PACKAGE_IO_STATE+1),a
                ld a,1
                ld (MSX_PACKAGE_IO_STATE),a
                ld (MSX_PACKAGE_PREFIX),a
                ld de,(CORE_PENDING_OWNER)
                call MSX_PACKAGE_ENTRY
                ld (MSX_PACKAGE_RESULT),a
                cp 4                           ; context rejection did not own/close stream
                jr c,msx_app_stream_closed
                call MSX_PACKAGE_IO_CLOSE
msx_app_stream_closed
                ld a,(MSX_PACKAGE_RESULT)
                or a
                jr nz,msx_app_seal_done
                call msx_secondary_commit      ; only a closed, fully validated package
                jr c,msx_app_seal_done
                ld a,1
                ld (MSX_PACKAGE_RESULT),a      ; shared owner rollback also frees the secondary
msx_app_seal_done
                ld hl,0
                ld (fs_ent_size+2),hl
                ld a,(MSX_PACKAGE_RESULT)
                or a
                jr nz,msx_app_stream_size
                ld hl,(MSX_PACKAGE_STATE+8)
msx_app_stream_size
                ld (fs_ent_size),hl
                ld a,2
                ld (MSX_PACKAGE_LAUNCH),a
                scf
                ret
msx_app_not_package
                or a
                ret
msx_app_magic   db "GBAP",4

; Invoked only for an armed launch after the router is installed. Non-launch
; reads cannot call this module while boot is still loading it.
msx_app_read_size
                call msx_app_progress
                ld a,(fsmx_total)
                ld b,a
                ld a,(fsmx_total+1)
                or b
                ret nz
                ld hl,256
                ret

; Root-only progress during a serialized load. Never call k_poll: its menu
; dispatch can re-enter apps while a package is incomplete. Reuse only hardware
; input, pointer clamping and the hardware-sprite leaf; no clock/WM repaint.
; CRC accumulators live in registers, so preserve every pair used by the core.
msx_app_progress
                ld a,i
                ret po                         ; never enable IRQs for a DI caller
                ld a,(MSX_PACKAGE_LAUNCH)
                or a
                ret z
                push hl
                ld hl,msx_app_progress_tick
                ld a,(MSX_TICK)
                cp (hl)
                jr z,msx_app_progress_idle
                ld (hl),a
                push bc
                push de
                push ix
                push iy
                call input_poll
                call poll_move
                call cursor_move_to
                ld hl,(cursor_x)
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,l
                ld (poll_byte),a
                ld (POLL_MX),a
                ld hl,(cursor_y)
                srl h
                rr l
                ld a,211
                sub l
                ld (poll_line),a
                ld (POLL_MY),a
msx_app_progress_updated
                pop iy
                pop ix
                pop de
                pop bc
msx_app_progress_idle
                pop hl
                ret
msx_app_progress_tick db 0

; Zero the complete mapped secondary, including its 256-byte tail, while
; retaining pointer-only progress. No callbacks, mapping changes or publication.
msx_app_clear_secondary
                ld hl,APP_BASE
                ld b,32
msx_app_clear_chunk
                push bc
                ld d,h
                ld e,l
                inc de
                ld bc,511
                ld (hl),0
                ldir
                ex de,hl
                call msx_app_progress
                pop bc
                djnz msx_app_clear_chunk
                ret

; Invoked before public launch writes the filename or allocates an owner.
; Preserve HL (the caller's app-name pointer); reject worker/nested entry.
msx_app_can_launch
                ld a,(CORE_PENDING_OWNER)
                ld b,a
                ld a,(CORE_PENDING_OWNER+1)
                or b
                ret nz
msx_app_context_ready
                ld a,(MSX_SECONDARY_STATE)
                or a
                ret nz
                ld a,(SCHED_CURRENT)
                or a
                ret nz
                ld a,(MSX_PACKAGE_STATE)
                or a
                ret nz
                ld a,(MSX_PACKAGE_IO_STATE)
                or a
                ret nz
                ld a,(MSX_PACKAGE_IO_STATE+2)   ; uncertain close forbids another open
                or a
                ret nz
                scf
                ret
