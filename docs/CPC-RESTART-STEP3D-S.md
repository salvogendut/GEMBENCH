# CPC restart 3D-S — configured font and palette

Issue **#77**, branch `feature/77-cpc-production-adapters`, 2026-09-07.
Follows [3D-R](CPC-RESTART-STEP3D-R.md). This is the first bounded asset/theme
checkpoint, **not completion of the asset providers or the CPC Desktop gate**.

The later [Clock/cursor responsiveness follow-up](CPC-CLOCK-RESPONSIVENESS.md)
supersedes the Clock APP identity and CPC kernel budgets recorded below; these
remain the original font/palette checkpoint's evidence.

## What is connected

- The MSX kernel's font selection/default-file fallback is extracted into
  `kernel/core/font_asset.asm`, with target bank/read/publication boundaries.
  The original MSX path is byte-identical after extraction.
- The private CPC runtime reads the configured `FONT=<name>` from
  `/GBENCH/<name>.FNT` on M4. Its renderer is the already-qualified CPC text
  backend; there is no new Desktop or application drawing implementation.
- `INKS=` now sets all four Mode-1 pens and the hardware border. The config
  format remains the canonical CPC firmware colour numbers used by MSX too.
  Only the final Gate Array translation/writes are CPC-specific.
- Window borders use the existing shared parser's contrast choice: Edge if
  distinct from Paper, otherwise Text, otherwise Accent. The previous private
  runtime's hard-coded white frame is gone.
- Root diagnostic **R** rereads configuration and applies this subset. A font
  pixel or frame-pen change requests a shared full repaint; an unchanged reload
  requests none. Palette RGB changes alone need no framebuffer repaint.
- Clipped root repairs preserve the bar's full-surface refresh cache. Testing
  found that a partial exposure could otherwise cache a newly focused menu
  without painting its title, leaving the old title indefinitely. The CPC
  wrapper now restores that cache after the shared renderer repairs a clipped
  area; the ordinary bar tick can then publish the complete new menu/time.
  This does not change the shared renderer or the MSX code path.

The default image keeps the GEOBENCH blue/white/black/red palette. Its normal
`DEFAULT.FNT` is now staged on the private card and genuinely loaded from M4.
The embedded font is emergency recovery, not the ordinary source.

## Font admission and fallback

This checkpoint admits **6x8, 100-glyph** GBFN v1 fonts covering codes 32–131,
with one byte per row and an exact 816-byte file. Different glyph artwork is
supported; different cell metrics/coverage are deliberately rejected because
the current shared Desktop/dialog/application layouts assume these metrics.
Reserved header bytes remain uninterpreted.

The sequence is configured file → `DEFAULT.FNT` → embedded default. Missing,
empty, truncated, extended, malformed or incompatible files cannot replace the
live font with partial data. The same bounded `/GBENCH` filename conversion as
the APP reader rejects path escapes. Status is observable in fixed state:

| `CPC_FONT_STATUS` | Published source |
|---|---|
| 0 | Configured file, including a configured `DEFAULT` |
| 1 | Default file after the configured candidate failed |
| 2 | Embedded recovery after both reads failed admission |

The existing bounded reader stages candidates in excluded **F6**. Its I/O cap
is `0x3F00`, with an EOF probe to reject larger files; this does **not** enlarge
the font allocation. Only a validated 816-byte candidate is copied, in
128-byte chunks through fixed staging, into **F7:4000–4330**. The following
filesystem module begins at **F7:4400**. The remainder of the font reservation,
filesystem code, I/O scratch, application pages and snapshot boundaries are not
borrowed for asset data.

F6 is reusable after the configuration parser returns and before a native
dialog is loaded. No persistent parser/UI executable is promised there. Calls
are serialized in root context, preserving bank, IX, scheduler lock and IFF;
workers cannot see a partially replaced font. No extra application page is
reserved: the pool remains 27 pages including root.

## Budget

| Region | Used / budget |
|---|---|
| Fixed resident kernel | 12,514 / 16,384 bytes |
| Support | 1,832 / 3,072 bytes |
| Hardware | 1,130 / 1,536 bytes |
| Scheduler | 1,446 / 1,536 bytes |
| F7 filesystem module | 4,502 / 7,168 bytes |
| F7 font | 816 / 1,024 bytes |
| Root module | 4,148 / 8,192 bytes; data 87 / 256 |
| F6 GBCFG / GBUI | 2,335 / 5,596 bytes, each within 6,144 |
| New fixed visual state | `1850–185D`, exclusive end |

The map has assembly assertions against native state, filesystem code and font
capacity. The build tests deliberately reject an overlapping font allocation.

## Validation

The dedicated M4 suite uses **19 private-image cases**: ordinary and custom
artwork, missing/empty/short/extended/oversized files (including the reader's
own size boundary), invalid magic/version/width/height/coverage, unsafe names,
missing/malformed defaults, alternate default artwork, Accent frame fallback,
and a palette with no contrasting pen. No test writes guest RAM.

For every case, the observer checks exact font bytes, cached geometry, source
status, hardware palette registers, frame selection, full expected screen
pixels, fixed code/module integrity, window ownership and stack guards. An
unchanged **R** must complete without extra drawing transactions. Ordinary and
custom artwork also run Calculator (retaining 72), a real native popup with
save-under restoration, and filesystem access after reload.

The palette unit test checks all 27 mappings against independently derived
RGB values; the pixel oracle has font-artwork and frame-pen sensitivity tests.
A native C regression executes the actual shared bar refresh/render fragments
and CPC damage wrapper: a clipped Desk-to-Edit transition must not falsely
advance the full-bar cache, and an unchanged later tick must not redraw.
Recorded results:

- **Full `make check`: PASS**, 223 Python tests with no skips, plus native C,
  SDK/ABI and distribution checks, in `/tmp/geobench-77s-reference`.
  Log: `/tmp/geobench-77s-check-fixed.log`.
- **19 font/palette image cases: PASS**. Logs:
  `/tmp/geobench-77s-assets-custom.log` and `/tmp/geobench-77s-asset-cases.log`.
  These admission cases preceded the final root-cache correction; font reader,
  validation and publication code did not change afterwards.
- **Final rebuilt image: PASS** for ordinary windows (11 checkpoints), custom
  assets with Calculator/dialogs/reload (10), native config/UI with live Clock
  (23), and Desk lifecycle/capacity (26). Logs:
  `/tmp/geobench-77s-fixed-regressions.log` and `/tmp/geobench-77s-desk-fixed.log`.
  Maximum observed main/IRQ/temporary stack use was **127/4/6 bytes**, with
  intact guards.
- Full Clock worker/occlusion/pointer checks (22) and portable filesystem
  checks (46) passed with the same font/palette implementation before the
  final cache correction. Logs: `/tmp/geobench-77s-regressions.log` and
  `/tmp/geobench-77s-fs.log`. The final Desk run also checks background Clock
  and M4 access after close/relaunch and capacity failure.
- **openMSX Screen 6 and Screen 7: PASS** on the byte-identical MSX reference,
  including 46 timer-source fragments and 23 rim repairs in each mode. Logs:
  `/tmp/geobench-77s-openmsx6-retry.log`, `/tmp/geobench-77s-openmsx7.log`.
  An initial Screen-6 run missed the Desk Calculator selection; the independent
  rerun passed without kernel, image, emulator or harness changes.

The Desk observer now handles a popup parking Clock between its completed hand
and digit passes, as the native UI observer already did. A regression covers
that shared observer predicate. Settling also tracks the menu and two bar-entry
turns. These changes did **not** hide the stale-bar defect: the missing pixels
persisted after resuming its saved snapshot, and the stricter rerun reproduced
them before the actual CPC cache wrapper was fixed. Exact-pixel assertions stay
enabled throughout.

MSX cooperative Screen 6 (13,929 bytes), preemptive Screen 6 (13,956 bytes),
and preemptive Screen 7 (15,534 bytes) compare byte-for-byte with the 3D-R
reference kernels. Clock and Calculator APPs are unchanged:

- `CLOCK.APP`: `73a3786bb08f75162018cfeeaaad2add5eb4f240bd72725441d8a6681b22a90c`
- `CALC.APP`: `5e1989d171052d751386b355b1204382c88bba69f4edc632ea65fafb8b7da8f5`
- CPC `CORE.RAW`: `5765813bb16a9c8ddfc1affbbb8c6f2013911870d5735db9e7f6cc34bd6b1b78`
- CPC `ROOTBAR.BIN`: `f163fa647194d4746075d9dc58d2a78409bbc731b9607abce9f572a6bc8320c7`

Normal `QA/MSX/GBMSX.IMG`, the user's `QA/CPC/`, recordings, and sibling
emulator sources are untouched. Tests use copied M4 images, never floppies.

## Try it

Build the ordinary private runtime:

```sh
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make diagnostic-cpc-runtime
distrobox enter my-distrobox -- ../1984/1984 \
  --config=QA/Diagnostics/CPC-runtime/1984.conf \
  --6128 --memory=512 --autostart=BOOT
```

Use Desk to open Clock/Calculator, then click empty background for **R**.
With the unchanged configuration, windows should not all flash. A ticking
Clock can still perform its normal, clipped content updates independently.
The current pointer remains the keyboard/joystick adapter.

`make diagnostic-cpc-assets-1984` builds and runs the custom-font/custom-palette
automated case. That case modifies **only a copied test image**, not the
ordinary manual runtime. For a built image, use
`python3 tools/test_cpc_runtime_1984.py --skip-build --asset-case <case>`;
`--help` lists cases. Do not modify a filesystem image while an emulator has
it mounted; prepare copies offline. Rebuilding restages the default card.

## Next

**3D-T: icon/cursor/backdrop asset providers**, using the shared loaders and
the same canonical formats. Budget storage and validate rendering before
connecting the full shared Desktop/File Manager. Titlebar/gadget tile modules
also remain unbound, as do file pickers and System/Settings.

`GB_RELOAD` stays explicitly unavailable: supporting one asset family must not
pretend to implement the complete native service. No new capability bit or
portable-app admission promise is added. Issue #77 and the production adapter,
Desktop integration and application parity gates remain open.
