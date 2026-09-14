# Unified Notepad — private runtime checkpoint 2j

2026-09-13, issue #84, branch `feature/84-unified-notepad`.
Continues the [consolidated sprint](UNIFIED-NOTEPAD.md#consolidated-sprint--runnable-msx-notepad).
The actual editor now builds and runs. This is **not** completion of the sprint
or replacement of native Notepad in either normal distribution.

**Historical status:** normal delivery and all later milestone-1 acceptance are
now complete; see [UNIFIED-NOTEPAD-CLOSURE.md](UNIFIED-NOTEPAD-CLOSURE.md).
The restrictions below describe this private checkpoint at the time it ran.

Saved/pushed as `e4c8e62`. Subsequent [Desktop handoff work](UNIFIED-NOTEPAD-HANDOFF.md)
now includes checkpoint **2l**: actual File Manager exact-path document opens,
bound recipient/rollback, editor startup adoption and private images. Read that
document for the latest APP hash, sizes and evidence. The numbers below are
the historical 2j checkpoint, not the current handoff-enabled build.

## Implementation and measured fit

`apps/unotepad/secondary/main.c` owns the unchanged editor model, its 4096-byte
document and separate 4096-byte transactional load/paste staging. The primary
keeps window/menu, chooser, clipboard and filesystem work. `protocol.h` defines
a 512-byte, explicit little-endian copied protocol: no cross-bank pointers.
Commands cover editing/selection, atomic staged publication, chunked export,
BASIC newline conversion and batches of five rendered rows. Cached layout and
caret metadata avoid rescanning the document on every idle frame.

The primary shares its idle, caller-owned FS transfer buffer with computation
packets. It borrows an exclusive 768-byte scratch union for the chooser, I/O,
clipboard and popup save-under. During the modal popup its callbacks cannot
start any of those other scratch users. Filesystem calls can overwrite the
packet: BASIC completion is saved before writing its payload.

| Final artifact | Measured extent |
| --- | --- |
| Complete APP | 18684 bytes; primary 14415 + secondary 4269 |
| Primary image / data | image ends `784F`; DATA starts `7870`; BSS ends `7EF4` |
| Primary remaining room | 33 bytes before DATA, 12 before the `7F00` snapshot boundary |
| Secondary image / data | image ends `50AD`; DATA starts `5E00`; BSS ends `7E21` |
| MSX Screen 6 / 7 child | unchanged 14534 / 16112 bytes; Screen 7 still has 16 bytes spare |

APP SHA256:
`d944f4565d4869d93f361b774fa38dbd657651878f8210133555b48de495b3c3`.
Both MSX modes use these exact APP bytes. No memory boundary or document
capacity was relaxed. Additional integration will require measured savings;
the primary is still very tight.

### Opt-in SDK build profiles

`tools/build_unotepad.sh` selects these private application-side options:

- `UNIVERSAL_IX=1`: compact SDCC IX frames. Generated frozen-vector wrappers
  preserve IX **after** argument marshalling, including tail calls. Raw native
  wrappers and default universal builds are unchanged. The instruction fixture
  exercises 22 marshalled/tail-call cases with a deliberately clobbering kernel
  and interrupts.
- `UNIVERSAL_MINIMAL=1`: omits unused convenience helpers, single-entry directory
  calls and whole-buffer document-I/O entry points. It does not remove kernel
  services or change the ABI; references to omitted helpers fail at link time.
- `UNIVERSAL_MENU_BORROWED=1`: the app supplies
  `gb_universal_popup_buffer()`, returning 768 live primary bytes exclusively
  available until popup return, including during reentrant poll callbacks.
  Default callers retain their separate library-owned save-under buffer.
- `gb_docio_load_chunks/save_chunks/chunk`: one bounded filesystem operation
  per step, without retaining a full primary document buffer. Existing job
  layout, exact-capacity EOF probe, cancellation and error rules remain intact.

Long rows are split at the semantic text service's 48-character limit, including
selection highlighting. Startup/click debounce drains a bounded 64 queue slots;
a filtered pointer arrow may return zero while a later typed character remains.

## Evidence and limits

All logs below are under `build/notepad-84/evidence/`.

- `editor-final-suite.log`: **61 focused host/Z80 tests pass, no skips**;
  actual editor/model, chunked storage fault paths, clipboard/chooser,
  malformed copied commands, 4-KiB capacity, long-line drawing, startup input
  draining, kernel-IX wrappers and earlier loader/call fixtures.
- `editor-final-{abi,package,layout}.log`: ABI, package corruption/determinism,
  and MSX low-RAM inventory checks pass (55 ranges, nine declared overlays).
- `editor-openmsx6-polled.log`, `editor-openmsx7-polled.log`: actual Desk launch,
  keyboard editing, File/Save As, explicit confirmation, close, fresh-owner
  launch, chooser reopen, edit and dirty discard pass. Independently read
  `SAVED.TXT` is exactly `abc\n`. There are 189/177 exact computation-return
  restoration checks, with final seal reclamation.
- `editor-1983-6-boundary/result.json`: 50 checks, keyboard-pointer input;
  small-file round trip, dirty Cancel/Discard, full 4096-byte load/save with
  exact disk readback, capacity rejection, and 4097-byte load rejection with
  the old document retained. Owner/page pool and seals return to baseline.
- `editor-1983-7-joystick/result.json`: the same boundary/recovery workflow,
  59 checks using real keyboard text and joystick-port-1 trigger clicks.
  Bridge hash `5af0fa8aa5cc7302109e2d1f74e7c1abb69608e5223c2c023614a8600dd762dc`.
  The bridge links unmodified sibling emulator sources; the writable-image
  profile is explicit and the driver writes only a fresh image copy.

**Retained input discrepancy:** Screen 7 runs using Space as keyboard-pointer
fire (`editor-1983-7-{boundary,polled}`) can insert a stray character before
closing, correctly triggering the dirty confirmation. Bounded queue draining
helps startup/queued arrows but does not establish that the poll/BIOS-key timing
race is fixed. Joystick success is separate evidence, not a waiver of that
failure. Physical SDL mouse input has not been qualified by these bridge runs.

The openMSX observer checks SP/IFF/lock/mapper/primary snapshot restoration.
An already-running asynchronous HMMV may finish during computation: when the
VDP was busy on entry, port-write guards replace the idle-VDP byte-equality
check. This permits prior drawing to complete, not secondary-issued drawing.
Idle-VDP calls retain strict VRAM equality; default earlier probes are unchanged.

Failed runs remain available. Some earlier failures were observers reading
temporary ROM mappings, acting before streamed registration/first paint, or
ending a short click before the guest polled it. No guest RAM patches, injected
calls or emulator/firmware fixes were used to pass the editor tests.

## Build and try it

The isolated build worktree must be explicitly synchronized with changed source
files; it is not a live mirror. From an up-to-date private worktree:

```sh
export PATH=/var/home/salvogendut/Dev/sdcc/bin:$PATH
bash tools/build_unotepad.sh
python3 tools/test_portable_fs_openmsx.py --mode 7 --notepad
```

Use the toolchain/openMSX from `distrobox enter my-distrobox` as needed.
The fixture builder prints its fresh image directory. Current matching images:

- Screen 7: `build/notepad-84/build/msx/portable-notepad-7-4zhwnl2g/filesystem.img`
- Screen 6: `build/notepad-84/build/msx/notepad-runtime-6/filesystem.img`

For a manual test, preserve evidence by copying the selected image first:

```sh
notepad_trial=$(mktemp -d /tmp/notepad-84-XXXXXX)
cp build/notepad-84/build/msx/portable-notepad-7-4zhwnl2g/filesystem.img "$notepad_trial/disk.img"
MSX_UNAPI=0 tools/run_msx.sh "$notepad_trial/disk.img"
```

In this **test fixture only**, Desk → Clock launches Notepad (the CLOCK alias
drives real shell launch); `GBENCH/NOTEPAD.APP` contains the same unified APP.
Use File → Load/Save As for document tests. Desktop document double-click
handoff is not yet integrated. In 1983, mount a disposable copy as the Sunrise
hard disk; prefer a real mouse/joystick trigger over Space-as-click.

`tools/test_notepad_openmsx.py --image … --output NEW_DIRECTORY` repeats the
small-file test without rebuilding. `tools/test_notepad_1983.py --boundary`
adds the full-capacity/oversize tests; supply bridge, firmware, matching image,
worktree, mode and a fresh output directory. Build a writable diagnostic bridge
with `MSX_TEST_WRITABLE_IMAGE=1 tools/build_msx_stability_1983.sh OUTPUT`.
The default bridge still mounts images read-only.

## Still required in this sprint

1. Exact Desktop document-name/path handoff, existing-instance behavior and
   portable configuration reload. `gb_fsctx_adopt_launch()` alone does not
   expose all metadata needed by the chooser/title; do not read native mailboxes.
2. Resolve/qualify the Space-as-click timing discrepancy. Measure full-document
   input latency, and qualify focus/overlap/drag/resize, selection and inter-app
   clipboard with real editor instances, not only host models.
3. Extend openMSX runtime coverage to the full-capacity/fault cases; qualify
   BASIC load/save edge cases (an all-newline 4-KiB document can save as 8 KiB).
   Existing saves are not atomic replacement and do not promise power-loss safety.
4. Re-run the bounded acceptance set and publish final manual instructions.
   CPC receiver/call qualification and normal distribution replacement follow.

Normal MSX/CPC Desktop/runtime image hashes remain exactly those recorded in
the previous checkpoint. The user requested saving/pushing 2j before proceeding
to Desktop document handoff; no merge or normal-image replacement is included.
