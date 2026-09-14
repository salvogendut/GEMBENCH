# Unified Notepad: milestone 1 closure

2026-09-14, issue
[#84](https://github.com/salvogendut/GEMBENCH/issues/84), branch
`feature/84-notepad-closure`, baseline `3cf32fb`.

This final acceptance pass closes the two omissions found after the delivery,
safe-reuse and live-configuration sprints. It does not expand v1.0 release
scope to CPC Albireo, PCW or whole-distribution release qualification.

## Closed gaps

### Portable CPC 8.3 paths

The CPC filesystem provider previously accepted only eight-character directory
components and a small filename alphabet. That contradicted the portable file
chooser, which emits bounded `BASE[.EXT]` components and the documented portable
8.3 punctuation set.

`kernel/kc/cpc_path83.h` is now the single production grammar used by CPC
context activation, selected filenames and directory aliases. It accepts root
and nested paths, dotted directory components, 1–8 byte bases, 1–3 byte
extensions and the chooser alphabet `A-Z`, `0-9`, and
`` !#$%&'()-@^_`{}~ ``. It rejects empty components, trailing separators,
multiple/empty extensions, lowercase input, spaces, plus signs and all length
overflows before issuing an M4 command.

The host grammar test covers every accepted punctuation byte and all component
boundaries. The rebuilt production CPC provider occupies 5002 of its 6656-byte
allocation; the complete CPC image still passes every link-size guard.

### Real BASIC newline round trip

A real `ROUND.BAS` fixture now exercises the identical Notepad APP on both
targets. Its source bytes are:

```text
10 PRINT "ONE"<CR><LF>
20 END<CR><LF>
```

The test opens Notepad through normal File Manager handoff, uses Notepad's own
File > Open chooser to select the BASIC document, proves the editor model has
normalized LF bytes, edits and saves it, reopens it, and independently reads the
media to prove exact CRLF output. The CPC case deliberately places the file in
`/ADOC/DIR.EXT/ROUND.BAS`, combining newline and dotted-directory coverage.
The configuration newline path remains covered by the prior configuration
sprint and was rerun after this provider change.

## Acceptance evidence

- CPC/1984, disposable M4 image only: the new `basic` case passed at
  `build/cpc-delivery-runtime/geobench-cpc-runtime-dp19nm3g`. Its checkpoints
  include normalized load, CRLF save, exact reopen and clean desktop teardown.
- CPC/1984, disposable M4 images: the existing `handoff` and `config` cases
  passed again at `geobench-cpc-runtime-ndu54ifo` and
  `geobench-cpc-runtime-vwoens5i`. No floppy media was used.
- MSX/1983: the new BASIC case passed 32 checks in both Screen 6 and Screen 7 at
  `build/notepad-84/closure-basic-1983-6-v3` and
  `build/notepad-84/closure-basic-1983-7-v3`. Both disposable source images were
  unchanged after the run; their SHA-256 values are
  `c511777761de0f5fb884b6f16ae74904a3e0519ff143857953fbca9682d01b3e`
  and `5aa0b55efd7ae05461874a59c090391a85d0d5addefc7064a719b222de42243d`.
- openMSX independently reran the Screen 7 editor/configuration regression:
  282 parameter/restoration checks and exact saved bytes passed at
  `build/notepad-84/closure-openmsx-7`.
- The focused host regression ran 33 tests covering the path grammar, CPC
  context/directory/read/write providers, chooser, unified Notepad, package
  receiver and CPC text input. All passed.
- `make cpc` and `make msx` passed. The identical production Notepad remains
  20521 bytes with
  SHA-256
  `fae9ad2f6da69b906af13836f7230095d2ca8421211a8f80a79e310813f933b7`;
  no target-specific editor was introduced.

Together with the earlier [delivery](UNIFIED-NOTEPAD-DELIVERY.md),
[safe-reuse](UNIFIED-NOTEPAD-REUSE.md), and
[configuration](UNIFIED-NOTEPAD-CONFIG.md) evidence, every issue #84 acceptance
row is now satisfied. Broader release, Albireo and boot-splash work remains in
the later roadmap milestones.

| Issue #84 acceptance row | Disposition |
| --- | --- |
| 4096-byte capacity and New/Load/Save/Save As/View/Edit | Passed by delivery boundary and editor cases. |
| Exact real-file round trips, including BASIC/config newlines | Passed by the closure BASIC cases and configuration sprint. |
| Typed cross-instance clipboard and incompatible rejection | Passed by delivery clipboard cases. |
| Dirty decisions, failed I/O and resource exhaustion | Passed by delivery and reuse failure cases. |
| File Manager handoff and safe live reuse | Passed by delivery and reuse sprints. |
| Focus, damage, Clock/pointer responsiveness and cleanup | Passed by normal-delivery interaction and lifecycle cases. |
| Identical portable APP and runtime geometry | The unchanged hash above matches both staged distributions. |
| openMSX, 1983 and M4-backed CPC | All three passed; CPC used no floppy media. |
| Separate MSX/CPC/unified ledger results | Updated in [V1-APPLICATION-LEDGER.md](V1-APPLICATION-LEDGER.md). |
