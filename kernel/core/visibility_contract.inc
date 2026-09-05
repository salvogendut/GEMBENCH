; Shared visibility/priority provider contract (#71).
;
; Code and state remain visible across application banks. Region/classification
; work is serialized root/compositor work; never re-enter an active iterator.
; Worker selection runs only after the platform has saved the complete context
; with interrupts excluded. It shares region scratch, so the platform must
; exclude switching while region/compositor work holds the scheduler lock.
;
; All rectangles are opaque, half-open, x/y/w/h bytes in the same native WM
; units as the clip. Origins/extents are unsigned; every right/bottom sum must
; fit in a byte without wrapping (<=255). Screen dimensions are 1..255.
; Native providers must normalize records into four contiguous geometry bytes.
; No canonical-pixel conversion, hardware clipping, drawing or bank I/O is here.
; CORE_Z_ORDER's live prefix is unique/alive and count<=CORE_WINDOW_MAX.
; The caller must initialize all visibility/owner metadata and valid geometry.
;
; CORE_CLIP_X/Y/W/H are contiguous. Prepare saves one immutable primary damage
; source and latches EXTRA_PENDING into adjacent EXTRA_ACTIVE, then clears
; pending. Primary/extra x/y/w/h are immutable through the whole z pass.
; Each surface starts from those sources; the extra excludes primary overlap.
; region_test bypasses extra-source continuation. Calls return A=1/NZ with
; a nonempty clip, or A=0/Z at exhaustion. The streaming band iterator has no
; fragment pool; FRAGMENT_COUNT is a wrapping diagnostic byte, NOT a bound.
;
; Classification saves/restores the incoming clip, and clears the contiguous
; surface+worker visibility arrays. Focus ranks 3, visible/uncovered 2,
; partially covered 1, fully hidden 0. Aggregation takes the maximum rank of
; an owner's surfaces for its designated worker slot (slot 0 remains root).
; This retains owner-ID-only lookup: generation validation belongs to lifetime
; publication/cleanup. Stale owner/window links are forbidden preconditions,
; not newly accepted public input. Rank refresh is explicit, not every slice.
;
; Selection returns every worker to runnable root before choosing another.
; Root searches focused/full/partial tiers in order, round-robin starting after
; WORKER_LAST within each tier; hidden workers retain their snapshots but are
; not selected. WORKER_CURRENT/LAST must be valid scheduler-owned slot values.
; Continuous higher-tier demand can starve lower tiers: existing policy, not
; a new fairness guarantee. Windowless service dispatch is separate from this
; visual-worker policy.
;
; VIS_WINDOW_RECT: A=slot -> HL=fixed contiguous x,y,w,h; preserve A/C,
;   clobber B/DE/flags as the original sched_wm_entry+INC sequence.
; VIS_WINDOW_FLAGS: A=slot -> HL=opaque flags cell; preserve A/C, clobber B/DE.
; VIS_ROOT_FLAGS: -> HL=root flags cell; preserve C=0 and the existing registers.
; CORE_WORKER_READY is the provider mask requiring both alive and runnable.
; VIS_RESTORE_CONTEXT: JR continuation with C=chosen slot, HL=its flags cell;
;   platform restores the saved context. VIS_RESUME_CONTEXT resumes the old
;   saved context when no candidate qualifies. The original saved-SP stack
;   item remains untouched. Continuations must be within Z80 JR reach, and
;   neither flags/rectangle macro may alter the context stack balance.
;
; These checks are local bounds/adjacency, not a complete map: the provider
; must exclude framebuffer, ROM, other allocations and context stacks itself.
CORE_VIS_HIDDEN equ 0
CORE_VIS_PARTIAL equ 1
CORE_VIS_FULL equ 2
CORE_VIS_FOCUSED equ 3
                assert (CORE_WINDOW_MAX>=2)&(CORE_WINDOW_MAX<=254),"invalid CORE_WINDOW_MAX"
                assert (CORE_OWNER_CAPACITY>=1)&(CORE_OWNER_CAPACITY<=255),"invalid CORE_OWNER_CAPACITY"
                assert (CORE_SCREEN_COLS>=1)&(CORE_SCREEN_COLS<=255),"invalid CORE_SCREEN_COLS"
                assert (CORE_SCREEN_LINES>=1)&(CORE_SCREEN_LINES<=255),"invalid CORE_SCREEN_LINES"
                assert (CORE_WORKER_READY>=1)&(CORE_WORKER_READY<=255),"invalid CORE_WORKER_READY"
                assert CORE_CLIP_Y==CORE_CLIP_X+1,"clip bytes must be contiguous"
                assert CORE_CLIP_W==CORE_CLIP_X+2,"clip bytes must be contiguous"
                assert CORE_CLIP_H==CORE_CLIP_X+3,"clip bytes must be contiguous"
                assert CORE_WORKER_VISIBILITY==CORE_SURFACE_VISIBILITY+CORE_WINDOW_MAX,"visibility arrays must be contiguous"
                assert CORE_COMPOSITOR_EXTRA_ACTIVE==CORE_COMPOSITOR_EXTRA_PENDING+1,"extra flags must be adjacent"
                assert (CORE_Z_ORDER & #FF)+CORE_WINDOW_MAX<=#100,"CORE_Z_ORDER crosses a 256-byte index page"
                assert (CORE_SURFACE_VISIBILITY & #FF)+CORE_WINDOW_MAX<=#100,"CORE_SURFACE_VISIBILITY crosses a 256-byte index page"
                assert (CORE_WORKER_VISIBILITY & #FF)+CORE_WINDOW_MAX<=#100,"CORE_WORKER_VISIBILITY crosses a 256-byte index page"
                assert (CORE_APP_WORKER_WIN & #FF)+CORE_OWNER_CAPACITY<=#100,"CORE_APP_WORKER_WIN crosses a 256-byte index page"
                assert (CORE_WIN_OWNER & #FF)+CORE_WINDOW_MAX<=#100,"CORE_WIN_OWNER crosses a 256-byte index page"
                assert ((CORE_Z_ORDER>=0)&(CORE_Z_ORDER+CORE_WINDOW_MAX<=#4000))|((CORE_Z_ORDER>=#8000)&(CORE_Z_ORDER+CORE_WINDOW_MAX<=#10000)),"CORE_Z_ORDER must remain in fixed address space"
                assert ((CORE_SURFACE_VISIBILITY>=0)&(CORE_SURFACE_VISIBILITY+CORE_WINDOW_MAX<=#4000))|((CORE_SURFACE_VISIBILITY>=#8000)&(CORE_SURFACE_VISIBILITY+CORE_WINDOW_MAX<=#10000)),"CORE_SURFACE_VISIBILITY must remain in fixed address space"
                assert ((CORE_WORKER_VISIBILITY>=0)&(CORE_WORKER_VISIBILITY+CORE_WINDOW_MAX<=#4000))|((CORE_WORKER_VISIBILITY>=#8000)&(CORE_WORKER_VISIBILITY+CORE_WINDOW_MAX<=#10000)),"CORE_WORKER_VISIBILITY must remain in fixed address space"
                assert ((CORE_APP_WORKER_WIN>=0)&(CORE_APP_WORKER_WIN+CORE_OWNER_CAPACITY<=#4000))|((CORE_APP_WORKER_WIN>=#8000)&(CORE_APP_WORKER_WIN+CORE_OWNER_CAPACITY<=#10000)),"CORE_APP_WORKER_WIN must remain in fixed address space"
                assert ((CORE_WIN_OWNER>=0)&(CORE_WIN_OWNER+CORE_WINDOW_MAX<=#4000))|((CORE_WIN_OWNER>=#8000)&(CORE_WIN_OWNER+CORE_WINDOW_MAX<=#10000)),"CORE_WIN_OWNER must remain in fixed address space"
                assert ((CORE_LIVE_WINDOWS>=0)&(CORE_LIVE_WINDOWS+1<=#4000))|((CORE_LIVE_WINDOWS>=#8000)&(CORE_LIVE_WINDOWS+1<=#10000)),"CORE_LIVE_WINDOWS must remain in fixed address space"
                assert ((CORE_FOCUS_SLOT>=0)&(CORE_FOCUS_SLOT+1<=#4000))|((CORE_FOCUS_SLOT>=#8000)&(CORE_FOCUS_SLOT+1<=#10000)),"CORE_FOCUS_SLOT must remain in fixed address space"
                assert ((CORE_WORKER_CURRENT>=0)&(CORE_WORKER_CURRENT+1<=#4000))|((CORE_WORKER_CURRENT>=#8000)&(CORE_WORKER_CURRENT+1<=#10000)),"CORE_WORKER_CURRENT must remain in fixed address space"
                assert ((CORE_WORKER_LAST>=0)&(CORE_WORKER_LAST+1<=#4000))|((CORE_WORKER_LAST>=#8000)&(CORE_WORKER_LAST+1<=#10000)),"CORE_WORKER_LAST must remain in fixed address space"
                assert ((CORE_CLIP_X>=0)&(CORE_CLIP_X+1<=#4000))|((CORE_CLIP_X>=#8000)&(CORE_CLIP_X+1<=#10000)),"CORE_CLIP_X must remain in fixed address space"
                assert ((CORE_CLIP_Y>=0)&(CORE_CLIP_Y+1<=#4000))|((CORE_CLIP_Y>=#8000)&(CORE_CLIP_Y+1<=#10000)),"CORE_CLIP_Y must remain in fixed address space"
                assert ((CORE_CLIP_W>=0)&(CORE_CLIP_W+1<=#4000))|((CORE_CLIP_W>=#8000)&(CORE_CLIP_W+1<=#10000)),"CORE_CLIP_W must remain in fixed address space"
                assert ((CORE_CLIP_H>=0)&(CORE_CLIP_H+1<=#4000))|((CORE_CLIP_H>=#8000)&(CORE_CLIP_H+1<=#10000)),"CORE_CLIP_H must remain in fixed address space"
                assert ((CORE_REGION_SLOT>=0)&(CORE_REGION_SLOT+1<=#4000))|((CORE_REGION_SLOT>=#8000)&(CORE_REGION_SLOT+1<=#10000)),"CORE_REGION_SLOT must remain in fixed address space"
                assert ((CORE_REGION_Z>=0)&(CORE_REGION_Z+1<=#4000))|((CORE_REGION_Z>=#8000)&(CORE_REGION_Z+1<=#10000)),"CORE_REGION_Z must remain in fixed address space"
                assert ((CORE_REGION_LEFT>=0)&(CORE_REGION_LEFT+1<=#4000))|((CORE_REGION_LEFT>=#8000)&(CORE_REGION_LEFT+1<=#10000)),"CORE_REGION_LEFT must remain in fixed address space"
                assert ((CORE_REGION_TOP>=0)&(CORE_REGION_TOP+1<=#4000))|((CORE_REGION_TOP>=#8000)&(CORE_REGION_TOP+1<=#10000)),"CORE_REGION_TOP must remain in fixed address space"
                assert ((CORE_REGION_RIGHT>=0)&(CORE_REGION_RIGHT+1<=#4000))|((CORE_REGION_RIGHT>=#8000)&(CORE_REGION_RIGHT+1<=#10000)),"CORE_REGION_RIGHT must remain in fixed address space"
                assert ((CORE_REGION_BOTTOM>=0)&(CORE_REGION_BOTTOM+1<=#4000))|((CORE_REGION_BOTTOM>=#8000)&(CORE_REGION_BOTTOM+1<=#10000)),"CORE_REGION_BOTTOM must remain in fixed address space"
                assert ((CORE_REGION_Y>=0)&(CORE_REGION_Y+1<=#4000))|((CORE_REGION_Y>=#8000)&(CORE_REGION_Y+1<=#10000)),"CORE_REGION_Y must remain in fixed address space"
                assert ((CORE_REGION_BAND_END>=0)&(CORE_REGION_BAND_END+1<=#4000))|((CORE_REGION_BAND_END>=#8000)&(CORE_REGION_BAND_END+1<=#10000)),"CORE_REGION_BAND_END must remain in fixed address space"
                assert ((CORE_REGION_X>=0)&(CORE_REGION_X+1<=#4000))|((CORE_REGION_X>=#8000)&(CORE_REGION_X+1<=#10000)),"CORE_REGION_X must remain in fixed address space"
                assert ((CORE_REGION_COVERED>=0)&(CORE_REGION_COVERED+1<=#4000))|((CORE_REGION_COVERED>=#8000)&(CORE_REGION_COVERED+1<=#10000)),"CORE_REGION_COVERED must remain in fixed address space"
                assert ((CORE_REGION_SCAN_Z>=0)&(CORE_REGION_SCAN_Z+1<=#4000))|((CORE_REGION_SCAN_Z>=#8000)&(CORE_REGION_SCAN_Z+1<=#10000)),"CORE_REGION_SCAN_Z must remain in fixed address space"
                assert ((CORE_REGION_SAVED_CLIP>=0)&(CORE_REGION_SAVED_CLIP+4<=#4000))|((CORE_REGION_SAVED_CLIP>=#8000)&(CORE_REGION_SAVED_CLIP+4<=#10000)),"CORE_REGION_SAVED_CLIP must remain in fixed address space"
                assert ((CORE_REGION_FRAGMENT_COUNT>=0)&(CORE_REGION_FRAGMENT_COUNT+1<=#4000))|((CORE_REGION_FRAGMENT_COUNT>=#8000)&(CORE_REGION_FRAGMENT_COUNT+1<=#10000)),"CORE_REGION_FRAGMENT_COUNT must remain in fixed address space"
                assert ((CORE_REGION_TEST_X>=0)&(CORE_REGION_TEST_X+1<=#4000))|((CORE_REGION_TEST_X>=#8000)&(CORE_REGION_TEST_X+1<=#10000)),"CORE_REGION_TEST_X must remain in fixed address space"
                assert ((CORE_REGION_REFRESH_Z>=0)&(CORE_REGION_REFRESH_Z+1<=#4000))|((CORE_REGION_REFRESH_Z>=#8000)&(CORE_REGION_REFRESH_Z+1<=#10000)),"CORE_REGION_REFRESH_Z must remain in fixed address space"
                assert ((CORE_REGION_OWNER_INDEX>=0)&(CORE_REGION_OWNER_INDEX+1<=#4000))|((CORE_REGION_OWNER_INDEX>=#8000)&(CORE_REGION_OWNER_INDEX+1<=#10000)),"CORE_REGION_OWNER_INDEX must remain in fixed address space"
                assert ((CORE_REGION_OWNER_ID>=0)&(CORE_REGION_OWNER_ID+1<=#4000))|((CORE_REGION_OWNER_ID>=#8000)&(CORE_REGION_OWNER_ID+1<=#10000)),"CORE_REGION_OWNER_ID must remain in fixed address space"
                assert ((CORE_REGION_WORKER_SLOT>=0)&(CORE_REGION_WORKER_SLOT+1<=#4000))|((CORE_REGION_WORKER_SLOT>=#8000)&(CORE_REGION_WORKER_SLOT+1<=#10000)),"CORE_REGION_WORKER_SLOT must remain in fixed address space"
                assert ((CORE_REGION_OWNER_MAX>=0)&(CORE_REGION_OWNER_MAX+1<=#4000))|((CORE_REGION_OWNER_MAX>=#8000)&(CORE_REGION_OWNER_MAX+1<=#10000)),"CORE_REGION_OWNER_MAX must remain in fixed address space"
                assert ((CORE_REGION_SLOT_SCAN>=0)&(CORE_REGION_SLOT_SCAN+1<=#4000))|((CORE_REGION_SLOT_SCAN>=#8000)&(CORE_REGION_SLOT_SCAN+1<=#10000)),"CORE_REGION_SLOT_SCAN must remain in fixed address space"
                assert ((CORE_COMPOSITOR_DAMAGE>=0)&(CORE_COMPOSITOR_DAMAGE+4<=#4000))|((CORE_COMPOSITOR_DAMAGE>=#8000)&(CORE_COMPOSITOR_DAMAGE+4<=#10000)),"CORE_COMPOSITOR_DAMAGE must remain in fixed address space"
                assert ((CORE_COMPOSITOR_EXTRA>=0)&(CORE_COMPOSITOR_EXTRA+4<=#4000))|((CORE_COMPOSITOR_EXTRA>=#8000)&(CORE_COMPOSITOR_EXTRA+4<=#10000)),"CORE_COMPOSITOR_EXTRA must remain in fixed address space"
                assert ((CORE_COMPOSITOR_EXTRA_PENDING>=0)&(CORE_COMPOSITOR_EXTRA_PENDING+1<=#4000))|((CORE_COMPOSITOR_EXTRA_PENDING>=#8000)&(CORE_COMPOSITOR_EXTRA_PENDING+1<=#10000)),"CORE_COMPOSITOR_EXTRA_PENDING must remain in fixed address space"
                assert ((CORE_COMPOSITOR_EXTRA_ACTIVE>=0)&(CORE_COMPOSITOR_EXTRA_ACTIVE+1<=#4000))|((CORE_COMPOSITOR_EXTRA_ACTIVE>=#8000)&(CORE_COMPOSITOR_EXTRA_ACTIVE+1<=#10000)),"CORE_COMPOSITOR_EXTRA_ACTIVE must remain in fixed address space"
                assert ((CORE_COMPOSITOR_SOURCE>=0)&(CORE_COMPOSITOR_SOURCE+1<=#4000))|((CORE_COMPOSITOR_SOURCE>=#8000)&(CORE_COMPOSITOR_SOURCE+1<=#10000)),"CORE_COMPOSITOR_SOURCE must remain in fixed address space"
