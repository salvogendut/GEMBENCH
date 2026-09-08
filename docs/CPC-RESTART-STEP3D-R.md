# Restart step 3D-R: native configuration and dialog services

Date: 2026-09-07. Issue: [#77](https://github.com/salvogendut/GEMBENCH/issues/77).
Branch: `feature/77-cpc-production-adapters`, following `32232ed` (3D-Q).
Parent: [restart plan](CPC-RESTART-PLAN.md).

This checkpoint binds the existing configuration parser and **basic native
dialog service** to the CPC runtime. It does not enable the full System menu,
Settings application, asset reload, file picker, Desktop or File Manager.
The universal APP format, capability masks and Clock/Calculator bytes are
unchanged. Native modules are target-linked implementation details, not
compile-once APPs.

## Shared code and providers

`kernel/core/data_module.asm` is the existing MSX module-call transaction:
save caller page and load limits, load the module, call it, restore on success
or failure. `kernel/core/ui_module.asm` is the existing modal-depth/result
handling. MSX supplies its original data-page, address, reader and optional
Browser selector. CPC supplies an explicitly reserved bank, bounded M4 reader
and the basic UI module. The extraction leaves MSX machine code unchanged.

The CPC build links the actual `kcfg_mod.c` and `kcfg.c`, including defaults,
parsing, 8.3 filename conversion, ink normalization and the RAM string.
`GB_CONFIG_PROVIDER` supplies its owned input/output addresses; the normal
MSX addresses and parser profile remain unchanged.

Likewise, CPC links the actual `gbui_mod.c`, `gbdlg.c` and `gbprompt.c`.
`GB_UI_PROVIDER` supplies the request block and save-under allocations.
`GBUI_BASIC_ONLY` excludes file/directory pickers and Browser operations whose
providers are not ready; it does not replace them with successful stubs.

| Native UI operation | CPC status |
|---|---|
| 1: popup | Bounded packed labels, selection/cancel, shared save-under renderer. |
| 2: prompt | Shared uppercase name editor, 1–12 characters, accept/cancel. |
| 6: resource-menu popup | Shared dispatch, at most eight labels and disabled-item result handling. Full resource applications are not qualified here. |
| 24: About | Shared renderer and nested OK popup. |
| 25: picture size | Shared two-field editor and result handling. |
| File/directory picker, Browser, alternate module selector | Explicitly unavailable. |

The receiver checks root context and rejects nested/alternate module entry.
It preserves IX, interrupt state, scheduler lock, caller page and drawing clip.
The shared modal flag suppresses app callbacks while their page is swapped
out. IRQ time/input continues, but workers remain parked until the modal call
returns. Results cross the bank boundary through the owned request block.

The bounded UI profile rejects unsupported operations, unterminated/overlong
labels, unsafe geometry and excessive prompt lengths before polling/drawing.
Prompt, size and About use a separate outer save-under buffer; About's nested
popup cannot overwrite it. Closing restores only the dialog's rectangle, not
the desktop or entire underlying windows. The normal MSX profile is unchanged.

## Allocation and loading contract

F7 remains the font/filesystem/I/O bank. **F6 is now reserved for native system
modules**, outside the application allocator. All 29 physical mappings are
still checked during 512-KiB admission. The allocator receives 27 pages rather
than 28; root C0 consumes one, leaving 26 before ordinary APP launch. Historical
foundation fixtures retain their original page budget. No snapshot, stack or
framebuffer limit is relaxed.

All end addresses are exclusive:

| Allocation | Location | Budget |
|---|---|---:|
| Retained configuration text | Fixed `1000..1200` | 512 bytes |
| Native UI request, result and packed text | Fixed `1700..1800` | 256 bytes; labels start at `1718` |
| Parsed configuration outputs | Fixed `1800..1840` | 64 bytes |
| Native status/counters/read offset | Fixed `1840..1850` | 16 bytes |
| Config **or** UI executable | F6 `4000..5800` | 6,144 bytes |
| Module CRT data | F6 `5800..5900` | 256 bytes |
| Outer dialog save-under | F6 `5900..6C00` | 4,864 bytes |
| Popup save-under | F6 `6C00..7F00` | 4,864 bytes |
| Excluded context-snapshot area | F6 `7F00..8000` | 256 bytes |

The audited configuration text range can retain the old address; its length
and normalized outputs use the new explicit provider. UI requests begin after
the existing `1500..1700` filesystem transfer buffer and end before configuration
outputs. F7 M4 scratch at `6000..6100` is physically separate from F6 dialog
pixels at the same CPU addresses. The 3D-Q root code/data/popup allocations in
C0 remain separate from both.

`/GEOBENCH.CFG` is read from M4 in bounded 128-byte transactions, including an
EOF probe at exactly 512 bytes. Missing/failed/oversized text supplies length
zero to the shared default-setting parser. The status preserves the distinction
between successful input, oversize and transport error. The actual file length
and text are retained for future Desktop consumers.

`/GBENCH/GBCFG.MOD` and `/GBENCH/GBUI.MOD` are padded to 6,144 bytes. The shared
transaction invokes a module only after the M4 read succeeds and the exact
length matches. Its read envelope is the owned F6 `4000..7F00` aperture: a bad
length may overwrite uninitialized module data/save-under storage, but never
an application page, fixed state or snapshot. CRT initialization runs on every
successful call. These are trusted native binaries, not a security sandbox.

A missing or malformed parser executable is an error, not the same as a missing
configuration file: boot stops before launching APPs. Dialog load failures
return deterministic cancellation without entering a modal loop. Configuration
results are staged only: this checkpoint **does not apply INKS or load selected
fonts/icons/cursors/backdrops**. That requires the next asset/theme integration.

| Linked section | Used / budget, bytes |
|---|---:|
| Fixed high kernel | 12,111 / 16,384 |
| Low support | 1,832 / 3,072 |
| Hardware leaves | 1,130 / 1,536 |
| Scheduler | 1,446 / 1,536 |
| F7 filesystem module | 4,502 / 7,168 |
| C0 root component | 4,092 / 8,192; data 87 / 256 |
| F6 configuration module | 2,335 / 6,144; data 0 / 256 |
| F6 basic UI module | 5,596 / 6,144; data 4 / 256 |

The dialog scenario observes main/IRQ/temporary stack use of 127/4/6 bytes,
with the existing guard bytes intact. Link/assembly assertions reject module
code/data and nested save-under overlap. Parsed frame-pen preference is also
staged; the qualified runtime's current chrome configuration is unchanged.

## Validation

- The native M4 scenario checks 23 exact-frame checkpoints: boot configuration,
  popup selection/hover, modal worker parking, prompt editing/accept/cancel,
  two-field size editing, About/nested popup, restoration over live Clock and
  Calculator windows, config reload and subsequent M4/Calculator use.
- Five configuration fixtures cover absent, empty, exact-capacity, oversized
  and custom text at both boot and reload. They compare retained bytes,
  normalized names/inks/drive/defaults and explicit status values.
- Three UI-module fixtures cover missing, truncated and oversized binaries,
  cancellation and subsequent Clock launch. Parser-module rejection is checked
  separately from the configuration-text fallback. The final image passes all
  six parser/root-module rejection cases, with no APP launch, intact fixed code
  and stack guards, and a stable halted state.
- The observer checks immutable root/kernel/filesystem/font/module bytes,
  page ownership, stack guards and full composition. Expected pixels are
  independently constructed; no guest memory is injected. Held input is
  acknowledged through the keyboard state. A modal can start between Clock's
  separate hand/digit updates, so the oracle models both completed caches
  independently and requires normal updates to finish after the modal returns.
- Host tests execute the actual basic UI dispatcher with mocked device
  boundaries, including cancellation, save-under pairing, malformed input and
  unsupported operations. A separate sensitivity check ensures the Clock
  oracle distinguishes its hand and digit caches.
- MSX extraction comparisons are byte-identical for cooperative Screen 6,
  preemptive Screen 6/7, `GBCFG` and normal `GBUI`. The UI comparison pins the
  same build/version identity on both sides (6,064 bytes); GBCFG is 2,373 bytes.
  Fresh private-media openMSX Desk/Clock regressions pass in both screen modes,
  exercising the native popup path and shared module gate.
- Existing ordinary-window (11), Desk (26), Clock (22) and portable-filesystem
  (46) regressions pass with the reserved native-module bank. The final rebuild
  repeats the complete 23-checkpoint native sequence and six boot rejections.
- Full `make check` passes: **218 Python tests without skips**, plus native C,
  SDK/ABI and distribution checks, in the isolated reference worktree. Log:
  `/tmp/geobench-77r-check-final.log`.

Final native sequence: `/tmp/geobench-77r-native-final-build.log`;
boot rejection: `/tmp/geobench-77r-boot-faults-final.log`;
configuration/UI failure cases: `/tmp/geobench-77r-config-cases.log` and
`/tmp/geobench-77r-native-faults.log`;
MSX regressions: `/tmp/geobench-77r-openmsx{6,7}.log`.

Final payload SHA256 values (native build identity `32232ed3278ed`):

| Payload | SHA256 |
|---|---|
| CPC CORE.RAW | `dec0af19be50e1c1b1e344630b1784d18a6f7c8ad44feb31705cf2bd705bcec9` |
| CPC GBCFG.MOD | `6721e0074e342a1012048cf349d76300fcc79bb6a5192c5e6920fb1bec2ca6bb` |
| CPC GBUI.MOD | `16a9e6cb090d6d69ea8c4ac6f550d6d3ffc9f6b2d398c5ccc33eba410c4ada0c` |
| Root component | `9d4e353e39329c7720a9d63d8e0a25f76e2a1c9a6f3d73555c01a8ae7c5928f8` |

1984 remains unchanged at
`00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`.

Evidence logs use `/tmp/geobench-77r-*`; tests print their private M4 artifact
directories. Full-suite checks use `/tmp/geobench-77r-reference.BC91xV` so
distribution fixtures cannot alter working release media. No emulator edits,
floppy runtime tests, PCW enablement or Albireo qualification. User recordings
and `QA/CPC/` remain untouched.

## Manual test

Launch the rebuilt private M4 image:

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Open Clock/Calculator through Desk (or F2/F7), then click the empty background
to give root focus. The following **private diagnostic keys** invoke the real
native services; they are not a replacement System menu:

- **U**: popup; select with arrows/Space or cancel with Escape.
- **P**: name prompt; type text, use Backspace, Enter to accept or Escape to cancel.
- **N**: picture-size dialog; type width, Tab to height, Enter to accept.
- **I**: About; dismiss its OK popup or press Escape.
- **R**: reread and parse the M4 configuration (no theme/asset application yet).

Place a dialog over the other windows and dismiss it: only its covered pixels
should be restored, and Clock should resume. Calculator's entered value should
survive. The pointer remains the keyboard/joystick test adapter.

Automated build/test:

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-native-1984
```

Additional private-image cases use `tools/test_cpc_runtime_1984.py --skip-build`
with `--config-case missing|empty|exact|oversized|custom`,
`--native-fault missing|short|oversized`, or
`--root-fault cfg-missing|cfg-short|cfg-oversized` (choose one value, not the
literal pipe-separated list). `make diagnostic-cpc-runtime` only rebuilds.

## Next

The first bounded asset step is now [3D-S](CPC-RESTART-STEP3D-S.md): configured
6x8 fonts, palette/border and shared frame contrast, with no-op reload detection.
The remaining asset families below are still required.

Bind asset/theme loading and application, then connect the full shared Desktop
and File Manager to the qualified M4 providers. File pickers, Settings,
screensavers, general UI clients and the remaining applications need their own
integration tests and budgets. Issue #77 remains open; this partial native UI
profile does not close the production-adapter or application-parity gates.
