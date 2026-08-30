;; gbsys.s - opt-in MSX2 architecture bindings (Milestones 1-2, #31/#32).
;; GB_SYSINFO returns the compatible v3 record after Milestone 3 (#35); the
;; separate gbdefer.s keeps deferred-message users from linking every M1/M2 call.
;;
;; Link with SYS=1. Keeping these calls out of the monolithic gblib.s preserves
;; the byte layout of applications that do not use the new architecture API.
        .module gbsys
        .globl  _gb_sysinfo
        .globl  _gb_owner_current
        .globl  _gb_page_alloc
        .globl  _gb_page_free
        .globl  _gb_page_check
        .globl  _gb_app_publish
        .globl  _gb_app_quit
        .globl  _gb_window_current
        .globl  _gb_window_close
        .globl  _gb_window_check
        .globl  _gb_window_slots_free
        .globl  _gb_app_window_count
        .globl  _gb_window_drag

        .area   _CODE

;; const gb_sysinfo_t *gb_sysinfo(void); -> DE = page-3 versioned capability record.
_gb_sysinfo:
        jp      0x80C3          ; GB_SYSINFO

;; gb_owner_t gb_owner_current(void); -> DE = generation-tagged identity.
_gb_owner_current:
        jp      0x80C6          ; GB_OWNER

;; gb_page_t gb_page_alloc(unsigned char purpose); purpose A -> DE handle/zero.
_gb_page_alloc:
        ld      b, a
        xor     a
        jp      0x80C9          ; GB_PAGE allocate

;; unsigned char gb_page_free(gb_page_t page); page HL -> status A.
_gb_page_free:
        ld      a, #1
        jp      0x80C9          ; GB_PAGE free

;; unsigned char gb_page_check(gb_page_t page); page HL -> status A.
_gb_page_check:
        ld      a, #2
        jp      0x80C9          ; GB_PAGE validate

;; unsigned char gb_app_publish(void); keep a windowless application alive.
_gb_app_publish:
        ld      a, #1
        jp      0x80CC          ; GB_APP publish

;; unsigned char gb_app_quit(void); close all windows and owned resources.
_gb_app_quit:
        ld      a, #2
        jp      0x80CC          ; GB_APP terminate

;; gb_window_t gb_window_current(void); -> DE generation-tagged focused window.
_gb_window_current:
        ld      a, #3
        jp      0x80CC

;; unsigned char gb_window_close(gb_window_t window); window HL -> status A.
_gb_window_close:
        ld      a, #4
        jp      0x80CC

;; unsigned char gb_window_check(gb_window_t window); window HL -> status A.
_gb_window_check:
        ld      a, #5
        jp      0x80CC

;; unsigned char gb_window_slots_free(void); -> free compositor slots in A.
_gb_window_slots_free:
        ld      a, #6
        jp      0x80CC

;; unsigned char gb_app_window_count(void); -> current application windows in A.
_gb_app_window_count:
        ld      a, #7
        jp      0x80CC

;; unsigned char gb_window_drag(void); drag the focused owned window in-kernel.
_gb_window_drag:
        ld      a, #8
        jp      0x80CC
