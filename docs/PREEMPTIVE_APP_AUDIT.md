# Preemptive Application Audit

Date: 2026-08-26
Issue: [#477](https://github.com/salvogendut/geobench/issues/477)

This audit determines what each GEOBENCH application needs before the optional
preemptive build can be considered broadly application-compatible. It does not
assume that every application should become a scheduled worker.

## Responsiveness contract

GEOBENCH has three valid application execution models:

1. **Root callback**: short event, drawing, and lifecycle callbacks return to the
   window manager promptly.
2. **Bounded root job**: kernel, firmware, storage, network, bank-switching, and
   video operations remain on the root task, but long workflows advance by one
   bounded step per frame.
3. **Compute worker**: pure application-owned computation may be preempted. It
   must not call the kernel, firmware, storage, networking, bank-switching,
   drawing, modules, dialogs, or window-manager APIs.

An application is ready only when:

- ordinary input and close requests are handled between bounded work units;
- a pending operation can be cancelled or safely abandoned when its window
  closes;
- app-owned workers publish complete data units and cannot publish stale data
  after a new request or close;
- drive, directory, palette, fullscreen, sound, and interrupt state are restored
  on every exit path;
- cooperative and preemptive builds retain the same visible behavior;
- CPC, MSX2, and PCW have been exercised where the application is shipped.

There is no useful blanket conversion flag. Moving a callback that performs
kernel work into a worker would make the system unsafe rather than preemptible.

## Priority summary

| Priority | Area | Result |
|---|---|---|
| P0 | File Manager | Copy, directory preparation, and APP-icon probing are bounded root jobs. |
| P0 | Settings | Asset enumeration and icon-set validation are bounded root jobs; modal/I/O lifecycle needs cross-target validation. |
| P0 | Screensavers | All shipped savers now use fixed or incremental frame budgets; lifecycle validation remains. |
| P1 | BASIC and Paint | Mostly cooperative already, but long individual operations need bounds. |
| P1 | Browser, WGET, Telnet, Shell | Network/storage stays root-owned and must advance in bounded chunks. |
| P1 | Viewer, Notepad, Icon Editor, Mahjong | Root-owned; measure and split their longest operations where needed. |
| P2 | Clock and small utilities | Clock is already bounded; remaining utilities need lifecycle smoke tests. |

## P0: File Manager

Classification: **bounded root job required**. File Manager must not be a
compute worker because directory, file, icon, drag/drop, and drawing services
are kernel-owned.

Implemented:

- preemptive builds represent a drag/drop copy as app-owned state with a 24-bit
  offset and create/append/result state;
- the focused destination performs one complete read/write chunk per frame, so
  the shared transfer buffer is never left live across frame boundaries;
- the destination is raised and titled `Copying`; closing it cancels the job and
  removes the partial destination;
- other File Manager instances suspend storage operations while the copy owns
  the shared filesystem context;
- directory scans process at most four entries per frame and insert each entry
  directly into the sorted display order;
- the free-space query runs as a separate frame step after enumeration;
- opening a drive or directory leaves the existing screen intact during the
  scan and publishes the completed title and listing in one window repaint;
- embedded `.APP` icons are probed and drawn one visible slot per frame through
  `GBAPICK.MOD`; repaint callbacks perform no storage I/O;
- cooperative builds retain the original synchronous copy path.

Remaining risks:

- each directory entry and APP probe still requires one atomic backend
  operation on the root task; slow firmware cannot be preempted inside that
  operation;
- a missing `GBAPICK.MOD` leaves the generic APP icon, as intended, but needs a
  cross-target runtime check;
- multiple File Manager windows serialize scans and copies through the shared
  storage claim; icon probes run only while that claim is free. This still
  needs contention testing.

Required work:

1. Exercise the copy job on every storage backend, including cancellation and
   exact-multiple chunk sizes, before treating it as production-ready.
2. Exercise maximum-size directories and close a File Manager during each scan
   stage; verify the storage claim is always released.
3. Exercise generic, missing, single-codec, and dual-codec APP icons while
   scrolling and switching between list and icon views.

Acceptance tests:

- copy a 63 KiB file floppy-to-floppy, floppy-to-card, and card-to-floppy while
  moving the pointer and clock;
- cancel/close during copy, then open both source and destination directories;
- open a directory containing the maximum cached entries and embedded icons;
- repeat on CPC floppy, CPC M4/Albireo, MSX DOS drives, and PCW floppies.

## P0: Settings

Classification: **root-owned modal UI with bounded enumeration**. Settings
calls configuration storage, paged modules, live asset reload, palette changes,
and window-manager services, so it is not a worker candidate.

Implemented:

- selecting an asset or screensaver redraws only that selector as `Reading...`
  and returns to the managed-window frame loop;
- root-directory discovery and asset enumeration process at most four entries
  per frame across every available drive;
- icon-set pickers validate at most one `.IST` candidate per frame after the
  directory cursor is no longer needed;
- the completed list is handed to the existing modal popup, preserving the
  established selection, persistence, and live-reload behavior;
- closing Settings during enumeration restores the previous drive and releases
  the shared storage claim; cooperative builds retain synchronous enumeration.

Remaining risks:

- every `cfg_set()` rewrites `GEOBENCH.CFG` immediately;
- screensaver configuration modules and live titlebar/gadget/backdrop reloads
  execute atomically;
- the colour dialog owns a polling loop. This is intentional modal behavior,
  but all exits must restore modal and palette state.

Required work:

1. Validate picker cancellation and empty/missing asset directories on every
   target and storage backend.
2. Keep configuration writes and live reload calls on root, but make the UI
   explicit about the short commit operation and prevent re-entry.
3. Audit every modal exit, including ESC, missing module, disk error, and close,
   for cursor, modal, drive, palette, and repaint restoration.

Acceptance tests:

- open every picker with A/B/C present, missing, empty, and slow media;
- configure each configurable saver and cancel each dialog;
- change titlebar, gadgets, backdrop, wallpaper, colours, and MSX video mode;
- invoke Return to Defaults and close Settings at each intermediate state;
- verify the underlying File Manager remains correctly framed and opaque.

## P0: Screensavers

Screensavers are fullscreen and draw directly through kernel or target-native
video paths. They should remain **root-owned bounded frame renderers**. A worker
conversion would require a separate compute/display protocol and gives little
benefit while the desktop is intentionally hidden.

| Saver | Current bound | Audit result | Required action |
|---|---|---|---|
| SQUARES | One square per frame | Ready | Cross-target wake/exit smoke test. |
| ANT | Forty ant steps per frame; reset clears 256 grid bytes and 16 screen lines per frame | Converted | Cross-target reset and wake/exit test. |
| DECO | Four subdivision or four-row fill units per frame | Converted | Incremental stack traversal and leaf-band rendering; cross-target lifecycle test remains. |
| XMATRIX | 16 feeder columns, 512 cell updates, or 12 dirty glyph draws per frame | Converted | Cross-target speed, wake, and dense-screen test. |
| MOUNTAIN | Bounded clear, map generation, smoothing, noise, and cell drawing stages | Converted | Cross-target lifecycle and maximum-settings test remains. |
| FOREST | Four explicit recursion-frame transitions per frame | Converted | CPC/MSX lifecycle test remains. |
| STARFLD | At most 24 stars per frame with round-robin motion compensation | Converted | Test maximum stars and speed on each target. |
| FRACTALI | 16 clear lines, 192 points, four Koch expansions, or 16 segment copies per frame | Converted | Exercise both fractal types and cycle transitions. |
| MUNCH | At most 16 points per frame | Converted | Test the largest square and square transitions. |
| RORSCH | Explicit `PERFRAME` point budget | Ready | Cross-target wake/exit smoke test. |
| TRUCHET | Eight tiles per frame | Converted | Incremental tile generation; CPC/MSX lifecycle test remains. |
| LIGHTN | 32 clear lines or four main/fork bolt segments per frame | Converted | Exercise strike, fork, hold, clear, and wake transitions. |
| PYRO | 40 particles per frame with three compensated physics steps and O(1) free-slot allocation | Converted | Test maximum active-particle frame and burst reuse. |
| HELIX | Four curve segments per frame | Converted | Persistent curve state; CPC/MSX lifecycle test remains. |
| XROACH | Six roaches, updated every second frame | Ready | Cross-target movement, collision, and wake/exit test. |
| CATCLK | Fixed bitmap and hand/pupil update | Ready | Verify time, palette, and fullscreen restoration. |

All savers also need a common lifecycle test: launch-click suppression, keyboard
and mouse wake, palette/border restoration, fullscreen reset, and immediate
desktop repaint. The repeated keyboard-buffer drain loops are finite, but should
be covered by held-key tests on MSX2.

## P2: Clock

Classification: **root-owned bounded renderer; no worker required**.

- the focused-frame callback performs one time read and updates only when the
  displayed minute or second changes;
- a tick erases and redraws at most three hands plus the short digital readout;
- the Set Time form polls once per frame through the shared modal lifecycle and
  commits through the target clock service only after acceptance;
- full face construction is a fixed 30-segment rim plus 12 ticks and occurs only
  on launch, resize, fullscreen changes, or damage repaint;
- no Clock path performs filesystem, module, or network I/O, and no pure compute
  workload exists that would benefit from an app worker.

Required validation: set the time and cancel the dialog on CPC, MSX, and PCW;
toggle seconds, resize, enter/leave fullscreen, obscure/reveal the window, and
close from each state. Adding a worker or resident scheduler hook is explicitly
out of scope unless those bounded operations show measurable input latency.

## P1: Companion applications

### GB-BASIC

`BASIC.APP` is an event-driven editor and should remain root-owned. `BASRUN.APP`
already executes at most 24 statements and four scroll operations per frame,
which is the correct cooperative shape.

The remaining risk is an expensive *single* BASIC statement. Array creation,
data scans, string expressions, graphics lines/circles, and input parsing can
each run to completion inside one statement budget slot. Test those worst cases,
then make any over-budget statement resumable. Interpreter code cannot become a
worker while statements call console, graphics, input, or kernel services.

### GB-PAINT

Paint owns banked picture storage and several windows, so it remains root-owned.
Its 20x20 editing tile keeps flood fill, shape, clipboard, and undo loops tightly
bounded. The higher-risk paths are creating, loading, and saving a complete
picture of up to 16 KiB in one command, plus repeated bank transfers and full
pane repaints.

Convert picture creation and save/load into per-frame document jobs. Keep
interactive drags modal and bounded by user input. Do not move bank mapping,
kernel drawing, file I/O, or `gb_copybuf` users into a worker.

## P1: Remaining user applications

| Application | Classification | Main audit item |
|---|---|---|
| Browser | Bounded root network/parser job | Bound each receive, parse, image, redirect, and cache step; cancellation must close the channel. |
| WGET | Bounded root network/storage job | Verify one receive/write unit per frame and safe partial-file cleanup/resume. |
| Telnet | Bounded root network/serial job | Cap receive and ANSI parsing per frame; disconnect must cancel every transport state. |
| Shell | Needs bounded root commands | `cat` and `cp` currently loop through complete files inside one command. |
| Viewer | Root-owned image renderer | Image-only; retains native banked rendering and falls back to bounded visible-row reads when picture banks are exhausted. |
| Notepad | Root-owned editor | Measure full-document load/save, wrap, and redraw; split only operations that exceed a frame. |
| Icon Editor | Root-owned editor | Bound `.IST`/`.APP` load/save and conversion; preserve borrowed-bank and preview state. |
| Mahjong | Root-owned game | Measure deal/shuffle/hint and full-board draws; tile interaction is otherwise event-driven. |
| Disk Utility | Root-owned destructive I/O | Formatting remains atomic kernel/module work; enforce modal state and error cleanup. |
| Nettest | Root-owned network state machine | Verify every transport state has a timeout and performs one bounded operation per frame. |
| Time Sync | Root-owned serial state machine | Verify bounded polling, timeout, cancellation, and clock-setting completion. |
| Browser Save | Root-owned storage helper | It writes all cached pages in one frame; convert to one page/chunk per frame. |
| Clock | Short root callbacks | Ready after set-time, close, and drag smoke tests. |
| Calculator | Short root callbacks | Ready after input and close smoke tests. |
| Sound Test | Short root sequencer | Ready; ensure close always stops sound. |
| Form Reference | Short root callbacks | Ready; retain as a modal/widget lifecycle diagnostic. |

## Scheduler-specific applications

- **Desktop** is the non-preemptible root task and owns input, composition,
  storage, modules, firmware, and policy. It requires scheduler lifecycle and
  interrupt restoration tests, not worker conversion.
- **TASKDEMO** is diagnostic only. It proves involuntary switching and must not
  be staged in normal preemptive images.
- **XAOS** is the reference compute-worker conversion. Its worker performs only
  fixed-point Mandelbrot computation and publishes complete rows; root code owns
  all drawing and lifecycle.

## Implementation order

1. Validate the implemented File Manager copy, progressive directory scan, and
   queued APP-icon probing across all storage backends.
2. Validate Settings progressive picker enumeration and finish its modal cleanup audit.
3. Validate every incremental and fixed-budget screensaver, including dense and
   maximum-setting cases.
4. Complete the screensaver timing and lifecycle matrix across CPC, MSX2, and PCW.
5. GB-BASIC worst-statement tests and any required resumable statements.
6. GB-PAINT document create/load/save jobs.
7. Browser/WGET/Telnet/Shell and the remaining P1 application checks.
8. Complete cross-target smoke matrix before issue #477 is proposed for merge.

All changes should remain app-linked or app-local. This audit identifies no
reason to add more resident kernel code before the application passes are
complete.
