#!/usr/bin/env bash
# tools/build_kernel_msx.sh - build the MSX2 target (#287): the GBMSX.COM
# kernel + the M1 app/asset set, staged into QA/MSX and packed into the
# bootable Nextor image QA/GBMSX.IMG.
#
# Kept separate from tools/build_kernel.sh (that script is CPC-DSK-entangled
# and wipes its own QA outputs); the shared pieces (apps via build_capp.sh,
# GBCFG via build_cfgmod.sh, the Python asset tools) are reused, with
# -DGB_MSX2 / --platform msx2 selecting the MSX encodings.
#
#   bash tools/build_kernel_msx.sh
#   MSX_SHOTS="20 30 45" tools/run_msx.sh      # then verify in openMSX
set -euo pipefail
cd "$(dirname "$0")/.."

RASM="${RASM:-rasm}"
command -v "$RASM" >/dev/null || { echo "ERROR: rasm not on PATH" >&2; exit 1; }
command -v sdcc >/dev/null || { echo "ERROR: sdcc not on PATH" >&2; exit 1; }

mkdir -p build/msx QA/MSX/GBENCH

# --- the C apps, compiled with the MSX geometry ------------------------------
APPDEFS="-DGB_MSX2" DATA_LOC=0x6D00 DOC=1 tools/build_capp.sh apps/desktop build/msx/DESKTOP.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x7740 DOC=1 tools/build_capp.sh apps/filemgr build/msx/FILEMGR.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x6BF0 DOC=1 tools/build_capp.sh apps/notepad build/msx/NOTEPAD.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x6F00 DIALOGS=1 tools/build_capp.sh apps/settings build/msx/SETTINGS.RAW
APPDEFS="-DGB_MSX2" DIALOGS=1 tools/build_capp.sh apps/diskutil build/msx/DISKUTIL.RAW  # FAT12 quick-format (WRABS)
APPDEFS="-DGB_MSX2" DOC=1 tools/build_capp.sh apps/xaos build/msx/XAOS.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x62C0 DOC=1 tools/build_capp.sh apps/iconed build/msx/ICONED.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x6720 DOCRO=1 tools/build_capp.sh apps/viewer build/msx/VIEWER.RAW
APPDEFS="-DGB_MSX2" DATA_LOC=0x6300 DOC=1 tools/build_capp.sh apps/paint build/msx/PAINT.RAW
APPDEFS="-DGB_MSX2" DOC=1 tools/build_capp.sh apps/clock build/msx/CLOCK.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/saver build/msx/SQUARES.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/ant  build/msx/ANT.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/deco build/msx/DECO.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/xmatrix build/msx/XMATRIX.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/mountain build/msx/MOUNTAIN.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/forest build/msx/FOREST.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/starfield build/msx/STARFLD.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/fractalic build/msx/FRACTALI.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/munch build/msx/MUNCH.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/rorschach build/msx/RORSCH.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/truchet build/msx/TRUCHET.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/lightning build/msx/LIGHTN.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/pyro build/msx/PYRO.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/helix build/msx/HELIX.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/xroach build/msx/XROACH.RAW
APPDEFS="-DGB_MSX2" tools/build_capp.sh apps/catclock build/msx/CATCLK.RAW

# --- the shared config-parser module (platform-neutral C over low RAM) -----
tools/build_cfgmod.sh                            # -> build/GBCFG.RAW
tools/build_uimod.sh                             # -> build/GBUI.RAW (dialogs/menus)

# --- assets ------------------------------------------------------------------
python3 tools/genfont.py build/msx/DEFAULT.FNT           # 1bpp glyphs: shared format
python3 tools/packicons.py --platform msx2 build/msx/DEFAULT.IST \
    lib/icon_floppy.asm lib/icon_ide.asm lib/icon_clock.asm lib/icon_trash.asm \
    lib/icon_geobench.asm lib/icon_basic.asm lib/icon_binary.asm \
    lib/icon_picture.asm lib/icon_text.asm lib/icon_folder.asm \
    lib/icon_app.asm lib/icon_notepad.asm lib/icon_iconeditor.asm \
    lib/icon_font.asm \
    lib/icon_desktop.asm lib/icon_filemanager.asm \
    lib/icon_paint.asm lib/icon_fractal.asm lib/icon_sd.asm \
    lib/icon_viewer.asm \
    lib/icon_telnet.asm lib/icon_network.asm lib/icon_shell.asm \
    lib/icon_up.asm lib/icon_screensaver.asm
python3 tools/packicons.py --platform msx2 build/msx/PAINT.IST \
    assets/paint/pencil.asm assets/paint/square.asm assets/paint/circle.asm \
    assets/paint/fill.asm assets/paint/undo.asm
# The MSX pointer (66-byte V9938 hardware sprite). A hand-edited assets/pointer.SPR
# wins - edit it with `tools/iconedit.py --platform msx2 assets/pointer.SPR` (white
# = outline, red = fill); otherwise generate it from the PNG art. 11x13 art (smaller
# than the 14x16 default) matches the CPC pointer's apparent size - Screen 6's
# tall/narrow pixels otherwise render it bigger.
if [ -f assets/pointer.SPR ]; then
    cp assets/pointer.SPR build/msx/DEFAULT.SPR
else
    python3 tools/png2spr.py --platform msx2 assets/pointer.png build/msx/DEFAULT.SPR cursor 11x13
fi

# Bootsplash (#196/#287): the CPC lollipop, transcoded to Screen 6. The MSX
# kernel does not incbin it (that is CPC-only) - boot_splash loads SPLASH.MOD
# from disk, so we just stage the Screen-6 bitmap. DEBUG=TRUE selects the
# SPLASHD.MOD variant with the build id.
BUILD_COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
python3 tools/make_bootsplash.py assets/SPLASH.png build/msx/SPLASH_BUILD.png "$BUILD_COMMIT" GEOBENCH
python3 tools/png2cpc.py --platform msx2 build/msx/SPLASH_BUILD.png build/msx/SPLASH.BIN splash 96x184
python3 tools/make_bootsplash.py assets/SPLASH.png build/msx/SPLASHD_BUILD.png "$BUILD_COMMIT"
python3 tools/png2cpc.py --platform msx2 build/msx/SPLASHD_BUILD.png build/msx/SPLASHD.BIN splash 96x184

# --- the kernel + the .COM stub ---------------------------------------------
# RASM exits 0 even on assembly errors, so stale outputs would silently ship:
# remove them first and require fresh files after each pass.
rm -f build/msx/GBKERNM.RAW build/msx/GBMSX.COM
( cd build/msx && "$RASM" ../../kernel/gbkern.asm -DPLATFORM_MSX=1 -s -o gbkernm ${EXTRA_RASM:-} )
[ -s build/msx/GBKERNM.RAW ] || { echo "ERROR: GBKERNM.RAW not produced (rasm errors above)" >&2; exit 1; }
( cd build/msx && "$RASM" ../../kernel/msx_stub.asm )
[ -s build/msx/GBMSX.COM ] || { echo "ERROR: GBMSX.COM not produced (rasm errors above)" >&2; exit 1; }

# --- stage QA/MSX --------------------------------------------------------------
cp build/msx/GBMSX.COM QA/MSX/
printf 'GBMSX\r\n' > QA/MSX/AUTOEXEC.BAT
printf 'FONT=DEFAULT\r\nICONS=REFINED\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\nBACKDROP=SOLID\r\nWALLPAPER=LOGO\r\nSAVER=SQUARES\r\nSAVERTIME=2\r\n' > QA/MSX/GEOBENCH.CFG
cp build/msx/DESKTOP.RAW  QA/MSX/GBENCH/DESKTOP.APP
cp build/msx/FILEMGR.RAW  QA/MSX/GBENCH/FILEMGR.APP
cp build/msx/NOTEPAD.RAW  QA/MSX/GBENCH/NOTEPAD.APP
cp build/msx/SETTINGS.RAW QA/MSX/GBENCH/SETTINGS.APP
cp build/msx/DISKUTIL.RAW QA/MSX/GBENCH/DISKUTIL.APP
cp build/msx/XAOS.RAW     QA/MSX/GBENCH/XAOS.APP
cp build/msx/ICONED.RAW   QA/MSX/GBENCH/ICONED.APP
cp build/msx/VIEWER.RAW   QA/MSX/GBENCH/VIEWER.APP
cp build/msx/PAINT.RAW    QA/MSX/GBENCH/PAINT.APP
cp build/msx/PAINT.IST    QA/MSX/GBENCH/PAINT.IST
cp build/msx/CLOCK.RAW    QA/MSX/GBENCH/CLOCK.APP
cp build/msx/SQUARES.RAW  QA/MSX/GBENCH/SQUARES.SAV
cp build/msx/ANT.RAW      QA/MSX/GBENCH/ANT.SAV
cp build/msx/DECO.RAW     QA/MSX/GBENCH/DECO.SAV
cp build/msx/XMATRIX.RAW  QA/MSX/GBENCH/XMATRIX.SAV
cp build/msx/MOUNTAIN.RAW QA/MSX/GBENCH/MOUNTAIN.SAV
cp build/msx/FOREST.RAW   QA/MSX/GBENCH/FOREST.SAV
cp build/msx/STARFLD.RAW  QA/MSX/GBENCH/STARFLD.SAV
cp build/msx/FRACTALI.RAW QA/MSX/GBENCH/FRACTALI.SAV
cp build/msx/MUNCH.RAW QA/MSX/GBENCH/MUNCH.SAV
cp build/msx/RORSCH.RAW QA/MSX/GBENCH/RORSCH.SAV
cp build/msx/TRUCHET.RAW QA/MSX/GBENCH/TRUCHET.SAV
cp build/msx/LIGHTN.RAW QA/MSX/GBENCH/LIGHTN.SAV
cp build/msx/PYRO.RAW QA/MSX/GBENCH/PYRO.SAV
cp build/msx/HELIX.RAW QA/MSX/GBENCH/HELIX.SAV
cp build/msx/XROACH.RAW   QA/MSX/GBENCH/XROACH.SAV
cp build/msx/CATCLK.RAW   QA/MSX/GBENCH/CATCLK.SAV
cp assets/WELCOME.TXT     QA/MSX/WELCOME.TXT
cp build/GBCFG.RAW      QA/MSX/GBENCH/GBCFG.MOD
cp build/GBUI.RAW       QA/MSX/GBENCH/GBUI.MOD
cp build/msx/SPLASH.BIN  QA/MSX/GBENCH/SPLASH.MOD
cp build/msx/SPLASHD.BIN QA/MSX/GBENCH/SPLASHD.MOD
cp build/msx/DEFAULT.FNT QA/MSX/GBENCH/
cp build/msx/DEFAULT.IST QA/MSX/GBENCH/
cp build/msx/DEFAULT.SPR QA/MSX/GBENCH/

# --- drop-in assets: everything under assets/{backdrops,iconsets,pictures} gets
# transcoded to Screen 6 and packaged automatically, mirroring the CPC build's
# globs (build_kernel.sh / stage_dist.sh) so a file dropped in ships on BOTH
# distros. Names are uppercased 8.3. (#287)
for bdp in assets/backdrops/*.BDP; do            # backdrop tiles (BACKDROP=<name>)
    [ -e "$bdp" ] || continue
    name=$(basename "$bdp" .BDP | tr a-z A-Z)
    python3 tools/bdp_to_msx.py "$bdp" "QA/MSX/GBENCH/$name.BDP"
done
for png in assets/backdrops/*.png; do            # ... or a source PNG with no .BDP
    [ -e "$png" ] || continue
    name=$(basename "$png" .png | tr a-z A-Z)
    [ -e "QA/MSX/GBENCH/$name.BDP" ] || \
        python3 tools/png2backdrop.py --platform msx2 "$png" "QA/MSX/GBENCH/$name.BDP"
done
for ist in assets/iconsets/*.IST; do             # icon sets (ICONS=<name>)
    [ -e "$ist" ] || continue
    name=$(basename "$ist" .IST | tr a-z A-Z)
    python3 tools/ist_to_msx.py "$ist" "QA/MSX/GBENCH/$name.IST"
done
for pic in assets/pictures/*.PIC; do             # pictures: root (viewable on Disk C)
    [ -e "$pic" ] || continue                    # + GBENCH (WALLPAPER=<name>)
    name=$(basename "$pic" .PIC | tr a-z A-Z)
    python3 tools/pic_to_msx.py "$pic" "QA/MSX/$name.PIC"
    cp "QA/MSX/$name.PIC" "QA/MSX/GBENCH/$name.PIC"
done

# --- bootable Nextor image ------------------------------------------------------
bash tools/build_msx_img.sh QA/MSX QA/GBMSX.IMG

echo "MSX2 target built: QA/MSX (staged) + QA/GBMSX.IMG (bootable Nextor image)"
