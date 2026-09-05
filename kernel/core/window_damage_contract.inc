; Shared window damage/repaint provider contract (#72).
;
; Serialized root/kernel work with fixed code, state, stack and window records.
; The caller holds the scheduler/kernel lock across prepare, dispatch, callbacks
; and cleanup. IRQ_ENTER/LEAVE preserve the original boundary sequence; they do
; NOT imply interrupts stay disabled during drawing (providers may enable IRQs)
; and do NOT save/restore the caller's IFF. Nested repaint is unsupported.
; Callbacks must honor the active clip and pointer lock, preserve this unit's
; scratch and iterator state, and not mutate geometry/lifetime/z-order mid-pass.
;
; Native geometry is a mutable contiguous x,y,w,h byte tuple, separate from the
; universal ABI's pixel coordinates. Inputs are trusted existing WM values:
; right/bottom and padded width must fit in a byte, with no wrap. No new public
; geometry validator, saturating arithmetic or pixel conversion is introduced.
; Move repairs the complete endpoint envelope (including the destructive outline
; sweep); resize keeps the origin and damages max(old,new) extents.
; wm_set_clip keeps the provider's right overdraw pad. k_wm_damage replaces the
; primary clip and, in region mode, clears pending extra damage. Other clip and
; geometry setters retain their previous pending-source semantics.
;
; Focus damage receives old/target slots, after focus assignment but before
; raising. At least one is a live non-desktop window; desktop is slot zero and
; has no focus furniture. The new app is primary, old app is optional extra;
; app->desktop uses the old app only. Preparation/iteration sees final z-order.
; CORE_Z_ORDER's live prefix is unique/alive, count<=CORE_WINDOW_MAX, desktop
; pinned at index 0. Repaint-all starts there; repaint-top starts at count-1.
; Repaint defensively skips dead slots but does not validate arbitrary tables.
;
; PAINT_PREPARE captures immutable primary/extra sources AND refreshes visibility
; (the historical MSX entry name says only "VIS_REFRESH"). REGION_BEGIN accepts
; A=slot, REGION_NEXT advances the same surface: A=1/NZ with nonempty clip,
; A=0/Z when exhausted. REGION_SLOT stays valid across each drawing callback.
; Fully covered windows receive no callback. Overlap subtraction and fragment
; enumeration are the shared visibility core, not duplicated in this unit.
;
; Hooks/macros:
; WINDOW_TOKEN: A=slot -> HL=fixed opaque record token; clobber B/DE/flags,
;   preserve A/C. WINDOW_RECT: same but HL=mutable geometry tuple.
; CLOSE_RECT: A=slot -> HL=tuple, B=native code tag; clobber DE/flags, preserve C.
;   wm_set_clip returns B plus HL=tuple+3 (height); lifetime glue adapts that
;   pointer if it needs record flags. Other routines promise no token on return.
; WINDOW_FLAGS: HL=token -> A=flags; preserve HL/B/C, clobber DE/flags.
;   ALIVE_BIT and MANAGED_BIT describe the provider's opaque flag encoding.
; WINDOW_NATIVE: HL=token -> A=native code tag; preserve HL/B/C/DE.
; RECT_ARGUMENTS: HL=token -> B=x,C=y,D=w,E=h; may clobber HL.
; REPAINT_POINTER: HL=token -> HL=callback in its mapped code page; clobber A/DE.
; SET_BANK: A=native tag, preserve HL token; update CORE_MAPPED_NATIVE.
; CHROME_DRAW: HL=token, page mapped -> managed chrome/content paint.
; CALL: HL=nonzero legacy callback, page mapped -> invoke it.
; RECT_CULL: B=x,C=y,D=w,E=h -> carry if disjoint from active clip.
; POINTER_ERASE/SHOW are called only when suppression is zero, and must honor
;   paintlock; SHOW is idempotent. The core brackets the entire paint pass.
; IRQ_ENTER/LEAVE are inline, register/flags preserving and stack neutral.
; All hooks retain the common scratch and immutable iterator state unless
; explicitly responsible for advancing it; macro stack effects must balance.
;
; CORE_REPAINT_REGIONS=1 is normal shared policy. Zero retains the MSX cooperative
; coarse-cull path; not an alternative CPC policy. ERASE_POINTER is independent:
; software save-under providers must erase before paint even with regions=1;
; a separate sprite plane can stay visible. Lock spans all fragments and is
; cleared only after restoring caller bank/full clip and the IRQ leave hook.
; Neither the caller's prior clip nor prior paintlock/IFF is restored.
;
; Local bounds/adjacency checks do not prove a complete map. Provider must
; exclude framebuffer, ROM overlays, other allocations and stacks, and bound
; macro expansion so local JR branches remain reachable.
                assert (CORE_WINDOW_MAX>=1)&(CORE_WINDOW_MAX<=255),"invalid CORE_WINDOW_MAX"
                assert (CORE_SCREEN_COLS>=1)&(CORE_SCREEN_COLS<=255),"invalid CORE_SCREEN_COLS"
                assert (CORE_SCREEN_LINES>=1)&(CORE_SCREEN_LINES<=255),"invalid CORE_SCREEN_LINES"
                assert (CORE_WINDOW_DAMAGE_PAD>=0)&(CORE_WINDOW_DAMAGE_PAD<=255),"invalid CORE_WINDOW_DAMAGE_PAD"
                assert (CORE_PAINT_ALIVE_BIT>=0)&(CORE_PAINT_ALIVE_BIT<=7),"invalid CORE_PAINT_ALIVE_BIT"
                assert (CORE_PAINT_MANAGED_BIT>=0)&(CORE_PAINT_MANAGED_BIT<=7),"invalid CORE_PAINT_MANAGED_BIT"
                assert CORE_PAINT_ALIVE_BIT!=CORE_PAINT_MANAGED_BIT,"paint flag bits must differ"
                assert (CORE_REPAINT_REGIONS==0)|(CORE_REPAINT_REGIONS==1),"CORE_REPAINT_REGIONS must be boolean"
                assert (CORE_REPAINT_ERASE_POINTER==0)|(CORE_REPAINT_ERASE_POINTER==1),"CORE_REPAINT_ERASE_POINTER must be boolean"
                assert CORE_CLIP_Y==CORE_CLIP_X+1,"clip bytes must be contiguous"
                assert CORE_CLIP_W==CORE_CLIP_X+2,"clip bytes must be contiguous"
                assert CORE_CLIP_H==CORE_CLIP_X+3,"clip bytes must be contiguous"
                assert (CORE_Z_ORDER & #FF)+CORE_WINDOW_MAX<=#100,"CORE_Z_ORDER crosses a 256-byte index page"
                assert ((CORE_Z_ORDER>=0)&(CORE_Z_ORDER+CORE_WINDOW_MAX<=#4000))|((CORE_Z_ORDER>=#8000)&(CORE_Z_ORDER+CORE_WINDOW_MAX<=#10000)),"CORE_Z_ORDER must remain in fixed address space"
                assert ((CORE_LIVE_WINDOWS>=0)&(CORE_LIVE_WINDOWS+1<=#4000))|((CORE_LIVE_WINDOWS>=#8000)&(CORE_LIVE_WINDOWS+1<=#10000)),"CORE_LIVE_WINDOWS must remain in fixed address space"
                assert ((CORE_FOCUS_SLOT>=0)&(CORE_FOCUS_SLOT+1<=#4000))|((CORE_FOCUS_SLOT>=#8000)&(CORE_FOCUS_SLOT+1<=#10000)),"CORE_FOCUS_SLOT must remain in fixed address space"
                assert ((CORE_FOCUS_TARGET>=0)&(CORE_FOCUS_TARGET+1<=#4000))|((CORE_FOCUS_TARGET>=#8000)&(CORE_FOCUS_TARGET+1<=#10000)),"CORE_FOCUS_TARGET must remain in fixed address space"
                assert ((CORE_FOCUS_OLD>=0)&(CORE_FOCUS_OLD+1<=#4000))|((CORE_FOCUS_OLD>=#8000)&(CORE_FOCUS_OLD+1<=#10000)),"CORE_FOCUS_OLD must remain in fixed address space"
                assert ((CORE_MOVE_X>=0)&(CORE_MOVE_X+1<=#4000))|((CORE_MOVE_X>=#8000)&(CORE_MOVE_X+1<=#10000)),"CORE_MOVE_X must remain in fixed address space"
                assert ((CORE_MOVE_Y>=0)&(CORE_MOVE_Y+1<=#4000))|((CORE_MOVE_Y>=#8000)&(CORE_MOVE_Y+1<=#10000)),"CORE_MOVE_Y must remain in fixed address space"
                assert ((CORE_SIZE_W>=0)&(CORE_SIZE_W+1<=#4000))|((CORE_SIZE_W>=#8000)&(CORE_SIZE_W+1<=#10000)),"CORE_SIZE_W must remain in fixed address space"
                assert ((CORE_SIZE_H>=0)&(CORE_SIZE_H+1<=#4000))|((CORE_SIZE_H>=#8000)&(CORE_SIZE_H+1<=#10000)),"CORE_SIZE_H must remain in fixed address space"
                assert ((CORE_REPAINT_INDEX>=0)&(CORE_REPAINT_INDEX+1<=#4000))|((CORE_REPAINT_INDEX>=#8000)&(CORE_REPAINT_INDEX+1<=#10000)),"CORE_REPAINT_INDEX must remain in fixed address space"
                assert ((CORE_REPAINT_BANK>=0)&(CORE_REPAINT_BANK+1<=#4000))|((CORE_REPAINT_BANK>=#8000)&(CORE_REPAINT_BANK+1<=#10000)),"CORE_REPAINT_BANK must remain in fixed address space"
                assert ((CORE_MAPPED_NATIVE>=0)&(CORE_MAPPED_NATIVE+1<=#4000))|((CORE_MAPPED_NATIVE>=#8000)&(CORE_MAPPED_NATIVE+1<=#10000)),"CORE_MAPPED_NATIVE must remain in fixed address space"
                assert ((CORE_CLIP_X>=0)&(CORE_CLIP_X+4<=#4000))|((CORE_CLIP_X>=#8000)&(CORE_CLIP_X+4<=#10000)),"CORE_CLIP_X must remain in fixed address space"
                assert ((CORE_DAMAGE_EXTRA>=0)&(CORE_DAMAGE_EXTRA+4<=#4000))|((CORE_DAMAGE_EXTRA>=#8000)&(CORE_DAMAGE_EXTRA+4<=#10000)),"CORE_DAMAGE_EXTRA must remain in fixed address space"
                assert ((CORE_DAMAGE_EXTRA_PENDING>=0)&(CORE_DAMAGE_EXTRA_PENDING+1<=#4000))|((CORE_DAMAGE_EXTRA_PENDING>=#8000)&(CORE_DAMAGE_EXTRA_PENDING+1<=#10000)),"CORE_DAMAGE_EXTRA_PENDING must remain in fixed address space"
                assert ((CORE_REGION_SLOT>=0)&(CORE_REGION_SLOT+1<=#4000))|((CORE_REGION_SLOT>=#8000)&(CORE_REGION_SLOT+1<=#10000)),"CORE_REGION_SLOT must remain in fixed address space"
                assert ((CORE_POINTER_SUPPRESSED>=0)&(CORE_POINTER_SUPPRESSED+1<=#4000))|((CORE_POINTER_SUPPRESSED>=#8000)&(CORE_POINTER_SUPPRESSED+1<=#10000)),"CORE_POINTER_SUPPRESSED must remain in fixed address space"
                assert ((CORE_POINTER_PAINTLOCK>=0)&(CORE_POINTER_PAINTLOCK+1<=#4000))|((CORE_POINTER_PAINTLOCK>=#8000)&(CORE_POINTER_PAINTLOCK+1<=#10000)),"CORE_POINTER_PAINTLOCK must remain in fixed address space"
