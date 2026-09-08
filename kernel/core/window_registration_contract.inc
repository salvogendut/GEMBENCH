; Native WM registration and chrome (not a public universal ABI gate).
;
; Serialized root/kernel calls under the scheduler lock. Native descriptors,
; callback/title pointers, current code page and pending/current owner are
; trusted and valid. Geometry is nonempty, has room for the selected furniture
; and does not wrap byte arithmetic. Public validation/coordinate conversion
; must precede this boundary. Callbacks cannot mutate the stack during paint.
;
; Frozen native entry: page +0, xywh +1, frame/managed desc +5, repaint +7,
; event +9, menu +11, flags +13, 11-byte argument +14. Descriptor: xywh +0,
; min size +4, proc +6, title +8, worker +10; ONLY explicit selector B6 opts
; into kind byte +12. Legacy garbage beyond byte 11 is never consulted.
;
; wm_register returns CF on success, NC/A=FF on full. Full must not publish
; alive/count/z-order/generation/owner changes (wm_desc scratch may change).
; k_wm_managed is the existing VOID native entry, with no flags/status promise.
; Both publish focus before the event loop maps it. Bind identity from wm_slot
; BEFORE focus assignment; consume a pending owner only on successful attach.
; No rollback or invalid-owner recovery is promised at this private boundary.
;
; k_wm_managed patches the native entry, publishes MW_RECT/mw_desc and seeds
; damage, but does not paint or install menus. Caller completes menu/content
; setup before mapping focus/painting; task_worker temporarily occupies menu.
; This unit registers worker metadata, not a runnable task or IRQ consumer.
;
; CHROME_ENTRY_FLAGS: HL=PAINTED entry -> HL=its flags; clobber DE/flags only
; in production. Never consult WM_FOCUS: background kinds can differ.
; CHROME_*_STORAGE macros retain historical MSX resident cells/placement; a
; fixed-state provider predefines those symbols and emits no cells here.
; CHROME_STRING_COPY_LOOP: B=maximum payload, HL=source, DE=fixed destination;
; copy up to B bytes, always terminate, no bank change. Native title cap=23
; plus NUL (unlike 48-character generic text). kw_title must hold >=24 bytes.
;
; fill_xywh/fill_block, k_frame, font pens/text and data-page map/restore
; bind graphics. Fill encoding KWB_* is target-native. All fills and text
; honor the immutable active compositor clip AND physical screen bounds;
; fill_block preserves its input fb_x/y/w/h because stripes reuse them.
; Managed paint uses the compositor pointer lock and restores the caller page
; before invoking its proc with GB_MSG_DRAW. IRQs may run during locked paint;
; these native routines do not independently preserve IFF or acquire a lock.
; TITLEBAR_TILE/THEMED_GADGETS select existing render configurations, not a
; different window policy. Enabled tile/bitmap hooks must be real providers.
                assert WM_ESZ==25,"native window record must remain frozen"
                assert WM_FR_FRAME==5,"native managed descriptor offset"
                assert WM_FR_EVENT==9,"native event offset"
                assert WM_FR_FLAGS==13,"native flags offset"
                assert WM_MAXWIN==CORE_WINDOW_MAX,"native/identity capacity mismatch"
