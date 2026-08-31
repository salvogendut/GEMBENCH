# GEOBENCH-2 first production universal applications

Issue #60 migrates Calculator and Clock from target-compiled payloads to one
GBAP v4 byte sequence for MSX2, CPC, and PCW. The current MSX2 distribution
stages `build/universal/CALC.APP` and `build/universal/CLOCK.APP` unchanged. The
legacy target builds remain available under `build/msx/*.RAW` as regression
fixtures while the other runtimes are reintroduced.

Calculator shares the existing fixed-point arithmetic core and uses only
runtime geometry, semantic drawing, normalized input, managed-window, and
accessory/deferred lifecycle calls. Its former embedded GBR tree is replaced by
the same fixed control layout rendered from portable primitives, avoiding a
package-resource dependency before that loader gate exists.

Both applications register persistent top-bar definitions after their managed
window. Calculator exposes `Edit > Clear`; Clock exposes `View > Fullscreen` and
`Options > Toggle Seconds`. Their dropdowns use the universal SDK's bounded
application-owned save-under buffer and semantic drawing calls, rather than the
target-era dialog scratch mailbox.

Clock uses the portable pixel-line wrapper and a generation-tagged background
damage publisher. Its worker observes the root-owned time snapshot and may only
publish a bounded rectangle. The root collector validates identity and actual
visibility before invoking the compositor. Fully hidden surfaces receive an
acknowledgement but no drawing or foreground damage. The focused path updates
directly; the background path alternates exact hand and digital damage so it
does not repaint the whole window every second.

The new high capability `0x00400000` identifies this background-timer contract.
Universal source never sees the fixed line/timer records, mapper state, VDP
ports, or scheduler slots; those remain behind `gbuniversal` accessors.

Build and host-check both applications with:

```sh
make geobench-v2-tier1
python3 tools/test_universal_tier1.py
```

For the current target, build and boot normally. Open Clock from the desktop or
Desk menu and Calculator from the Desk menu:

```sh
make geobench-msx
MSX_UNAPI=0 tools/run_msx.sh QA/MSX/GBMSX.IMG
```

Clock keeps ticking when partially visible behind another window, stops
publishing effective repaint while fully covered, supports kernel-owned
move/resize/maximize, and toggles seconds with `S`. Calculator accepts pointer
buttons and the existing keyboard shortcuts.

The openMSX accessory regression also checks presentation contracts: Calculator
must issue its initial display plus twenty label draws with the correct ABI
register order, each application must preserve the compositor-owned side and
bottom borders, and focus must install the application's expected top-bar menu.
