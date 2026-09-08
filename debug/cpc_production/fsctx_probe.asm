; Inputs/captures only; every context mutation is performed by shared policy.
fp_vector equ #3300
fp_case equ #3302
fp_done equ #3303
fp_result equ #3304
fp_bank equ #3305
fp_iff equ #3306
fp_saved equ #3308
fp_saved_end equ #3338              ; 24 context handles, not owned resources
fp_payload equ #3338
fp_commands equ #333A
fp_traces equ #3340                 ; four allocator-issued resource pages
fp_trace_count equ #3344
cpc_fsctx_probe
                di
                ld a,1
                ld (SCHED_LOCK),a
                call cpc_fs_load_module
                ld a,#71
                jp nc,cpc_probe_fail
                ld hl,(command_count)
                ld (fp_commands),hl
                ; Observation storage is owned, not borrowed from free banks.
fp_alloc_trace
                ld de,(draw_root_owner)
                ld b,GB_PAGE_RESOURCE
                call page_alloc_owned
                ld e,a
                ld a,#72
                jp nc,cpc_probe_fail
                ld a,(fp_trace_count)
                ld l,a
                ld h,0
                ld bc,fp_traces
                add hl,bc
                ld (hl),e
                ld a,e
                call foundation_bank_set
                ld hl,#4000
                ld de,#4001
                ld bc,#3FFF
                ld (hl),#D7
                ldir
                ld hl,fp_trace_count
                inc (hl)
                ld a,(hl)
                cp FP_TRACE_PAGES
                jr c,fp_alloc_trace
                ld a,#C0
                call foundation_bank_set
                call cpc_fs_cases
                di
                ld hl,(command_count)
                ld de,(fp_commands)
                or a
                sbc hl,de
                ld (fp_commands),hl
                xor a
                ld (fp_trace_count),a
fp_free_trace
                ld a,(fp_trace_count)
                ld l,a
                ld h,0
                ld bc,fp_traces
                add hl,bc
                ld a,(hl)
                call wm_free_page
                ld hl,fp_trace_count
                inc (hl)
                ld a,(hl)
                cp FP_TRACE_PAGES
                jr c,fp_free_trace
                ld a,#C0
                call foundation_bank_set
                call clip_set_full
                call sched_compositor_prepare
                ret
cpc_fs_cases
                ld hl,fp_vectors
                ld (fp_vector),hl
fp_next
                ld hl,CPC_FS_REQUEST
                ld de,CPC_FS_REQUEST+1
                ld bc,31
                ld (hl),0
                ldir
                ld hl,#DEAD                  ; never trust a marshalled owner
                ld (CPC_FS_REQUEST+4),hl
                ld hl,CPC_FS_XFER
                ld de,CPC_FS_XFER+1
                ld bc,511
                ld (hl),#A5
                ldir
                ld ix,(fp_vector)
                ld a,(ix+1)
                call foundation_bank_set
                ld l,(ix+2)                  ; saved context handle index
                ld h,0
                add hl,hl
                ld de,fp_saved
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (CPC_FS_REQUEST+2),de
                ld a,(ix+3)
                ld (CPC_FS_REQUEST+6),a
                ld a,(ix+14)
                ld (CPC_FS_REQUEST+7),a
                ld l,(ix+4)
                ld h,(ix+5)
                ld (CPC_FS_REQUEST+8),hl
                ld l,(ix+6)
                ld h,(ix+7)
                ld c,(ix+8)
                ld b,0
                ld a,c
                or a
                jr z,fp_no_payload
                ld de,CPC_FS_XFER
                ldir
fp_no_payload
                ld a,(ix+9)                  ; preserve real caller IFF on gate return
                or a
                jr z,fp_no_ei
                ei
fp_no_ei
                ld a,(ix+0)
                cp #FF
                jr nz,fp_call
                ; Resident owner teardown without loading/calling the module.
                ld de,(draw_worker_owner)
                ld (CORE_ALLOC_OWNER),de
                call fsctx_owner_cleanup
                xor a
                jr fp_called
fp_call
                call cpc_fsctx_call
fp_called
                ld (fp_result),a
                ld a,i
                ld a,0
                jp po,fp_save_iff
                inc a
fp_save_iff
                ld (fp_iff),a
                di
                ld a,(BANK_CUR)
                ld (fp_bank),a
                ld ix,(fp_vector)
                ld a,(ix+10)                 ; optional returned-handle destination
                cp #FF
                jr z,fp_capture
                ld l,a
                ld h,0
                add hl,hl
                ld de,fp_saved
                add hl,de
                ld de,(CPC_FS_REQUEST+2)
                ld (hl),e
                inc hl
                ld (hl),d
fp_capture
                ld a,(ix+11)
                ld l,a
                ld h,0
                ld de,fp_traces
                add hl,de
                ld a,(hl)
                call foundation_bank_set
                ld e,(ix+12)
                ld d,(ix+13)
                ld hl,CPC_FS_REQUEST
                ld bc,32
                ldir
                ld hl,CORE_FSCTX_TABLE
                ld bc,576
                ldir
                ld hl,CPC_FS_PENDING
                ld bc,64
                ldir
                ld hl,CPC_FS_XFER
                ld bc,512
                ldir
                ld hl,fp_result
                ld bc,3
                ldir
                ld a,(SCHED_LOCK)
                ld (de),a
                inc de
                ld a,(SCHED_CURRENT)
                ld (de),a
                inc de
                ld a,(io_offline)
                ld (de),a
                inc de
                ld a,(io_fd)
                ld (de),a
                inc de
                ld a,(CORE_PAGE_FREE)
                ld (de),a
                ld hl,(fp_vector)
                ld de,FP_VECTOR_SIZE
                add hl,de
                ld (fp_vector),hl
                ld hl,fp_case
                inc (hl)
                ld a,(hl)
                cp FP_CASES
                jp c,fp_next
                ld (fp_done),a
                ret
                include "fsctx_vectors.inc"
