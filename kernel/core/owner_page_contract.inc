; Shared owner/page state contract (#64). Emits assertions only, no bytes.
;
; Providers define each CORE_* fixed-RAM cell/table plus these hooks:
; OWNER_PAGE_CURRENT_OWNER: same owner_current DE result and clobbers.
; OWNER_PAGE_PURGE_MESSAGES / OWNER_PAGE_CLOSE_CONTEXTS: same cleanup calls;
;   consume DE=current owner and preserve CORE_ALLOC_OWNER across the call.
; OWNER_PAGE_PUBLISH_FREE: inline macro, A=count; preserve A/BC/DE/HL/flags.
;   It updates any public snapshot mirrors without requiring a common address.
;
; Runtime precondition: 1 <= CORE_PAGE_TOTAL <= CORE_PAGE_CAPACITY. Native
; page tags are opaque bytes populated by the platform before policy entry.
; Mapping/discovery is outside this core; its current-owner hook resolves the
; mapped code page using the platform bank shadow. No bank switch occurs here.
;
; Table indexing intentionally preserves the existing low-byte-only additions.
; Every indexed byte table must fit within one 256-byte page. All state and
; executing code/stack must remain visible outside the banked app aperture
; #4000..#7FFF. Providers own non-overlap with other resident state/video/stack.
; The two-byte scratch handles below must also remain outside that aperture.
; Entry is serialized root/kernel work, never an unguarded worker callback.
;
; The first CORE_WINDOW_MAX pool entries preserve the legacy busy mirror.
; Owner and page generations are nonzero, wrapping byte identities; they are
; short-lived handles, not persistent IDs. Allocation errors and cleanup order
; remain the existing GB_PAGE/GB_OWNER contracts.

                assert CORE_PAGE_CAPACITY>0 & CORE_PAGE_CAPACITY<=255,"owner/page capacity must fit a nonzero byte count"
                assert CORE_OWNER_CAPACITY==GB_OWNER_MAX,"owner table must match the public owner capacity"
                assert CORE_OWNER_CAPACITY>0 & CORE_OWNER_CAPACITY<=255,"owner capacity must fit a nonzero byte count"
                assert CORE_WINDOW_MAX>0 & CORE_WINDOW_MAX<=CORE_PAGE_CAPACITY,"legacy mirror must fit the page pool"
                assert ((CORE_ALLOC_HANDLE>=0) & (CORE_ALLOC_HANDLE+2<=#4000)) | ((CORE_ALLOC_HANDLE>=#8000) & (CORE_ALLOC_HANDLE+2<=#10000)),"CORE_ALLOC_HANDLE must remain in fixed address space"
                assert ((CORE_ALLOC_INDEX>=0) & (CORE_ALLOC_INDEX+1<=#4000)) | ((CORE_ALLOC_INDEX>=#8000) & (CORE_ALLOC_INDEX+1<=#10000)),"CORE_ALLOC_INDEX must remain in fixed address space"
                assert ((CORE_ALLOC_NATIVE>=0) & (CORE_ALLOC_NATIVE+1<=#4000)) | ((CORE_ALLOC_NATIVE>=#8000) & (CORE_ALLOC_NATIVE+1<=#10000)),"CORE_ALLOC_NATIVE must remain in fixed address space"
                assert ((CORE_ALLOC_OWNER>=0) & (CORE_ALLOC_OWNER+2<=#4000)) | ((CORE_ALLOC_OWNER>=#8000) & (CORE_ALLOC_OWNER+2<=#10000)),"CORE_ALLOC_OWNER must remain in fixed address space"
                assert ((CORE_ALLOC_PURPOSE>=0) & (CORE_ALLOC_PURPOSE+1<=#4000)) | ((CORE_ALLOC_PURPOSE>=#8000) & (CORE_ALLOC_PURPOSE+1<=#10000)),"CORE_ALLOC_PURPOSE must remain in fixed address space"
                assert (CORE_APP_ACCESSORY & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_ACCESSORY crosses a 256-byte index page"
                assert ((CORE_APP_ACCESSORY>=0) & (CORE_APP_ACCESSORY+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_ACCESSORY>=#8000) & (CORE_APP_ACCESSORY+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_ACCESSORY must remain in fixed address space"
                assert (CORE_APP_CODE_GEN & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_CODE_GEN crosses a 256-byte index page"
                assert ((CORE_APP_CODE_GEN>=0) & (CORE_APP_CODE_GEN+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_CODE_GEN>=#8000) & (CORE_APP_CODE_GEN+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_CODE_GEN must remain in fixed address space"
                assert (CORE_APP_CODE_NATIVE & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_CODE_NATIVE crosses a 256-byte index page"
                assert ((CORE_APP_CODE_NATIVE>=0) & (CORE_APP_CODE_NATIVE+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_CODE_NATIVE>=#8000) & (CORE_APP_CODE_NATIVE+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_CODE_NATIVE must remain in fixed address space"
                assert (CORE_APP_CODE_PAGE & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_CODE_PAGE crosses a 256-byte index page"
                assert ((CORE_APP_CODE_PAGE>=0) & (CORE_APP_CODE_PAGE+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_CODE_PAGE>=#8000) & (CORE_APP_CODE_PAGE+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_CODE_PAGE must remain in fixed address space"
                assert (CORE_APP_FLAGS & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_FLAGS crosses a 256-byte index page"
                assert ((CORE_APP_FLAGS>=0) & (CORE_APP_FLAGS+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_FLAGS>=#8000) & (CORE_APP_FLAGS+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_FLAGS must remain in fixed address space"
                assert (CORE_APP_PRIMARY_WIN & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_PRIMARY_WIN crosses a 256-byte index page"
                assert ((CORE_APP_PRIMARY_WIN>=0) & (CORE_APP_PRIMARY_WIN+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_PRIMARY_WIN>=#8000) & (CORE_APP_PRIMARY_WIN+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_PRIMARY_WIN must remain in fixed address space"
                assert (CORE_APP_SERVICE & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_SERVICE crosses a 256-byte index page"
                assert ((CORE_APP_SERVICE>=0) & (CORE_APP_SERVICE+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_SERVICE>=#8000) & (CORE_APP_SERVICE+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_SERVICE must remain in fixed address space"
                assert (CORE_APP_WINDOW_COUNT & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_WINDOW_COUNT crosses a 256-byte index page"
                assert ((CORE_APP_WINDOW_COUNT>=0) & (CORE_APP_WINDOW_COUNT+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_WINDOW_COUNT>=#8000) & (CORE_APP_WINDOW_COUNT+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_WINDOW_COUNT must remain in fixed address space"
                assert (CORE_APP_WORKER_WIN & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_WORKER_WIN crosses a 256-byte index page"
                assert ((CORE_APP_WORKER_WIN>=0) & (CORE_APP_WORKER_WIN+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_APP_WORKER_WIN>=#8000) & (CORE_APP_WORKER_WIN+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_WORKER_WIN must remain in fixed address space"
                assert (CORE_DEFER_HANDLER_HI & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_DEFER_HANDLER_HI crosses a 256-byte index page"
                assert ((CORE_DEFER_HANDLER_HI>=0) & (CORE_DEFER_HANDLER_HI+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_DEFER_HANDLER_HI>=#8000) & (CORE_DEFER_HANDLER_HI+CORE_OWNER_CAPACITY<=#10000)),"CORE_DEFER_HANDLER_HI must remain in fixed address space"
                assert (CORE_DEFER_HANDLER_LO & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_DEFER_HANDLER_LO crosses a 256-byte index page"
                assert ((CORE_DEFER_HANDLER_LO>=0) & (CORE_DEFER_HANDLER_LO+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_DEFER_HANDLER_LO>=#8000) & (CORE_DEFER_HANDLER_LO+CORE_OWNER_CAPACITY<=#10000)),"CORE_DEFER_HANDLER_LO must remain in fixed address space"
                assert (CORE_OWNER_ACTIVE & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_OWNER_ACTIVE crosses a 256-byte index page"
                assert ((CORE_OWNER_ACTIVE>=0) & (CORE_OWNER_ACTIVE+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_OWNER_ACTIVE>=#8000) & (CORE_OWNER_ACTIVE+CORE_OWNER_CAPACITY<=#10000)),"CORE_OWNER_ACTIVE must remain in fixed address space"
                assert (CORE_OWNER_GEN & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_OWNER_GEN crosses a 256-byte index page"
                assert ((CORE_OWNER_GEN>=0) & (CORE_OWNER_GEN+CORE_OWNER_CAPACITY<=#4000)) | ((CORE_OWNER_GEN>=#8000) & (CORE_OWNER_GEN+CORE_OWNER_CAPACITY<=#10000)),"CORE_OWNER_GEN must remain in fixed address space"
                assert ((CORE_PAGE_FREE>=0) & (CORE_PAGE_FREE+1<=#4000)) | ((CORE_PAGE_FREE>=#8000) & (CORE_PAGE_FREE+1<=#10000)),"CORE_PAGE_FREE must remain in fixed address space"
                assert (CORE_PAGE_GEN & #FF)+CORE_PAGE_CAPACITY<=#100,"CORE_PAGE_GEN crosses a 256-byte index page"
                assert ((CORE_PAGE_GEN>=0) & (CORE_PAGE_GEN+CORE_PAGE_CAPACITY<=#4000)) | ((CORE_PAGE_GEN>=#8000) & (CORE_PAGE_GEN+CORE_PAGE_CAPACITY<=#10000)),"CORE_PAGE_GEN must remain in fixed address space"
                assert (CORE_PAGE_NATIVE & #FF)+CORE_PAGE_CAPACITY<=#100,"CORE_PAGE_NATIVE crosses a 256-byte index page"
                assert ((CORE_PAGE_NATIVE>=0) & (CORE_PAGE_NATIVE+CORE_PAGE_CAPACITY<=#4000)) | ((CORE_PAGE_NATIVE>=#8000) & (CORE_PAGE_NATIVE+CORE_PAGE_CAPACITY<=#10000)),"CORE_PAGE_NATIVE must remain in fixed address space"
                assert (CORE_PAGE_OWNER & #FF)+CORE_PAGE_CAPACITY<=#100,"CORE_PAGE_OWNER crosses a 256-byte index page"
                assert ((CORE_PAGE_OWNER>=0) & (CORE_PAGE_OWNER+CORE_PAGE_CAPACITY<=#4000)) | ((CORE_PAGE_OWNER>=#8000) & (CORE_PAGE_OWNER+CORE_PAGE_CAPACITY<=#10000)),"CORE_PAGE_OWNER must remain in fixed address space"
                assert (CORE_PAGE_OWNER_GEN & #FF)+CORE_PAGE_CAPACITY<=#100,"CORE_PAGE_OWNER_GEN crosses a 256-byte index page"
                assert ((CORE_PAGE_OWNER_GEN>=0) & (CORE_PAGE_OWNER_GEN+CORE_PAGE_CAPACITY<=#4000)) | ((CORE_PAGE_OWNER_GEN>=#8000) & (CORE_PAGE_OWNER_GEN+CORE_PAGE_CAPACITY<=#10000)),"CORE_PAGE_OWNER_GEN must remain in fixed address space"
                assert (CORE_PAGE_PURPOSE & #FF)+CORE_PAGE_CAPACITY<=#100,"CORE_PAGE_PURPOSE crosses a 256-byte index page"
                assert ((CORE_PAGE_PURPOSE>=0) & (CORE_PAGE_PURPOSE+CORE_PAGE_CAPACITY<=#4000)) | ((CORE_PAGE_PURPOSE>=#8000) & (CORE_PAGE_PURPOSE+CORE_PAGE_CAPACITY<=#10000)),"CORE_PAGE_PURPOSE must remain in fixed address space"
                assert (CORE_PAGE_STATE & #FF)+CORE_PAGE_CAPACITY<=#100,"CORE_PAGE_STATE crosses a 256-byte index page"
                assert ((CORE_PAGE_STATE>=0) & (CORE_PAGE_STATE+CORE_PAGE_CAPACITY<=#4000)) | ((CORE_PAGE_STATE>=#8000) & (CORE_PAGE_STATE+CORE_PAGE_CAPACITY<=#10000)),"CORE_PAGE_STATE must remain in fixed address space"
                assert ((CORE_PAGE_TOTAL>=0) & (CORE_PAGE_TOTAL+1<=#4000)) | ((CORE_PAGE_TOTAL>=#8000) & (CORE_PAGE_TOTAL+1<=#10000)),"CORE_PAGE_TOTAL must remain in fixed address space"
                assert ((CORE_PENDING_OWNER>=0) & (CORE_PENDING_OWNER+2<=#4000)) | ((CORE_PENDING_OWNER>=#8000) & (CORE_PENDING_OWNER+2<=#10000)),"CORE_PENDING_OWNER must remain in fixed address space"
                assert (CORE_WIN_OWNER & #FF)+CORE_WINDOW_MAX<=#100,"CORE_WIN_OWNER crosses a 256-byte index page"
                assert ((CORE_WIN_OWNER>=0) & (CORE_WIN_OWNER+CORE_WINDOW_MAX<=#4000)) | ((CORE_WIN_OWNER>=#8000) & (CORE_WIN_OWNER+CORE_WINDOW_MAX<=#10000)),"CORE_WIN_OWNER must remain in fixed address space"
                assert (CORE_WIN_OWNER_GEN & #FF)+CORE_WINDOW_MAX<=#100,"CORE_WIN_OWNER_GEN crosses a 256-byte index page"
                assert ((CORE_WIN_OWNER_GEN>=0) & (CORE_WIN_OWNER_GEN+CORE_WINDOW_MAX<=#4000)) | ((CORE_WIN_OWNER_GEN>=#8000) & (CORE_WIN_OWNER_GEN+CORE_WINDOW_MAX<=#10000)),"CORE_WIN_OWNER_GEN must remain in fixed address space"
                assert (CORE_LEGACY_BUSY & #FF)+CORE_WINDOW_MAX<=#100,"CORE_LEGACY_BUSY crosses a 256-byte index page"
                assert ((CORE_LEGACY_BUSY>=0) & (CORE_LEGACY_BUSY+CORE_WINDOW_MAX<=#4000)) | ((CORE_LEGACY_BUSY>=#8000) & (CORE_LEGACY_BUSY+CORE_WINDOW_MAX<=#10000)),"CORE_LEGACY_BUSY must remain in fixed address space"
