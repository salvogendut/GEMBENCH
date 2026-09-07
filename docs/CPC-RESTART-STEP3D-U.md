# CPC restart 3D-U — titlebars and gadgets

Issue #77, branch `feature/77-cpc-production-adapters`, 2026-09-07.
Follows [3D-T](CPC-RESTART-STEP3D-T.md). This is a native asset-provider
checkpoint, **not the complete CPC Desktop or a release CPC target**.

## Shared implementation

- The Desktop's actual `cfg_val` and `chrome_load` key/stem selection now live
  in `apps/desktop/core/config_value.inc`, `chrome_select.inc` and
  `chrome_keys.inc`. MSX retains its original calls, storage bindings and
  output bytes. The CPC configuration module binds the same selection to its
  retained 512-byte text and two owned filename outputs. Its read boundary
  additionally stops at EOF/NUL, including an unterminated final value.
- `TITLEBAR_TILE` and `THEMED_GADGETS` are enabled in the composed CPC runtime.
  Isolated earlier plain-chrome fixtures retain their original configuration.
  `kernel/core/window_chrome.asm` still decides furniture, title placement and
  window kinds. Focus, drag, maximize, restore and close policy are unchanged.
- The existing Mode-1 title tile loop is extracted to
  `kernel/core/title_pattern.asm`. Both the existing MSX-packaged payload and
  new CPC-bound payload include it. CPC supplies screen addressing, scratch
  cells and an entry wrapper that clips before excluding the software cursor.
  Gadgets use the already validated icon bitmap blitter, now callable by the
  shared furniture code. Time IRQs progress under the existing WM lock.

No new window manager, theme format, application ABI or capability bits.
Universal Clock and Calculator APP bytes are unchanged. `GB_RELOAD` remains
unavailable: a private root **R** operation is not the complete native reload
contract required by Settings.

## Admission, fallback and reload

Every read uses the existing bounded M4 reader, strict `/GBENCH` 8.3 namespace
and excluded F6 staging. The following files are different kinds of input:

| Input | Accepted | Failure behavior |
| --- | --- | --- |
| `GBTITLE.MOD` | Exactly 384 bytes of this build's CPC-bound native payload | No renderer call; plain light title band and embedded ORIGINAL gadgets |
| `TITLEBAR=<stem>` | Exactly 56-byte repeated 16x14 background, or legacy 106-byte background + gadget pair | Use the ORIGINAL artwork carried by the loaded module |
| `GADGETS=<stem>` | Exactly 50 bytes: 8x10 close + 12x10 maximize | Retain the pair from the accepted legacy TBR, otherwise module fallback |

As on MSX, absent keys select `ORIGINAL`, the first matching key wins and a
filename extension is ignored when forming the stem. Explicit GDT selection
overrides a legacy combined TBR's gadget pair. Empty/unsafe names cannot escape
the system directory. Oversized/trailing/truncated files cannot partially
replace live assets. This is stricter size admission than the legacy MSX
installer's minimum-size checks; valid canonical artwork has the same meaning.

Native modules are trusted platform/build-specific code, **not** universal
APPs or sandboxed/authenticated input. Exact length is a bounds check, not a
signature. Do not copy MSX `GBTITLE.MOD` into the CPC card. TBR/GDT artwork is
portable and is staged unchanged from the repository.

The entire candidate theme is composed in fixed scratch, then compared with
the live 106 bytes before publication. Renderer code and readiness are checked
for changes too. An unchanged reload performs no screen invalidation; a real
theme change uses the existing visual-change invalidation. Ordinary window
damage remains clipped by the shared compositor. Nothing changes the rules
for covered windows or background Clock updates.

## Allocations

| Allocation | Used / budget |
| --- | --- |
| Resident CPC kernel | 14,973 / 16,384 bytes |
| Support / hardware / scheduler | 1,836 / 3,072; 1,130 / 1,536; 1,446 / 1,536 |
| F7 filesystem module, 4400–5E00 | 4,502 / 6,656 bytes |
| F7 title payload, 5E00–6000 | 203 meaningful bytes, 384 loaded / 512 reserved |
| F7 filesystem I/O scratch, 6000–6100 | Unchanged |
| F7 icons, 6100–7F00 | 5,284 / 7,680 bytes for REFINED |
| Fixed theme candidate, 1900–196A | 106 bytes; follows cursor save-under |
| Fixed theme status/scratch and names, 196A–1996 | Dedicated cells, before hardware state at 1A00 |
| F6 GBCFG | 2,815 / 6,144 code bytes; 11 / 256 data bytes |
| F6 GBUI / root component | Unchanged budgets and payload sizes |

The filesystem link and runtime load limit now stop at 5E00; its data budget
is moved below that bound. Neither renderer nor assets borrow filesystem
scratch, application snapshots, stacks, framebuffer or raster gaps.
**27 application pages including root** remain available; F6/F7 stay excluded.
Build assertions reject an undersized/overlapping title allocation.

## Validation

M4-only tests use private copies of `QA/Diagnostics/CPC-runtime/RUNTIME.IMG`.
They steer real keyboard/pointer input and observe snapshots; they never inject
guest RAM. Expected pixels are decoded independently from source artwork.

- All **21 chrome cases** pass: current and legacy themes, independent GDT
  precedence, missing files, malformed lengths, unsafe/empty names, duplicate
  keys and a full 512-byte config ending in an unterminated value.
- Rich default/custom/legacy-fallback/missing-module scenarios check title
  focus, overlap, drag exposure, Calculator digits, close/maximize/restore,
  unchanged reload and filesystem integrity after rendering.
- Ordinary runtime, Clock visibility/occlusion, native dialogs and custom
  bitmap assets are rechecked against themed frames, including memory/stack
  guards and byte-identical loaded code.
- Video-timed pointer regression: idle 50.0 steps/s, focused seconds 49.24,
  background seconds 47.35. Maximum moving gap 11 IRQ ticks, no stationary
  sample spans. Existing thresholds are unchanged. Background IRQ/video ratio
  is about 0.967; the previously documented software-time drift is not solved
  by this asset checkpoint.
- In an isolated worktree, MSX Desktop is byte-identical before/after the
  extraction (15,147 bytes), as are GBTITLE.PAY (334) and MSX GBTITLE.RAW (528).
  No new MSX runtime behavior is introduced; no fresh openMSX run is claimed.
- Full `make check` passes in the isolated worktree: 234 Python tests, no
  skips, plus native C, SDK, ABI and distribution checks. Maximum observed
  main/IRQ/temporary stack use across M4 regressions is 125/4/6 bytes, with
  intact guards. Custom theme screenshots were also visually inspected.

Evidence logs for this run are under `/tmp/geobench-77u-*`; these are local
artifacts, not required source/distribution inputs.

Build identities:

- Private M4 image: `ca2663466d07d27e8255810eaacbee5b1756f94ccc680b14182d30de3fff3ba9`
- CPC CORE.RAW: `8b6effef19c97c7e53b7edf8027a0c16c03184fcecb3bc10bf74df6b2f665f33`
- CPC GBTITLE.MOD: `5857ef577e2269c5667667dd3fe365e3d3a063750d38a04212d222eb9ea3b39a`
- MSX Desktop comparison: `552199b90097c7a6c5ee398152c0f1c0b15ea952f986a7e86d747ddc10e1abe5`
- MSX GBTITLE comparison: `8407fe22ed1d88d9555fd39c55660bd5e60233677de83e04b74ddefdbdba42cc`
- Normal MSX image unchanged: `047a19d38e05f009df8c07a22be90e226a98bc68992fc7474c34015f251ce308`
- 1984 executable unchanged: `00ac601cab80763dcea63e08cf3be642322c87b23864897069a8d21ca3d1228e`

## Manual test

The private M4 image has been rebuilt. Start it with:

```sh
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

The normal card retains `TITLEBAR=ORIGINAL` and `GADGETS=ORIGINAL`. Open
Calculator/Clock with **F7/F2**, focus and drag their titlebars, close via the
left gadget and maximize/restore a supported window via its right gadget.
Arrow keys move the pointer; **Space** clicks. With the background focused,
**R** reloads configuration without flashing unchanged windows.

For a visibly different manual theme, **stop the emulator first**, edit
`QA/Diagnostics/CPC-runtime/CARD/GEOBENCH.CFG` to set `TITLEBAR=WEAVE` and
`GADGETS=IMPROVED`, then copy that edited file into the image:

```sh
distrobox enter my-distrobox -- mcopy -o \
  -i QA/Diagnostics/CPC-runtime/RUNTIME.IMG@@16384 \
  QA/Diagnostics/CPC-runtime/CARD/GEOBENCH.CFG ::/GEOBENCH.CFG
```

Restart with the same command. Rebuilding `make diagnostic-cpc-runtime`
restores the normal ORIGINAL defaults. Never edit an image while mounted.
`make diagnostic-cpc-chrome-1984` builds and runs the automated custom-theme
scenario on a separate copy; `--chrome-case` on
`tools/test_cpc_runtime_1984.py` selects individual cases.

User recordings, `QA/CPC/`, normal MSX media and sibling emulator sources are
untouched. No floppies were used. These tests do not qualify Albireo or PCW.

## Next

**3D-V: native file-picker integration**, using the existing shared dialog and
filesystem policy. Then System/Settings, the complete shared Desktop/File
Manager and remaining application parity. The broader production-adapter gate
and full native reload contract remain open.
