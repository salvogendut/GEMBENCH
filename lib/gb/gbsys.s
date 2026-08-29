;; gbsys.s - opt-in MSX2 Architecture Milestone 1 bindings (#31).
;;
;; Link with SYS=1. Keeping these calls out of the monolithic gblib.s preserves
;; the byte layout of applications that do not use the new architecture API.
        .module gbsys
        .globl  _gb_sysinfo
        .globl  _gb_owner_current
        .globl  _gb_page_alloc
        .globl  _gb_page_free
        .globl  _gb_page_check

        .area   _CODE

;; const gb_sysinfo_t *gb_sysinfo(void); -> DE = page-3 v1 capability record.
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
