# Preemptive Application Audit

Date: 2026-08-25
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
| P0 | Settings | Needs bounded asset enumeration and careful modal/I/O lifecycle. |
| P0 | Screensavers | Several are already frame-bounded; five need incremental generation. |
| P1 | BASIC and Paint | Mostly cooperative already, but long individual operations need bounds. |
| P1 | Browser, WGET, Telnet, Shell | Network/storage stays root-owned and must advance in bounded chunks. |
| P1 | Viewer, Notepad, Icon Editor, Mahjong | Root-owned; measure and split their longest operations where needed. |
| P2 | Small utilities and diagnostics | Mostly ready after lifecycle smoke tests. |

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

Current risks:

- asset pickers synchronously enumerate one or more drives before opening;
- icon-set enumeration additionally loads every candidate `.IST` to validate
  its slot count;
- every `cfg_set()` rewrites `GEOBENCH.CFG` immediately;
- screensaver configuration modules and live titlebar/gadget/backdrop reloads
  execute atomically;
- the colour dialog owns a polling loop. This is intentional modal behavior,
  but all exits must restore modal and palette state.

Required work:

1. Add an app-owned picker-enumeration job and a small `Reading...` state.
2. Scan one bounded directory unit per frame; validate at most one icon set per
   step.
3. Keep configuration writes and live reload calls on root, but make the UI
   explicit about the short commit operation and prevent re-entry.
4. Audit every modal exit, including ESC, missing module, disk error, and close,
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
| ANT | Fixed `STEPS` per frame | Measure | Confirm the configured step count keeps wake latency short. |
| DECO | Complete subdivision/layout in one call | Needs work | Make subdivision and leaf drawing incremental. |
| XMATRIX | Fixed columns plus complete cell scan | Measure | Measure worst-case dirty-cell frame on all targets. |
| MOUNTAIN | Drawing is cell-budgeted; terrain regeneration is not | Needs work | Split clear, peaks, spreading, noise, and drawing into stages. |
| FOREST | Three complete recursive trees per regeneration | Needs work | Replace recursive one-shot growth with an explicit bounded branch stack. |
| STARFLD | Bounded configured star count | Ready/measure | Test maximum stars and speed on each target. |
| FRACTALI | Drawing is budgeted; Koch geometry setup is one-shot | Measure | Bound geometry setup if target timing exceeds one frame. |
| MUNCH | One bounded scanline-width pass | Ready/measure | Test the largest square. |
| RORSCH | Explicit `PERFRAME` point budget | Ready | Cross-target wake/exit smoke test. |
| TRUCHET | Complete tile grid per regeneration | Needs work | Generate a bounded number of tiles per frame. |
| LIGHTN | Fixed bolt generation and drawing pass | Measure | Measure generation plus both line passes. |
| PYRO | Fixed particle array per frame | Ready/measure | Test maximum active-particle frame. |
| HELIX | Complete `STEPS` curve per regeneration | Needs work | Retain curve index and draw a bounded segment batch. |
| XROACH | Fixed roach count and sprite loops | Ready/measure | Test maximum movement/collision frame. |
| CATCLK | Fixed bitmap and hand/pupil update | Ready | Verify time, palette, and fullscreen restoration. |

All savers also need a common lifecycle test: launch-click suppression, keyboard
and mouse wake, palette/border restoration, fullscreen reset, and immediate
desktop repaint. The repeated keyboard-buffer drain loops are finite, but should
be covered by held-key tests on MSX2.

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
| Viewer | Root-owned renderer | Retain native banked renderers; measure decode/blit batches and keep the known-good paths. |
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
2. Settings progressive picker enumeration and modal cleanup audit.
3. Incremental DECO, MOUNTAIN, FOREST, TRUCHET, and HELIX generation.
4. Screensaver timing and lifecycle matrix across CPC, MSX2, and PCW.
5. GB-BASIC worst-statement tests and any required resumable statements.
6. GB-PAINT document create/load/save jobs.
7. Browser/WGET/Telnet/Shell and the remaining P1 application checks.
8. Complete cross-target smoke matrix before issue #477 is proposed for merge.

All changes should remain app-linked or app-local. This audit identifies no
reason to add more resident kernel code before the application passes are
complete.
