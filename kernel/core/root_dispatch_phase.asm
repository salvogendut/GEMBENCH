; Shared post-input root-loop phase. Fall through to the caller's frame/bar
; routing: one non-nested queue head, remap resulting focus, reset native clip.
; Fixed code/stack, root task and scheduler lock held. Hooks preserve those
; invariants; delivery may change focus. This is not a complete input/WM loop.
                call ROOT_DISPATCH_ONE
                call ROOT_MAP_FOCUS
                call ROOT_FULL_CLIP
