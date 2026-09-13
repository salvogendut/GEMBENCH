# Unified Notepad — Desktop handoff work

2026-09-13, issue #84, `feature/84-unified-notepad`.
The runnable-editor checkpoint was committed and pushed as **`e4c8e62`**.
This document records subsequent work, not another sprint or completed
normal-distribution delivery.

## Current checkpoint 2l: real document launch

File Manager document double-clicks now reach the actual two-bank Notepad in
the private MSX images. Normal images are unchanged; this is not completed
existing-instance delivery or full sprint acceptance. Checkpoints 2k/2l are
grouped in the document-handoff save following `e4c8e62`; consult the branch
history/upstream status for the current commit and publication state.

Filesystem **API v3** retains API v2's identity query and the existing operation
numbers. Operations 12/13 now participate in a bounded synchronous launch:

- Prepare copies the producer context's drive/path and the selected 11-byte
  name before a paged filesystem call can overwrite the native directory entry.
  File Manager immediately calls `WMOPEN`, not `WMLAUNCHAS` with that stale entry.
- Shared resident policy selects only this caller's preparation, binds it to
  the new owner **including generation**, and only that recipient can adopt.
  Preparation cannot overwrite an occupied transaction.
- Unconsumed requests expire on launch return: no window slot/owner/page,
  admission failure, non-registering entry, or an app that does not adopt.
  Early root rejection clears its own preparation; workers cannot cancel a
  root request. Resident owner cleanup also invalidates matching requests.
- Notepad adopts before registration, queries its copied identity and starts
  the existing staged load. Title/path/document are published only on success.
  Errors keep the blank/previous model intact; retained cleanup follows the
  existing explicit error acknowledgement policy. Full 4096-byte editing and
  separate 4096-byte transactional staging remain intact.

The private receiver uses `PORTABLE_FS_HANDOFF=1`, together with
`PORTABLE_FS_IDENTITY=1` and `PORTABLE_PACKAGE_STREAM=1`; matching GBFSCTX uses
`PORTABLE_FS_HANDOFF=1`. The boot-checked admission module is now `GBV4,6` and
the mode-specific routing module uses `GBWM,0x56/0x57`; mixed old/new module
compositions are rejected. Default profiles still publish filesystem API v1.
No new outer ABI number, opcode, bank limit or fixed-memory region was added.

Private File Manager uses `GB_FSCTX_LAUNCH` and checks API >=3. It excludes the
old native shell-delivery client: each text-file open currently starts a new
editor; it does **not** route a second document into an existing dirty editor.
Normal File Manager builds keep their previous behavior.

### Measured final fit

| Artifact | Size / limits |
| --- | --- |
| Notepad APP | 18697 bytes: primary 14428 + secondary 4269 |
| Primary | image end `785C`, DATA `7870`, BSS end `7EF4`; 20 / 12 bytes spare |
| Secondary | unchanged image end `50AD`, DATA `5E00`, BSS end `7E21` |
| Private File Manager | 14786 bytes |
| GBFSCTX v3 | 2298 bytes, within `6000..7F00` |
| Screen 6 / 7 child | 14536 / 16114 bytes; Screen 7 has 14 bytes spare |
| GBPKWM / GBAPV4 | unchanged extents: 1496 / 3014 bytes |

The resident policy uses existing routing-module padding. Primary savings
come from a wire-layout-checked 19-byte model snapshot copy, one identity
record instead of repeated metadata copies, and excluding unused producer/
free-space/cancel wrappers in `UNIVERSAL_MINIMAL`'s document FS subset. Default
SDK wrappers are unchanged. Both modes use APP SHA256
`922b0e5c3688bf6fddaa2252743812b4389d4e5fc3ec8e86741e0b919d01e05f`.

### Testing and manual images

Evidence is under `build/notepad-84/evidence/`:

- `handoff-regressions.log`: 50 tests pass, no skips. Includes real Z80 launch
  rollback/cleanup, shared owner/generation policy, copied SDK, editor atomic
  startup/error tests, package composition, secondary and IX/IRQ regressions.
- `handoff-final-openmsx{6,7}.log`: normal Desk launch, keyboard editing,
  chooser save/reopen and independent disk readback pass. Exact secondary-call
  preservation: 189 returns in Screen 6, 185 in Screen 7.
- `handoff-final-1983-{6,7}/result.json`: real Desktop → File Manager → Notepad
  double-clicks, focus/chrome, same-named files in `/ADOC` and `/ADOC/SUB`, exact
  model bytes and save-in-place disk readback; contexts/pages/seals reclaimed.
- `handoff-final-1983-6-bad/result.json`: corrupt the secondary CRC in a copied
  `NOTEPAD.APP`, attempt a document launch, verify rollback, then launch the
  undamaged Desk alias and verify a blank document—not the failed request.
  The earlier Screen 7 equivalent also passes (`handoff-1983-7-bad`).
- `handoff-boundary-1983-7/result.json`: 59 checks pass, including full 4096-byte
  load/save, rejected 4097-byte load retaining the old document, and dirty
  close/Cancel/Discard. Uses joystick fire, not a waiver of the known late
  keyboard Space-as-click issue. `stack_max=0` is not a root-stack measurement.

Private manual images (these contain the actual editor, not FSPROBE):

- Screen 6: `build/notepad-84/build/msx/portable-notepad-6-ghlvpr6p/filesystem.img`
- Screen 7: `build/notepad-84/build/msx/portable-notepad-7-3dzkwu_3/filesystem.img`

```sh
MSX_UNAPI=0 tools/run_msx.sh build/notepad-84/build/msx/portable-notepad-7-3dzkwu_3/filesystem.img
```

Open Disk A → ADOC → EXACT.TXT. Close the editor, enter SUB, open its EXACT.TXT:
the text must differ. File → Save writes to the selected directory. Desk →
Clock remains the private blank-Notepad alias; it is not the release Clock.
Prefer the mouse/joystick for clicks while the Space timing issue is open.

A separate writable Screen 7 copy was prepared for manual testing on
2026-09-13 (local build artifact, not checked into Git):

```sh
MSX_UNAPI=0 tools/run_msx.sh build/notepad-84/manual-DfNCgT/NOTEPAD.IMG
```

No rebuild is needed. Open `Disk A → ADOC → EXACT.TXT` ("Chosen root document.").
Edit, choose File → Save, close and reopen to verify persistence. Then close
the editor and open `ADOC/SUB/EXACT.TXT`: it should retain its different text,
"Chosen nested document." Test a dirty close with Cancel, then Discard.
In 1983, mount the same copy as an **IDE hard disk in read-write mode** using
your MSX2/512K + Sunrise/Nextor setup. Close one emulator before opening the
same writable image in the other. The automated 1983 runs used the corrected
firmware at `build/rainbios-170/build/rainbios_omega.rom`; the sibling ROMS copy
is not byte-identical, so do not assume identical firmware coverage.

Each File Manager document open currently creates a new editor window.
The normal `QA/MSX/GBMSX.IMG` still contains native Notepad; rebuilding the normal
distribution does not enable this private handoff profile.

Rebuild from explicitly synchronized `build/notepad-84/`, with the SDCC path
set, using `python3 tools/test_portable_fs_openmsx.py --mode 7 --notepad`.
`--reuse-app` avoids recompilation of an already audited, matching APP.
`tools/test_notepad_handoff_1983.py` takes the same bridge/firmware/image/worktree/
mode/output arguments as the existing Notepad runner; `--bad-app` exercises
failed admission and the subsequent blank launch. All writes are to disposable
hard-disk copies; no sibling emulator/firmware or release-image changes.

## Historical checkpoint 2k: copied context identity

The portable app previously could adopt a filesystem context but could not
read its configured filename/path. That prevented correct titles, Save As
location and exact-path document handling without native-memory dependencies.

Optional filesystem **API v2** adds operation 15, `identity`. The outer ABI
stays 2.1, GB_PARAMS operation 8 and its 32-byte header/512-byte transfer stay
unchanged, as do existing filesystem operations 0..14. The receiver validates
the context generation and implicit caller owner before publishing:

| Transfer bytes | Meaning |
| --- | --- |
| 0 | Configured drive |
| 1..11 | Exact raw space-padded 8.3 name |
| 12..59 | Configured absolute path, slash-normalized, NUL-terminated and zero padded |

Success returns `actual=60`. It does not change the context, read offset,
directory cursor or pending launch. It does not inspect the target file or
resolve/canonicalize filesystem aliases: it is a context snapshot, not `stat`.
The policy performs no target-file I/O; loading the paged service code remains
a receiver implementation detail. A malformed stored path or stale/foreign
handle publishes nothing. Bytes after the 60-byte result are untouched.

`gb_fsctx_identity(context, &result)` checks `filesystem_api_version >= 2`
before issuing the call, and leaves the caller's result unchanged on all
errors, including unsupported receivers and malformed result lengths.
The result is copied; it does not alias private kernel records or transfer
scratch. The helper is linked only with `UNIVERSAL_FS_IDENTITY=1`, which also
requires `UNIVERSAL_FS=1`. Existing Notepad is not yet linked to it.

The private MSX profile is enabled with `PORTABLE_FS_IDENTITY=1` in both the
receiver assembly and `build_fsctxmod.sh`. That selects the gate's additional
opcode, sysinfo API v2 publication and the corresponding module implementation.
Default MSX/CPC builds retain API v1 and reject the extra operation. There is
no normal-image update or CPC receiver enablement in this checkpoint.

## Evidence

Logs are under `build/notepad-84/evidence/`:

- `identity-regressions.log`: **48 tests pass, no skips**, covering the new
  service/SDK and existing filesystem, caller parameters, loader, editor,
  document/chooser and secondary-call behavior.
- `identity-host-tests.log`: 12 focused tests, including independent low/high
  state layouts, exact 60-byte Z80 structure offsets, ownership/stale errors,
  maximum-length and malformed paths, zero padding, unchanged context/offset
  and unchanged caller output on errors. SDK source/assembly passes the
  portable audit.
- `identity-msx{6,7}.log`: openMSX passes all **54 APP checks** per mode;
  each run observes **50 exact parameter returns** with caller state, snapshot
  region and VRAM preserved. Interleaved reads continue at the correct offset
  after identity queries; normal directory/read/write/truncate checks also pass.
- `identity-1983-{6,7}/result.json`: three real Desk launches per mode, all
  54 APP checks each time, explicit context closure, owner cleanup and exact
  disk readback. Only disposable hard-disk copies are written; source images
  remain unchanged. No sibling emulator/firmware changes.
- `identity-{abi,package,layout}.log`: ABI, deterministic/corrupt package checks
  and MSX fixed-memory inventory pass.
- `identity-default-module.log`: default `GBFSCTX.MOD` remains exactly 2024
  bytes, SHA `9ab4d8b625b34d226eb635f3112a7cf86ac8f6eaddc337680caac9b85f83abdc`.
  The optional v2 module is 2255 bytes, within the existing paged-module limit.
- `identity-notepad-compatibility.log`: existing two-bank Notepad rebuilds to
  the exact 18684-byte checkpoint-2j APP, SHA
  `d944f4565d4869d93f361b774fa38dbd657651878f8210133555b48de495b3c3`.

Same probe APP in both modes: 5554 bytes, SHA
`8486682bc5547be6c9cb32a9a692340570ae280c269df0ae4116f64411b55d62`.
Private diagnostic images (these are FS probes, **not new Notepad images**):

- `build/notepad-84/build/msx/portable-file-identity-6-lzc5735z/filesystem.img`
- `build/notepad-84/build/msx/portable-file-identity-7-35e49wif/filesystem.img`

Reproduce in the explicitly synchronized private worktree:

```sh
export PATH=/var/home/salvogendut/Dev/sdcc/bin:$PATH
python3 tools/test_portable_fs_openmsx.py --mode 7 --identity
```

For 1983, `tools/test_fsctx_identity_1983.py` takes `--bridge`, `--omega`,
`--sunrise`, `--image`, `--worktree`, `--mode` and a fresh `--output` directory.
Use the existing writable diagnostic bridge, not its default read-only variant.

## Remaining work

1. Existing-instance document delivery/reuse, with exact-path ownership and
   dirty Save/Discard/Cancel before replacing the current document. This is
   not provided by the synchronous startup transaction or native shell mailbox.
2. Portable configuration reload and the known late Space-as-click input race.
3. Broader focus/overlap/drag/resize/clipboard-exchange and latency qualification;
   confirm all sprint exit checks before claiming completion. The full-capacity
   BAS newline expansion/reopen limit remains recorded in the runtime document.

Normal image promotion and CPC streaming/editor delivery remain later work.
