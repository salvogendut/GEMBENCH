; Shared focus/stack provider contract (#70).
;
; State is fixed, serialized root/kernel work, not callable from workers.
; CORE_Z_ORDER[0..CORE_LIVE_WINDOWS) contains unique, alive slots. Desktop is
; slot 0 and stays at index 0; the count is 1..CORE_WINDOW_MAX once booted.
; wm_z_append requires an alive unpublished slot and spare capacity (boot may
; append desktop at count 0). wm_z_remove requires exactly one occurrence and
; a nonempty list; normal callers never remove desktop. wm_raise requires a
; live non-desktop slot. wm_focus_top requires count>=1. These are trusted
; internal helpers, NOT public validators; registration/close enforce inputs.
; Removed tail bytes are unspecified. Raise preserves other slots' order.
; Focus may be desktop while another window remains z-top. Temporary focus
; during drag/service delivery is still owned by those callers, not this unit.
;
; Preserve the existing MSX2 sibling rule: same native code-page tag consumes
; only the activation bit (CORE_INPUT_FLAGS bit 0). This does not replace it
; with owner-handle comparison. Providers must maintain unique live page tags.
; CORE_FOCUS_OLD first holds the old native tag, then the old focus slot for
; visible damage. CORE_FOCUS_TARGET survives all lookups and damage hooks.
;
; FOCUS_NATIVE_CELL: A=slot -> HL=fixed native-tag cell/window token; preserve A,
;   clobber B/DE/flags as wm_entry does, preserve C. Valid for every live slot.
; FOCUS_RECT: A=slot -> HL=fixed contiguous x,y,w,h bytes; preserve A/C,
;   clobber B/DE/flags.
;   Coordinates and CORE_POINTER_X/Y use the same native WM units (not public
;   universal pixels), unsigned byte origins/extents, nonzero extents. Hit-test
;   uses half-open bounds and rejects negative differences before subtraction.
; FOCUS_EVENT_POINTER/MENU_POINTER: HL=native cell/token -> HL=callback/menu
;   address in that window's mapped code page; clobber A/DE, preserve B/C.
; FOCUS_SET_BANK: A=native tag -> map the page; preserve A/HL. No app callback.
; FOCUS_MENU_CLEAR/INSTALL: tail hooks with existing menu semantics, INSTALL
;   takes HL=menu in mapped page. Both leave the focused page mapped.
; FOCUS_BUILD_DAMAGE: target/old slots -> exact focus sources, preserve target.
;   Called after focus assignment but BEFORE raise; it must not consume
;   visibility until the repaint hook sees the final stacking order.
; FOCUS_REPAINT: tail hook after any raise; use the prepared focus sources.
; FOCUS_SET_CLIP: A=slot -> prepare legacy top-window clip.
; FOCUS_REPAINT_TOP: tail legacy top-only repaint; hooks retain return mapping.
;
; CORE_Z_PRESERVE_SLOT selects the original append sequence (1 preserves A;
; 0 is the historical cooperative sequence, returning the prior count in A).
; CORE_FOCUS_VISIBLE_DAMAGE selects the existing compositor path. Normal
; shared desktop integration uses both=1; zero variants only preserve the
; existing MSX2 cooperative compatibility build, not a separate CPC policy.
; Window-table layout, drawing, bank hardware and menu implementation belong
; to the provider. Bounds below do not prove non-overlap with framebuffer,
; ROM overlays, scratch, stacks or other allocations; the full map must do so.
                assert (CORE_WINDOW_MAX>=1)&(CORE_WINDOW_MAX<=255),"invalid CORE_WINDOW_MAX"
                assert (CORE_Z_ORDER & #FF)+CORE_WINDOW_MAX<=#100,"CORE_Z_ORDER crosses a 256-byte index page"
                assert ((CORE_Z_ORDER>=0)&(CORE_Z_ORDER+CORE_WINDOW_MAX<=#4000))|((CORE_Z_ORDER>=#8000)&(CORE_Z_ORDER+CORE_WINDOW_MAX<=#10000)),"CORE_Z_ORDER must remain in fixed address space"
                assert ((CORE_LIVE_WINDOWS>=0)&(CORE_LIVE_WINDOWS+1<=#4000))|((CORE_LIVE_WINDOWS>=#8000)&(CORE_LIVE_WINDOWS+1<=#10000)),"CORE_LIVE_WINDOWS must remain in fixed address space"
                assert ((CORE_FOCUS_SLOT>=0)&(CORE_FOCUS_SLOT+1<=#4000))|((CORE_FOCUS_SLOT>=#8000)&(CORE_FOCUS_SLOT+1<=#10000)),"CORE_FOCUS_SLOT must remain in fixed address space"
                assert ((CORE_PREVIOUS_FOCUS>=0)&(CORE_PREVIOUS_FOCUS+1<=#4000))|((CORE_PREVIOUS_FOCUS>=#8000)&(CORE_PREVIOUS_FOCUS+1<=#10000)),"CORE_PREVIOUS_FOCUS must remain in fixed address space"
                assert ((CORE_FOCUS_HANDLER>=0)&(CORE_FOCUS_HANDLER+2<=#4000))|((CORE_FOCUS_HANDLER>=#8000)&(CORE_FOCUS_HANDLER+2<=#10000)),"CORE_FOCUS_HANDLER must remain in fixed address space"
                assert ((CORE_INPUT_FLAGS>=0)&(CORE_INPUT_FLAGS+1<=#4000))|((CORE_INPUT_FLAGS>=#8000)&(CORE_INPUT_FLAGS+1<=#10000)),"CORE_INPUT_FLAGS must remain in fixed address space"
                assert ((CORE_POINTER_X>=0)&(CORE_POINTER_X+1<=#4000))|((CORE_POINTER_X>=#8000)&(CORE_POINTER_X+1<=#10000)),"CORE_POINTER_X must remain in fixed address space"
                assert ((CORE_POINTER_Y>=0)&(CORE_POINTER_Y+1<=#4000))|((CORE_POINTER_Y>=#8000)&(CORE_POINTER_Y+1<=#10000)),"CORE_POINTER_Y must remain in fixed address space"
                assert ((CORE_FOCUS_TARGET>=0)&(CORE_FOCUS_TARGET+1<=#4000))|((CORE_FOCUS_TARGET>=#8000)&(CORE_FOCUS_TARGET+1<=#10000)),"CORE_FOCUS_TARGET must remain in fixed address space"
                assert ((CORE_FOCUS_OLD>=0)&(CORE_FOCUS_OLD+1<=#4000))|((CORE_FOCUS_OLD>=#8000)&(CORE_FOCUS_OLD+1<=#10000)),"CORE_FOCUS_OLD must remain in fixed address space"
                assert ((CORE_HIT_CURSOR>=0)&(CORE_HIT_CURSOR+1<=#4000))|((CORE_HIT_CURSOR>=#8000)&(CORE_HIT_CURSOR+1<=#10000)),"CORE_HIT_CURSOR must remain in fixed address space"
                assert (CORE_Z_PRESERVE_SLOT==0)|(CORE_Z_PRESERVE_SLOT==1),"CORE_Z_PRESERVE_SLOT must be boolean"
                assert (CORE_FOCUS_VISIBLE_DAMAGE==0)|(CORE_FOCUS_VISIBLE_DAMAGE==1),"CORE_FOCUS_VISIBLE_DAMAGE must be boolean"
