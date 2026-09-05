; Shared window/application lifetime provider contract (#69).
; Include after owner_page_contract.inc. All previous CORE_* obligations apply.
;
; Calls are serialized root/kernel work with fixed code/stack; workers may not
; mutate these tables. No new interrupt policy, mapping convention or state is
; introduced. CORE_MAPPED_NATIVE is the provider's current application-page
; shadow. Pending loader identity, then mapped page, then focused window remain
; the existing owner_current resolution order (focus is only legacy fallback).
;
; Internal attach/detach/generation helpers require an in-range slot, consistent
; links/counts, and (attach) a freshly allocated, not already-attached slot.
; These are NOT untrusted public inputs. window_validate_owned checks public
; slot/generation, alive status and owner. The provider supplies unique live
; native page tags and the existing GB_APP_* constants from the ABI contract.
;
; Hooks/macros preserve the existing register behavior:
; LIFETIME_CURRENT_OWNER -> DE=owner, existing owner_current clobbers.
; LIFETIME_REGISTER_SLOT -> A=new registering slot, other registers preserved.
; LIFETIME_TEST_WINDOW_ALIVE: C=slot -> Z=dead, preserve C; clobber A/DE/HL.
; LIFETIME_PREPARE_CLOSE: A=slot -> establish exact damage and HL=flags cell;
;   preserve C; record its native code page in CORE_ALLOC_NATIVE.
; LIFETIME_DROP_WORKER: HL=flags -> remove that window's runnable contribution
;   when applicable; preserve HL (the core clears its alive/other flags next).
; LIFETIME_REMOVE_Z: C=dead slot -> remove it from z-order/live count.
; LIFETIME_FOCUS_TOP -> A=new focus; same existing wm_focus_top side effects.
; LIFETIME_MAP_FOCUS -> install focus handler/menu and native page; it must not
;   schedule/run an application callback while close scratch is live.
; LIFETIME_SET_BANK: A=native page -> map it, preserve A.
; LIFETIME_REPAINT: tail callback after owner cleanup; preserve return mapping
;   and close-owner scratch as the existing compositor does.
; LIFETIME_CLOSE_WINDOW: C=validated slot -> shared close orchestration; retains
;   CORE_CLOSE_OWNER for the explicit-quit loop, even when owner dies on last
;   window. Restore caller bank before resource release and repaint.
; LIFETIME_DRAG_CURRENT: current owned focus -> publish/move geometry without
;   repaint, with existing volatile registers. Rendering/focus policies stay
;   in providers; these macros permit different window-table/driver layouts.
;
; Scratch persistence: CORE_ALLOC_OWNER/APP_SLOT/WINDOW_SLOT/APP_REMAIN are
; clobbered by attachment/detachment. CORE_CLOSE_OWNER and CORE_CALLER_BANK
; must survive close hooks. owner_release invalidates pages/messages/contexts
; through the previously extracted owner/page contract; no new I/O is added.
;
; These bounds do not prove a complete target map. The provider must keep all
; tables/scratch/code outside framebuffer, ROM overlays and other allocations.
                assert (CORE_WIN_GEN & #FF)+CORE_WINDOW_MAX<=#100,"CORE_WIN_GEN crosses a 256-byte index page"
                assert ((CORE_WIN_GEN>=0)&(CORE_WIN_GEN+CORE_WINDOW_MAX<=#4000))|((CORE_WIN_GEN>=#8000)&(CORE_WIN_GEN+CORE_WINDOW_MAX<=#10000)),"CORE_WIN_GEN must remain in fixed address space"
                assert ((CORE_APP_SLOT>=0)&(CORE_APP_SLOT+1<=#4000))|((CORE_APP_SLOT>=#8000)&(CORE_APP_SLOT+1<=#10000)),"CORE_APP_SLOT must remain in fixed address space"
                assert ((CORE_APP_REMAIN>=0)&(CORE_APP_REMAIN+1<=#4000))|((CORE_APP_REMAIN>=#8000)&(CORE_APP_REMAIN+1<=#10000)),"CORE_APP_REMAIN must remain in fixed address space"
                assert ((CORE_WINDOW_SLOT>=0)&(CORE_WINDOW_SLOT+1<=#4000))|((CORE_WINDOW_SLOT>=#8000)&(CORE_WINDOW_SLOT+1<=#10000)),"CORE_WINDOW_SLOT must remain in fixed address space"
                assert ((CORE_WINDOW_HANDLE>=0)&(CORE_WINDOW_HANDLE+2<=#4000))|((CORE_WINDOW_HANDLE>=#8000)&(CORE_WINDOW_HANDLE+2<=#10000)),"CORE_WINDOW_HANDLE must remain in fixed address space"
                assert ((CORE_CLOSE_OWNER>=0)&(CORE_CLOSE_OWNER+2<=#4000))|((CORE_CLOSE_OWNER>=#8000)&(CORE_CLOSE_OWNER+2<=#10000)),"CORE_CLOSE_OWNER must remain in fixed address space"
                assert ((CORE_CALLER_BANK>=0)&(CORE_CALLER_BANK+1<=#4000))|((CORE_CALLER_BANK>=#8000)&(CORE_CALLER_BANK+1<=#10000)),"CORE_CALLER_BANK must remain in fixed address space"
                assert ((CORE_MAPPED_NATIVE>=0)&(CORE_MAPPED_NATIVE+1<=#4000))|((CORE_MAPPED_NATIVE>=#8000)&(CORE_MAPPED_NATIVE+1<=#10000)),"CORE_MAPPED_NATIVE must remain in fixed address space"
                assert ((CORE_FOCUS_SLOT>=0)&(CORE_FOCUS_SLOT+1<=#4000))|((CORE_FOCUS_SLOT>=#8000)&(CORE_FOCUS_SLOT+1<=#10000)),"CORE_FOCUS_SLOT must remain in fixed address space"
                assert ((CORE_PREVIOUS_FOCUS>=0)&(CORE_PREVIOUS_FOCUS+1<=#4000))|((CORE_PREVIOUS_FOCUS>=#8000)&(CORE_PREVIOUS_FOCUS+1<=#10000)),"CORE_PREVIOUS_FOCUS must remain in fixed address space"
                assert ((CORE_LIVE_WINDOWS>=0)&(CORE_LIVE_WINDOWS+1<=#4000))|((CORE_LIVE_WINDOWS>=#8000)&(CORE_LIVE_WINDOWS+1<=#10000)),"CORE_LIVE_WINDOWS must remain in fixed address space"
