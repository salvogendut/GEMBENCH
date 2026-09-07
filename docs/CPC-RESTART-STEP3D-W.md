# CPC restart 3D-W — System/Settings integration

Issue #77, branch `feature/77-cpc-production-adapters`, following `66b5cc9`.
2026-09-07. **W1 is implemented and M4/1984 validated. W2/W3 remain open.**
W2 has started with the [W2-A platform boundary and compile audit](CPC-RESTART-STEP3D-W2-A.md);
this is preparatory, not a runnable Settings application.
The later [desktop-first delivery update](CPC-RESTART-PLAN.md#desktop-first-delivery-update--2026-09-07)
prioritizes Desktop-required bindings; complete Settings/saver support remains
tracked here but does not block the first usable desktop milestone.

## Gates

1. **W1 — configuration persistence/reload (complete).** Extract the actual
   Settings configuration edit logic without changing MSX output. Bind it to
   owned CPC filesystem contexts, bounded requests and readback verification.
   Exercise a real appearance change, no-op, failure and reboot persistence on
   private M4 images. Do not enable the full native `GB_RELOAD` contract merely
   because the diagnostic root can reparse configuration.
2. **W2 — actual Settings application.** Measure and bind its native application
   loading, managed forms, implicit directory/file state, configuration outputs,
   live palette/title assets and saver-module interfaces. Reuse the current
   application's code; no replacement CPC control panel or fake services.
3. **W3 — actual System menu.** Connect qualified actions and their deferred
   launch/return paths, including Settings and About. Media, icon layout,
   screensavers and return-to-firmware remain explicit dependencies of their
   respective actions. Validate alongside Clock/Calculator and then continue
   with the complete shared Desktop/File Manager.

## Why W1 precedes the window

`apps/settings/main.c` still loads through the native app path and directly
uses configuration/name/palette addresses from the old memory map. Its asset
enumeration and saver dialogs also need native providers that the universal
Clock/Calculator do not use. The CPC runtime deliberately admits only the
qualified application/service profiles; widening those gates before binding
their memory and callbacks would recreate the original port's failures.

W1 therefore does not claim a working Settings window or System menu. It
qualifies the persistence side first, using the existing Settings text-edit
policy and the already-tested CPC filesystem and asset providers.

## W1 implementation

`apps/settings/core/config_keypos.inc` and `config_edit.inc` contain the
existing Settings key lookup and in-place replace/append code. MSX includes
those blocks at their original locations, retaining its original persistence
and live-state handling. Both cooperative and production preemptive Settings
binaries remain byte-identical. The build cache tracks the new includes.

`GBEDIT.MOD` binds the same edit block to CPC-owned storage and the existing
filesystem-context client/backend. The private `cpc_config_update` entry uses
the already-qualified serialized F6 module transaction and captured caller
identity, then reloads only **after the edit module has returned**. It does not
enable the legacy native `GB_RELOAD` slot at 80BA or advertise a universal
configuration capability. The existing private root reload now preserves IX,
interrupt state and the scheduler lock instead of unconditionally enabling IRQs.

The binding performs these checks before publication:

1. Validate the fixed request, then allocate one owned filesystem context.
   Only `/GEOBENCH.CFG` on the qualified boot/M4 drive can be written.
2. Read a nonempty configuration of at most 512 bytes, including an exact-EOF
   probe at capacity. Check native transport errors as well as the shared
   context status: the inherited zero-read ambiguity is not sufficient for
   deciding whether a configuration file is safe to overwrite.
3. Run the actual Settings edit, preserving comments, unknown keys, line
   endings and the existing first-matching-key rule. An unchanged value skips
   the write but still permits reloading the existing configuration.
4. Replace the file through the existing chunked M4 writer, rewind, read back
   and compare every byte, then verify EOF. Release the context on every normal
   exit. Only verified success permits reparse/live asset publication.
5. Use the existing configuration and asset loaders. Unchanged assets cause
   no repaint; a real global appearance change uses the existing invalidation
   path. Application state, ownership and worker scheduling remain shared.

This is a bounded persistence provider, **not another Settings UI**. For W1,
requests accept `FONT=`, `ICONS=`, `CURSOR=`, `TITLEBAR=`, `GADGETS=` and
`BACKDROP=`, with a one-to-eight-character uppercase/digit/`_`/`-`/`~` stem and
an optional matching three-character extension. Paths, drive overrides and
other settings are not admitted yet. Normal asset-loader fallback still
applies to an unavailable selected asset; saving a name does not prove that
the asset exists or loaded successfully.

Missing/empty/oversized or NUL-containing configs are rejected, not silently
created or truncated. The legacy edit block also assumes an existing value
fits its 8-bit length arithmetic, and that an appended key starts on a new
line. CPC guards those preconditions: values longer than 255 bytes and an
append after an unterminated line are rejected before mutation. These checks
do not change MSX behavior; hardening that legacy path remains follow-up work.
Replacing a matching unterminated final value is supported.

### Failure limits

Malformed input/module and pre-write read/bounds failures leave the disk and
live configuration unchanged. Write or verification failure prevents live
publication, **but the existing M4 replace/append contract is not atomic**:
a failed write can leave a partial file, and a failed verification can follow
a completed write. There is no rollback, temporary-file rename or power-loss
guarantee in W1. A verified disk write followed by reload failure is reported
separately; it must not be presented as successful live application.

The private result cells at 1E48–1E4E record phase/status, verified-write flag,
filesystem/transport detail and accepted-call count. UI operation 26 carries
the bounded key in `UI_NAME` and value in `UI_TEXT`; callers use the private
update entry, not a new portable ABI. The input/status convention is not the
complete native Settings filesystem or reload contract.

**Sprint 1 follow-up:** [the shared read-status binding](CPC-RESTART-SPRINT1.md)
now propagates CPC read failures as FSCTX I/O errors. The config editor no
longer needs the transport-cell workaround described for W1 above. Missing
files remain rejected without writes or publication, now with common status 6
instead of a private transport-derived error. Other W1 guarantees and limits
are unchanged.

## Allocations

| Allocation | Used / budget |
| --- | --- |
| Fixed CPC kernel | 15,223 / 16,384 bytes |
| Root component | 5,092 / 8,192 code; 87 / 256 data bytes |
| F6 GBEDIT | 3,661 / 6,144 code; 645 / 768 data bytes |
| Fixed edit status cells | 1E48–1E4E, after the picker handoff |

The editor's 512-byte candidate and 128-byte verification buffer fit within
the existing F6 data allocation. No additional bank, framebuffer scratch or
stack reservation is needed. F7 filesystem/assets and the 27 application
pages including root are unchanged. Native module/link checks enforce code,
data and fixed-state bounds.

## Validation

- All **14 M4 cases** pass: normal save/reload, exact-capacity input, appending,
  duplicate keys, replacement of an unterminated final value, missing/empty/
  oversized files, excessive existing value length, unterminated append,
  capacity exhaustion, and missing/short/oversized editor modules.
- The normal run checks live Calculator preservation and configuration edits
  with Clock seconds/background work active. A fresh emulator boots a copy of
  the saved private image and confirms the persisted WEAVE titlebar. No guest
  RAM is injected. Rejection and no-op cases compare the entire private image
  to verify that no write occurred; successful edits compare exact file bytes.
- Full framebuffer, code, window/owner state, context cleanup and stack guards
  are checked. The persistence scenarios observe at most **128/4/6 bytes** of
  main/IRQ/temporary stack use. Basic native dialog regression passes all
  **23 checkpoints**, including live Clock and reload recovery.
- The existing native file-picker regression passes all **34 checkpoints**
  with the new module dispatch, including Clock suspension/resumption and
  subsequent M4 access; its stack high-water marks remain **147/4/6 bytes**.
- Host tests run the actual shared edit and CPC module with mocked device
  calls, checking all admitted asset keys, request bounds, preserved text,
  capacity limits, no-op, context exhaustion, transport/read/write/readback
  failures and cleanup. Partial-write failure is explicitly exercised.
- Full `make check` passes in an isolated worktree: **237 Python tests**, no
  skips, plus native C, SDK, ABI and distribution checks.
- MSX Settings is byte-identical before/after: cooperative 15,011 bytes,
  SHA-256 `150acb7b5a64558ac523b3a06d2c7e1209d3479a68bc1a9699dd9d4be0755221`;
  production preemptive 15,276 bytes,
  `c08dd22060b83e23bfe77462ba5f522bb817359af526de962ccbd07d64d21387`.
  No fresh openMSX run is claimed for this byte-preserving extraction.

Evidence is under `/tmp/geobench-77w-*`. Tests use **private M4 copies**;
normal MSX media, `QA/CPC/`, user recordings and sibling emulator sources are
untouched. No floppy emulator runs or Albireo/PCW qualification.

## Manual check

The diagnostic M4 image is rebuilt. Run:

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Focus the blue background (arrows move the pointer; Space clicks):

- **W** saves `TITLEBAR=WEAVE` and applies it live.
- **E** saves `TITLEBAR=ORIGINAL` and restores it live.
- Sprint 1 adds **L** (`VIEW=LIST`) and **B** (`VIEW=DEFAULT`) after rebuilding
  diagnostics. These exercise the actual File Manager persistence binding;
  they do not launch a File Manager or change desktop/window appearance.
- Press the same key twice: the second request does not write or repaint.
- Stop and restart the emulator without rebuilding: the saved choice remains.
- F7/F2 open Calculator/Clock. Return focus to the background before W/E and
  check that the application state and background Clock updates survive.

Unlike the earlier read-only picker, these diagnostic keys **write the
diagnostic image's configuration**. They do not touch normal release media.
Rebuilding `make diagnostic-cpc-runtime` restores the staged ORIGINAL defaults.
`make diagnostic-cpc-config-edit-1984` runs the automated save/reload/reboot
scenario on separate copies. Individual cases are available via
`tools/test_cpc_runtime_1984.py --skip-build --config-edit <case>`.

Next after W2-A: sprint 1 of the four-sprint desktop-first plan combines the
dependency audit and required native service/memory bindings. Reuse W1
persistence where required; finish Settings' complete profile separately.
W3 connects qualified System actions
incrementally. Sprint 1 now has complete linked profiles for both applications
and private actual-Desktop/File Manager contracts, including owned browsing and
native load rollback. Sprint 1's combined runtime capacity/recovery and actual
File Manager View/configuration/Clock qualification now pass; see the
[sprint 1 closure](CPC-RESTART-SPRINT1.md#final-combined-qualification--2026-09-08).
Next is sprint 2's regular M4 Desktop delivery, not another service-only
checkpoint. W1 alone does not close the production-adapter gate.
