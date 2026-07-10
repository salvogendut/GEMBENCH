#!/usr/bin/env bash
# stage_dist.sh <outdir>: stage the GEOBENCH Albireo/M4 card (#104 + #134 + #136 + #259).
# The shipped card contains both the Albireo (CH376) and M4 kernels. GB.BAS probes
# M4ROM and RUN"s GBM4 on M4 hardware, otherwise GBALB.
# On-card layout:
#   AUTOEXEC.BAS - M4ROM cold-boot hook; tokenized BASIC that RUN"s GB.BAS.
#   GB.BAS       - BASIC loader: LOAD/CALL M4DETECT, then RUN"GBM4 or RUN"GBALB.
#                  (A machine-code loader is impossible under UniDOS - see memory
#                  geobench-loader-136 - hence BASIC.)
#   M4DETECT.BIN - tiny RAM probe at 0x4000; writes 1/0 to 0x4030.
#   GBALB.BIN    - Albireo (CH376) kernel: real 128-byte AMSDOS header, exec 0x8000;
#                  falls back to floppy A when no card is present.
#   GBM4.BIN     - M4 board kernel: real 128-byte AMSDOS header, exec 0x8000.
#   GEOBENCH.CFG - config (root; read before the kernel enters /GBENCH)
#   GBENCH/      - everything the kernel loads at boot (apps/modules/fonts/icons/cursor)
# Boot: RUN"GB -> detector -> RUN"GBM4 or RUN"GBALB -> the kernel reads /GBENCH.
# Needs build/GBALB.RAW and build/GBM4.RAW.
#   * <app>.APP / GBCFG/GBFAT/FLOPPYSV/GBUI.MOD - HEADERLESS raw kernel modules (#234: .MOD,
#     not .BIN, so .BIN is reserved for native runnable binaries; the kernel loads them)
#   * GB.BAS / GEOBENCH.CFG - written with CR+LF line endings (the CPC requires them)
set -euo pipefail
cd "$(dirname "$0")/.."
RASM="${RASM:-rasm}"
GB_BASIC_DIR="${GB_BASIC_DIR:-../GB-BASIC}"

OUT="${1:?usage: tools/stage_dist.sh <outdir>}"
SYS="$OUT/GBENCH"                    # the system folder (#174: <=7 chars so the M4's
                                     # '>'-prefixed dir listing round-trips it; was /GEOBENCH)
mkdir -p build
mkdir -p "$SYS"

# --- root: the loader, both card kernels, the config --------------------------
# GB.BAS remains BASIC because UniDOS needs DOS active while RUN"ing the selected
# binary. ASCII with CR+LF, as the CPC requires. AUTOEXEC.BAS must be tokenized:
# M4ROM's cold-boot loader reads ASCII but does not execute it.
"$RASM" tools/m4detect.asm -eo >/dev/null
python3 tools/make_autoexec_bas.py "$OUT/AUTOEXEC.BAS"
printf '10 MEMORY &3FFF\r\n20 LOAD"M4DETECT",&4000\r\n30 CALL &4000\r\n40 IF PEEK(16432)=1 THEN RUN"GBM4\r\n50 RUN"GBALB\r\n' > "$OUT/GB.BAS"
python3 tools/amsdos_header.py build/M4DETECT.RAW "$OUT/M4DETECT.BIN" M4DETECT BIN 0x4000
python3 tools/amsdos_header.py build/GBALB.RAW "$OUT/GBALB.BIN" GBALB BIN 0x8000
python3 tools/amsdos_header.py build/GBM4.RAW "$OUT/GBM4.BIN" GBM4 BIN 0x8000
cp build/GEOBENCH.CFG "$OUT/GEOBENCH.CFG"   # #205: one source, shared with the floppy DSK (pack_apps3)

# --- /GBENCH: apps, modules, assets -------------------------------------------
for a in DESKTOP FILEMGR VIEWER NOTEPAD ICONED CLOCK PAINT XAOS SETTINGS DISKUTIL; do
    cp "build/$a.RAW" "$SYS/$a.APP"
done
cp build/TELNET.RAW  "$SYS/TELNET.APP"      # #238: windowed ANSI/VT terminal + telnet client
cp build/NETTEST.RAW "$SYS/NETTEST.APP"     # #261: DNS/TCP/HTTP diagnostic for Albireo/Net4CPC and M4 backends
cp build/WGET.RAW    "$SYS/WGET.APP"        # #363: streaming HTTP downloader for any writable drive
for f in "$GB_BASIC_DIR/build/BASIC.RAW" "$GB_BASIC_DIR/build/BASRUN.RAW" "$GB_BASIC_DIR/build/BASRUN2.BIN"; do
    [ -s "$f" ] || { echo "ERROR: missing GB-BASIC payload $f (run make -C \"$GB_BASIC_DIR\" raws)" >&2; exit 1; }
done
cp "$GB_BASIC_DIR/build/BASIC.RAW"   "$SYS/BASIC.APP"   # GB-BASIC editor (external repo)
cp "$GB_BASIC_DIR/build/BASRUN.RAW"  "$SYS/BASRUN.APP"  # GB-BASIC runtime
cp "$GB_BASIC_DIR/build/BASRUN2.BIN" "$SYS/BASRUN2.BIN" # GB-BASIC float/graphics low-RAM overlay
for bas in "$GB_BASIC_DIR"/examples/*.BAS; do           # examples next to BASIC/BASRUN
    [ -e "$bas" ] || continue
    sed 's/$/\r/' "$bas" > "$SYS/$(basename "$bas")"
done
cp build/SQUARES.RAW "$SYS/SQUARES.SAV"     # #219/#281: the default screensaver (a .SAV, not a .APP)
cp build/DECO.RAW   "$SYS/DECO.SAV"         # art-deco panels screensaver (ported from symsav-deco)
cp build/XMATRIX.RAW "$SYS/XMATRIX.SAV"     # Matrix digital-rain screensaver (ported from symsav-xmatrix)
cp build/MOUNTAIN.RAW "$SYS/MOUNTAIN.SAV"   # isometric terrain screensaver (ported from symsav-mountain)
cp build/STARFLD.RAW  "$SYS/STARFLD.SAV"    # 3D star-field screensaver (inspired by symsav-starfield)
cp build/FRACTALI.RAW "$SYS/FRACTALI.SAV"   # fractal screensaver (ported from symsav-fractalic) - CARD ONLY
cp build/XROACH.RAW   "$SYS/XROACH.SAV"     # cockroach screensaver (ported from symsav-xroach) - CARD ONLY
cp build/MUNCH.RAW    "$SYS/MUNCH.SAV"      # munching-squares screensaver (xscreensaver port) - CARD ONLY
cp build/RORSCH.RAW   "$SYS/RORSCH.SAV"     # rorschach ink-blot screensaver (xscreensaver port) - CARD ONLY
cp build/TRUCHET.RAW  "$SYS/TRUCHET.SAV"    # truchet-tile maze screensaver (xscreensaver port) - CARD ONLY
cp build/ANT.RAW      "$SYS/ANT.SAV"        # Langton's-ant screensaver (xscreensaver port) - CARD ONLY
cp build/LIGHTN.RAW   "$SYS/LIGHTN.SAV"     # fractal-lightning screensaver (xscreensaver port) - CARD ONLY
cp build/PYRO.RAW     "$SYS/PYRO.SAV"       # fireworks screensaver (xscreensaver port) - CARD ONLY
cp build/FOREST.RAW   "$SYS/FOREST.SAV"     # fractal-trees screensaver (xscreensaver port) - CARD ONLY
cp build/HELIX.RAW    "$SYS/HELIX.SAV"      # harmonograph screensaver (xscreensaver port) - CARD ONLY
cp build/CATCLK.RAW   "$SYS/CATCLK.SAV"     # Kit-Cat clock screensaver (inspired by X11 catclock) - CARD ONLY
cp build/GBCFG.RAW "$SYS/GBCFG.MOD"          # #234: kernel modules use .MOD (.BIN = native runnable)
cp build/GBFAT.RAW "$SYS/GBFAT.MOD"
cp build/FLOPPYSV.RAW "$SYS/FLOPPYSV.MOD"   # #135: paged AMSDOS/floppy write module
cp build/GBUI.RAW "$SYS/GBUI.MOD"           # #142: paged dialog (popup/prompt/file-picker) module
cp build/GBNET.RAW "$SYS/GBNET.MOD"         # #238: W5100 networking module (gb_net_* socket API)
cp build/GBNETM4.RAW "$SYS/GBNETM4.MOD"     # #259: M4 TCP module, same gb_net_* socket API
cp build/M4SAVE.RAW "$SYS/M4SAVE.MOD"       # #259: M4 C_OPEN/C_WRITE/C_CLOSE save module
cp build/DEFAULT.FNT build/CLASSIC.FNT build/DEFAULT.IST build/PAINT.IST \
   build/DEFAULT.SPR build/HAND.SPR "$SYS/"
cp build/SPLASH.BIN "$SYS/SPLASH.MOD"         # #196: bootsplash lollipop bitmap (.MOD, #234)
cp build/SPLASHD.BIN "$SYS/SPLASHD.MOD"       # DEBUG=TRUE variant with the build id
for bdp in build/*.BDP; do                    # #128: backdrop tiles (BACKDROP=<name>)
    [ -e "$bdp" ] && cp "$bdp" "$SYS/"
done
for ist in assets/iconsets/*.IST; do          # tracked custom icon sets (edit with
    [ -e "$ist" ] && cp "$ist" "$SYS/"         # tools/iconedit.py); select via ICONS=<name>
done
cp assets/WELCOME.TXT "$SYS/"
for pic in assets/pictures/*.PIC; do        # ship every .PIC in assets/pictures/ to the card
    [ -e "$pic" ] && cp "$pic" "$SYS/"       # (PENGUIN.PIC + anything you add - view in the Viewer)
done
