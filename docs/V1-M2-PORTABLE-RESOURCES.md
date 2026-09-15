# v1.0 milestone 2 — portable resources and forms

Started 2026-09-14 in issue
[#88](https://github.com/salvogendut/GEMBENCH/issues/88), branch
`feature/88-portable-resources-forms`, from main `b190ac4`.

The finish line is one byte-identical `GBRDEMO.APP` and one byte-identical
`FORMREF.APP` in the MSX2 and CPC distributions. Both must exercise their real
resource/form behavior and cleanly reclaim every owned page and secondary-code
record. This is not permission to migrate Settings/File Manager or advertise an
unimplemented package-resource capability.

## Four sprints

1. **Baseline and contract.** Inventory the native applications, freeze the
   common data/service boundary and record private acceptance fixtures and
   budgets. Normal distribution delivery remains unchanged.
2. **GBRDEMO vertical slice.** Make the existing bounded GBR1 reader/object
   runtime compile in the universal profile, load the real external
   `HELLO.GBR` through the portable filesystem, and qualify drawing, hit/state,
   clipping, malformed resources, lifecycle and cleanup on both targets.
3. **FormRef vertical slice.** Embed the same generated `FORMREF.GBR` bytes in
   the common primary image and migrate the complete field, checkbox, radio,
   disabled, default/cancel, pointer and keyboard-focus workflow.
4. **Secondary-code closure and delivery.** Convert FormRef's secondary work to
   the already-sealed portable computation contract, qualify all call/ownership
   rejection and restoration cases, then stage identical APPs only after the
   private cross-target gate passes.

## Baseline inventory

| Item | Current state | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| MSX `GBRDEMO.RAW` | Native external-resource demo | 11214 | `482c32bceb4a336f7058b4a4a22086179123418fb80fb0047be2215f37f28df2` |
| `HELLO.GBR` | Frozen external GBR1 fixture | 111 | `49b42e9268ad4f4208d70f591f9d3f6b6ad7bee2dcf6f008a773ece968febf12` |
| MSX `FORMREF.RAW` | Native GBAP v3, MSX-only | 16026 | `c6650c86348b97db50102d839b3d8b5f08a16bd6fb41b045b9a2c02b9d838e46` |
| `FORMREF.GBR` | Embedded generated GBR1 tree | 231 | `a5f473f4665e5f119bf809819e8e191d509f41bda3cd0111320e54f3750bdfc8` |
| `FORMREF.SEC` | Native GBS3 MSX drawing bank | 227 | `5d612267def78d76a49d1df41fc9e53eda123512e2d1f0a41ab57507c0a5fd6b` |

Current source is not a shared build:

- GBRDEMO calls the native implicit-file `gb_fs_load` and compiles visible
  geometry around the MSX target.
- FormRef selects two different implementations with `GB_MSX2`. Its manifest
  is `target-z80`, names only MSX2 and requires a native GBS3 secondary.
- The GBR object and VDI libraries use compile-time `GB_XPIX`, `GB_COLS` and
  `GB_LINES`; a universal build deliberately removes those constants.
- The universal builder has no resource/form link profile yet.
- GBAP v4 describes resource segments, but production receivers deliberately
  do not advertise `package-resources`. The existing portable secondary service
  accepts one sealed common GBS4 computation bank and does not allow secondary
  code to call target drawing entries.

These are migration inputs, not defects to hide with target defines or separate
APPs.

## Contract decisions

### Keep GBR1 frozen

No GBR2 fork is required. The canonical GBR1 bytes, state bits, object types,
tree linkage and generated identifiers remain unchanged. Mutable state and text
or raster bindings remain caller-owned. The existing reader must reject a bad
magic/checksum, overlapping or truncated sections, invalid links/types/text and
unsupported visible objects before partial publication or drawing.

### Use runtime geometry in app-linked code

The universal resource/form/VDI runtime will be linked into each APP. Under
`GB_UNIVERSAL` it obtains columns, lines and pixel width from the v6 sysinfo
accessors and uses only the four semantic pens. Native builds retain their
existing compile-time profile. This is an internal source-profile change, not a
new kernel jump-table contract.

### Do not invent package-resource support for these small fixtures

GBRDEMO keeps its actual external-document behavior, but reads the selected
`HELLO.GBR` through the already-qualified portable filesystem into its bounded
primary buffer. FormRef's 231 immutable bytes are generated once and embedded
in the common primary image. Therefore neither application requires a new v4
resource segment or `package-resources` capability in this milestone. Typed
package resources remain gated for a later real consumer and may not be
advertised as a shortcut.

### Make FormRef secondary work computation-only

The native secondary currently draws through fixed resident addresses. The
portable FormRef will instead give a sealed common GBS4 bank a bounded copied
record and receive a bounded result record; primary code performs all drawing
through universal semantic calls. No code pointer, app pointer, bank number or
target entry crosses the boundary. The existing owner/generation/range/root
guards and exact map/SP/IFF restoration remain authoritative.

## Acceptance matrix

| Surface | MSX2 | CPC |
| --- | --- | --- |
| GBRDEMO | Screen 6 and 7 in openMSX and 1983; external root resource, malformed variants, click/state, move/overlap/close | 1984 with disposable M4 media; same resource bytes and workflows |
| FormRef | Screen 6 and 7; text editing, pointer and forward/reverse keyboard traversal, checkbox/radio/disabled/default/cancel | 1984/M4; same object identities, state transitions and geometry adjusted only by runtime limits |
| Secondary | Valid copied computation plus stale/foreign/nested/worker/teardown/entry/length rejection; exact cleanup/restoration | The same sealed APP/secondary bytes and rejection matrix through the CPC provider |
| Delivery | Normal-image launch/close and exact APP hashes after private acceptance | Normal M4 image only; no floppy tests |

Every emulator driver must observe published state or exported read-only
diagnostics. Guest RAM patches are not acceptance. A smaller CPC-only form,
native fallback hidden behind the universal filename, or host-only resource
test cannot close the milestone.

## Initial baseline evidence

The following pre-migration checks pass on main `b190ac4`:

- 17 GBR compiler tests;
- the complete GBR reader, object, form, graphics and menu host suites,
  including corrupt-resource and interaction semantics;
- Z80 compilation of reader/accessor/menu/object/graphics/form components;
- GBVDI core/base/raster/text contract and size checks;
- visible-region contract and Z80 build;
- 13 owner-page, data-page and sealed-secondary instruction suites, including
  1058 real Z80 bind/call/reclaim operations and 113 data-page calls.

The first code gate is now precise: add a universal resource runtime build
profile and make GBRDEMO compile without target defines, while preserving its
native implementation and normal media until its private two-target acceptance
passes.

## Sprint 2 checkpoint A — compile-once GBRDEMO

The first code gate now passes on this branch:

- `UNIVERSAL_GBR_OBJECTS=1` makes the universal builder link the bounded GBR1
  reader, object runtime and button-only widgets, and requires runtime geometry
  plus portable drawing. It deliberately does not claim the target-native
  `gbr` capability because all GBR policy is linked inside the common APP;
- the object runtime obtains pixel width and line count through v6 runtime
  geometry in a universal build, while its native source profile remains
  byte-identical;
- `apps/ugbrdemo` adopts File Manager's exact launch context, reads at most 512
  bytes through the portable filesystem, rejects an oversized or failed read,
  closes the context, validates `HELLO.GBR`, and only then publishes its managed
  window;
- move is kernel-owned, click/state changes publish bounded content damage, and
  failed/direct launch displays an inert error surface rather than retaining a
  filesystem context;
- the private APP is **13069 bytes**, SHA-256
  `4ec6f034ed396c51fcf5d573c548acfd7df53f077e9f14a718a7cd8cc762b4ff`.
  Code ends at `0x730D`; application state ends at `0x7D9C`, below the guarded
  `0x7F00` limit.

`make geobench-v1-m2-gbrdemo-check` builds the APP twice, proves byte identity,
checks its v4 identity/capabilities and reruns the universal source/assembly/map
audit. The existing universal SDK test, GBR compiler/reader/object suites and
the exact native MSX GBRDEMO rebuild all pass; the native rebuild retains SHA
`482c32bceb4a336f7058b4a4a22086179123418fb80fb0047be2215f37f28df2`.

This is build-level acceptance only. Neither normal image contains the new APP.
The next checkpoint is private receiver staging and the real MSX Screen 6/7 and
CPC/M4 external-resource workflow, including malformed resources and cleanup.

## Sprint 2 checkpoint B — private cross-target receiver qualification

The identical 13069-byte `GBRDEMO.APP` now passes its private receiver gate on
both targets. It is still not installed as the normal GBRDEMO delivery.

- File Manager prepares the selected `.GBR` context and opens `GBRDEMO.APP`
  through the shared launch transaction on MSX2 and CPC. The receiver adopts
  that owner-bound context, reads and closes it, and never relies on a native
  directory pointer or implicit current-file state.
- The shared launch path now clears all 11 bytes of its transient launch-name
  scratch after the synchronous registration/admission attempt. Success,
  rejection and rollback retain neither the argument nor a selected/bound
  pending record.
- The private CPC M4 profile passes four real 1984 runs: canonical, checksum
  corruption, truncation and 513-byte oversize. Exact independent framebuffer
  checks cover open, selected button, drag, focus away/return, close and clean
  Desktop. Invalid resources publish the bounded error surface and remain
  inert. Main-stack high water is 242/256 bytes in the canonical case and at
  most 205 bytes in the invalid cases; IRQ high water is four bytes.
- Disposable MSX images cover the same four fixtures in both Screen 6 and
  Screen 7. All eight openMSX runs pass real File Manager input, package
  admission, resource acceptance/rejection, button state and exact close/
  transaction cleanup. The larger package's real CRC pass requires the test to
  wait after the deliberate second click; repeatedly injecting clicks while
  admission is synchronous is explicitly avoided.
- The same eight cases independently pass on 1983 with real keyboard/joystick
  pointer input. Each run performs 23 assertions: exact APP bytes in the mapped
  page, canonical outlined/selected state or invalid-resource inertness,
  owner/context cleanup, drag/overlap state preservation, page reclamation and
  scheduler guards. Each source image remains byte-identical and a final PPM is
  retained by the private driver.

The canonical resource remains exactly 111 bytes with SHA-256
`49b42e9268ad4f4208d70f591f9d3f6b6ad7bee2dcf6f008a773ece968febf12`;
the APP remains SHA-256
`4ec6f034ed396c51fcf5d573c548acfd7df53f077e9f14a718a7cd8cc762b4ff`.
The native MSX fallback remains exactly 11214 bytes with SHA-256
`482c32bceb4a336f7058b4a4a22086179123418fb80fb0047be2215f37f28df2`.
Normal CPC media and the normal MSX GBRDEMO application remain unchanged by
the private staging tools; CPC qualification uses M4 only, never a floppy.

Reproduce the build and private target gates with:

```sh
make geobench-v1-m2-gbrdemo-check
python3 tools/build_cpc_runtime.py --gbrdemo
python3 tools/test_cpc_runtime_1984.py --skip-build \
  --private-media build/v1-m2/gbrdemo-cpc --gbrdemo-case good
python3 tools/prepare_gbrdemo_msx.py --output NEW_EMPTY_DIRECTORY
GEMBENCH_GBR_MSX_STAGE=NEW_EMPTY_DIRECTORY \
  bash tools/test_universal_gbrdemo_openmsx.sh
bash tools/build_msx_stability_1983.sh NEW_EMPTY_DIRECTORY/1983-bridge
python3 tools/test_universal_gbrdemo_1983.py --mode 6 --case good \
  --bridge NEW_EMPTY_DIRECTORY/1983-bridge \
  --omega ../1983/ROMS/rainbios_omega.rom \
  --sunrise ../1983/ROMS/Nextor-2.1.1.SunriseIDE.ROM \
  --image NEW_EMPTY_DIRECTORY/mode6-good/filesystem.img \
  --worktree . --output NEW_EMPTY_DIRECTORY/evidence-1983-mode6-good
```

Repeat the CPC case for `checksum`, `truncated` and `oversized`; repeat the 1983
command for all four fixture names and both modes. The private preparation and
1983 drivers refuse existing evidence paths by design.

## Sprint 2 checkpoint C — normal MSX/CPC delivery

The qualified universal application and its canonical external resource are
now part of both normal distributions. This completes the GBRDEMO vertical
slice without removing the native MSX build used as a regression oracle.

- `make geobench-msx` stages `build/universal/GBRDEMO.APP` as
  `QA/MSX/CARD/GBENCH/GBRDEMO.APP`, stages `HELLO.GBR` at the card root and
  packs both into `QA/MSX/GBMSX.IMG` and the normal `GEOBENCH.DSK` floppy.
- `make cpc` stages the same two byte-identical files in the normal M4 card and
  `QA/CPC-Desktop/GEOBENCH.IMG`. Its delivery manifest advances to
  `cpc-desktop-m4-v5` and rejects a missing, substituted or mismatched APP or
  resource.
- `tools/test_gbrdemo_delivery.py` checks the host staging trees, MSX hard-disk
  and floppy images, CPC M4 image, universal package identity and CPC delivery
  manifest. The APP is
  13069 bytes with SHA-256
  `4ec6f034ed396c51fcf5d573c548acfd7df53f077e9f14a718a7cd8cc762b4ff`;
  the resource is 111 bytes with SHA-256
  `49b42e9268ad4f4208d70f591f9d3f6b6ad7bee2dcf6f008a773ece968febf12`.
- The canonical CPC image passes the real 1984/M4 open, button-state, drag,
  focus-away/return, close and cleanup workflow with 242/256 bytes maximum
  main-stack use and four IRQ-stack bytes. The canonical MSX Screen 7 image
  passes the same File Manager association and lifecycle in openMSX and 1983;
  the 1983 run performs 23 checks and leaves the source image unchanged.

Reproduce the normal-media gates with:

```sh
make geobench-v1-m2-gbrdemo-delivery-check
make geobench-v1-m2-gbrdemo-delivery-cpc-1984
make geobench-v1-m2-gbrdemo-delivery-openmsx
```

Sprint 2 is complete. Sprint 3's compile-once FormRef implementation is the
next ordered milestone work.

## Sprint 3 checkpoint A — compile-once primary FormRef

The first FormRef build gate now produces a deterministic primary-only
universal candidate while leaving both normal distributions unchanged:

- `apps/uformref` contains no target define or backend branch. It embeds the
  exact compiler-generated 231-byte `FORMREF.GBR`, keeps text/focus/object
  state in its primary page, and drives the complete field, checkbox, radio,
  Save/Cancel, pointer and forward/reverse keyboard workflow through the shared
  GBR form engine. The APP accepts the portable back-tab code; translating an
  actual Shift-Tab chord on both targets remains part of runtime acceptance.
- The universal builder now has explicit form and embedded-resource profiles.
  The embedded profile links only the already-validated GBR accessor rather
  than paying for an external-file parser that this application cannot use.
- The self-polling universal modal helper contains no target address. It owns
  its synchronous loop locally and restores the compositor once on exit;
  native applications retain their existing low-RAM modal implementation.
- The candidate is **15640 bytes**, SHA-256
  `00658270a1ea5456e2c68f31f092ea25f5038123575a83ad857a40f571885ccf`.
  Code ends at `0x7D18`, eight bytes below DATA at `0x7D20`; application state
  ends at `0x7DB8`, leaving 328 bytes before the guarded `0x7F00` task limit.
- The native reference still rebuilds to exactly 16026 bytes with SHA-256
  `c6650c86348b97db50102d839b3d8b5f08a16bd6fb41b045b9a2c02b9d838e46`;
  its 231-byte GBR and 227-byte GBS3 hashes also remain frozen. `make formref`
  now delegates to that complete reference recipe instead of its stale,
  over-budget partial link.

Reproduce this checkpoint with:

```sh
make geobench-v1-m2-formref-check
make formref
bash tests/run_gbr_reader_tests.sh
```

This checkpoint proves source/resource identity, portability auditing, layout
and deterministic packaging. It does not stage the candidate or claim runtime
acceptance. Next, exercise it on private MSX Screen 6/7 and CPC M4 media before
the Sprint 4 GBS4 secondary conversion.

## Sprint 3 checkpoint B — private cross-target runtime qualification

The same 15640-byte primary-only `FORMREF.APP` now passes the complete private
form workflow on MSX Screen 6, MSX Screen 7 and CPC M4. Normal distributions
continue to deliver native FormRef; the universal candidate is not staged.

- The MSX input adapter translates a real Shift-Tab matrix chord to the
  portable `GBR_KEY_BACKTAB` value. The CPC keyboard table supplies the same
  value for shifted Tab; neither application code nor the resource contains a
  target branch.
- The private MSX preparation copies the normal hard-disk image, changes only
  its Screen mode/configuration and stages the exact APP as a short root alias.
  The 1983 driver opens it through Desktop and File Manager and uses real
  keyboard-matrix and joystick input. Screen 6 and 7 each pass 33 assertions:
  exact mapped APP bytes, embedded-resource publication, field editing,
  forward/reverse focus traversal, checkbox/radio semantics, Save/Cancel,
  pointer hit testing, managed movement and exact page/window cleanup. The
  runs complete in 4485 and 4555 frames respectively and leave both source
  images byte-identical.
- Independent openMSX runs on both private Screen modes confirm the real
  Desktop/File Manager launch, embedded-resource state, forward keyboard
  traversal, modal cancellation and FormRef window teardown. Their source
  images also remain byte-identical. Reverse traversal remains covered by the
  deterministic 1983 matrix chord and CPC keyboard table/runtime workflow.
- The private CPC profile stages the same APP on a disposable M4 image. Its
  native File Manager receives a profile-only allowlist entry for the short
  visible alias; the normal-media qualified-application policy does not
  change. The 1984 driver passes 21 lifecycle/framebuffer checkpoints through
  the same interactions, then returns to one Desktop window, zero filesystem
  contexts and the original free-page count. Maximum observed stack use is
  231 main, four IRQ and zero temporary bytes.
- Every checkpoint verifies the canonical 231-byte resource with SHA-256
  `a5f473f4665e5f119bf809819e8e191d509f41bda3cd0111320e54f3750bdfc8`
  and the byte-identical APP with SHA-256
  `00658270a1ea5456e2c68f31f092ea25f5038123575a83ad857a40f571885ccf`.

Reproduce the target gates with:

```sh
make geobench-v1-m2-formref-msx-media
bash tools/test_universal_formref_openmsx.sh
bash tools/build_msx_stability_1983.sh build/v1-m2/formref-msx/1983-bridge
python3 tools/test_universal_formref_1983.py --mode 6 \
  --bridge build/v1-m2/formref-msx/1983-bridge \
  --omega ../1983/ROMS/rainbios_omega.rom \
  --sunrise ../1983/ROMS/Nextor-2.1.1.SunriseIDE.ROM \
  --image build/v1-m2/formref-msx/mode6/filesystem.img \
  --worktree . --output NEW_EMPTY_EVIDENCE_DIRECTORY
make geobench-v1-m2-formref-cpc
```

Repeat the 1983 command with `--mode 7` and the mode-7 image. This closes the
primary FormRef vertical slice. Sprint 4 remains responsible for converting
the frozen native secondary behavior to the sealed, computation-only GBS4
contract and for normal delivery; this checkpoint does not claim either.
