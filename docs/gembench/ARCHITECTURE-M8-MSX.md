# Architecture Milestone 8: MSX2 background visual timers

Status: **implemented on the MSX2 target in issue
[#45](https://github.com/salvogendut/GEMBENCH/issues/45)**.

Milestone 8 completes the first visual-timer slice of application-owned worker
lifecycle from improvement 3 of the SymbOS-inspired review. Clock's graphical
face can now advance while another application owns focus. CPC and PCW retain
their existing focused-frame Clock path.

## Execution contract

The existing preemptive scheduler still owns execution. Clock opts its managed
window into one pure application worker with `gb_task_enable()`. That worker may
read app-owned bytes and the fixed time snapshot refreshed by Desktop, but it
may not call the kernel, firmware, drawing code, filesystem, or a paged module.

When the displayed minute or second changes, the worker calls
`gb_timer_damage(x, y, w, h)`. Clock alternates two component requests: a tight
bounding rectangle around the old and new hands, then either the three-byte
seconds field or the changed full digital field at a minute boundary. The rim,
hour ticks, unchanged `HH:MM`, title, borders, and resize furniture stay outside
the frequent damage. This leaf performs only fixed-RAM reads and writes. It
coalesces into one mailbox, so a slow compositor cannot accumulate timer events.
Ordinary `GB_MSG_FRAME` delivery remains focused-only; no background application
callback enters the graphical runtime.

Desktop remains the root policy owner. Its always-live bar hook refreshes the
fixed time bytes and calls `gb_timer_collect()`. The collector validates the
publishing window's slot and generation, confirms that it still has a live
application owner, snapshots the mailbox, and retains that source with bit 7
set until the normal damage compositor returns. That active identity lets Clock
select its component-only draw and makes a recursive Desktop collection a
no-op. Repainting therefore stays bottom-up and preserves every higher window.
The V9938 command engine is explicitly drained after a hands-only pass before a
higher window is restored. Because the MSX pointer is a hardware sprite, the
active timer tag also keeps it visible instead of parking it for each tick.

Fullscreen suppresses publication. Closing Clock clears its scheduler runnable
state through the existing window/application lifecycle. A queued request from
a closed or reused slot fails owner/generation validation and is discarded.

## Fixed memory and build profiles

The Screen 7 child COM has only three free bytes, so no resident timer service
was added. The mailbox uses the final six bytes before the existing filesystem
context area:

| Address | Contents |
| --- | --- |
| `0xC3CA` | `0` empty; `1..8` pending slot + 1; `0x81..0x88` active source |
| `0xC3CB-0xC3CE` | damage rectangle `x, y, w, h` |
| `0xC3CF` | publishing window generation |

`tools/build_capp.sh` exposes two MSX2-only profiles:

- `GB_TIMER=1` requires `TASK=1` and links only the worker publisher;
- `GB_TIMER_COLLECTOR=1` requires `TASK_ROOT=1` and links only root policy.

The release build applies the publisher to Clock and the collector to Desktop.
Explicit cooperative MSX builds retain the old Clock behavior and do not link
either side. Clock is 12,736 bytes and Desktop is 15,760 bytes. Clock's data and
BSS end below `0x7300`; Desktop's end at `0x7EF6`, below the scheduler snapshot
at `0x7F00`. The Screen 6 and Screen 7 child COMs are 14,548 and 16,126 bytes
respectively.

## Validation

The host model checks coalescing, snapshot/republish behavior, generation-safe
slot reuse, fixed layout, and build-profile guards. The openMSX test launches
the exact staged Clock through File Manager, enables seconds, raises File
Manager over it, and observes several seconds with File Manager still focused.

The reference run on 2026-08-30 recorded four background Clock draws (hand,
seconds, hand, seconds), zero focused Clock frames, unchanged focus, two runnable
scheduler contexts, and an identical foreground overlap hash (`3671906385`)
before and after. The hand rectangles measured only `16x17` and `17x15` cells;
both seconds rectangles were exactly `3x8`. The hardware pointer remained shown
through every active timer pass.

```sh
python3 -m unittest tests.test_background_timer -v
make gembench-msx
OPENMSX='distrobox enter my-distrobox -- openmsx' \
  MSX_HEADLESS=1 make gembench-m8-timer-openmsx
```

For a manual check, boot `QA/MSX/GBMSX.IMG`, open Clock, enable **Show
Seconds**, then activate and overlap another window while leaving part of the
watch visible. The digital value and graphical hands must continue advancing;
the static face and `HH:MM` digits should remain steady, the pointer should not
blink, and the foreground window must retain focus and remain visually intact.

## Deliberate limits

This is one coalesced visual-damage channel, not a general timer queue. It does
not deliver arbitrary background window messages, promise exact tick counts,
run drawing code in workers, or add a public resident ABI entry. Multiple timer
registrations, periodic control messages, and CPC/PCW backends remain future
work and should be added only for measured application needs.
