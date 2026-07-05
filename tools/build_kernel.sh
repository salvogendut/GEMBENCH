#!/usr/bin/env bash
# Build the GEOBENCH banked-kernel skeleton + the HELLO app (Phase 1 proof).
#
# Apps are separate binaries; the app is built FIRST because the kernel incbins
# build/HELLO.RAW. Output: build/gbkern.dsk (GBKERN.BIN, with HELLO embedded).
#   tools/build_kernel.sh
#   1984 --memory=128 --disk-a=build/gbkern.dsk --autostart=GBKERN
set -euo pipefail

cd "$(dirname "$0")/.."          # repo root
RASM="${RASM:-rasm}"

# The card ships both Albireo and M4 kernels in QA/CARD and QA/GEOBENCH.IMG.
# STORAGE only picks the backend left in build/ for the dev harness (--disk-a):
# "albireo" (default), "m4", or "ide" (the dormant legacy backend, still buildable
# for recovery/tests). Backends are mutually exclusive per build (#104).
case "${STORAGE:-albireo}" in
    albireo) STORAGE_FLAG="-DSTORAGE_ALBIREO=1" ;;
    m4)      STORAGE_FLAG="-DSTORAGE_M4=1" ;;
    ide)     STORAGE_FLAG="" ;;
    *)
        echo "STORAGE must be one of: albireo, m4, ide" >&2
        exit 2
        ;;
esac

# FAT16=1: build the IDE kernel FAT16-only (drops the FAT32 read branches, ~81 B
# smaller resident). Real CPC IDE/SD cards are FAT16 (#130, #148); the dev/test
# FAT32 images need the default full build. Albireo is unaffected (chip does FAT).
FAT16_FLAG=""
if [ "${FAT16:-0}" = "1" ]; then
    FAT16_FLAG="-DFAT16_ONLY=1"
    echo "FAT16=1: building a FAT16-only IDE kernel (no FAT32 read path)"
fi

mkdir -p build
rm -f build/gbkern.dsk                        # save-to-DSK appends; start clean

BUILD_COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
if ! git diff --quiet --ignore-submodules -- 2>/dev/null \
    || ! git diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
    BUILD_COMMIT="${BUILD_COMMIT}-dirty"
fi
echo "Build id: GB $BUILD_COMMIT"

python3 tools/make_bootsplash.py assets/SPLASH.png build/SPLASH_BUILD.png "$BUILD_COMMIT"
python3 tools/png2cpc.py build/SPLASH_BUILD.png build/SPLASH.BIN splash 96x184  # #196: bootsplash + build id
# Default GEOBENCH.CFG (#205): one source for BOTH distributions - the card root (stage_dist.sh)
# and the floppy DSK (pack_apps3.asm). CR+LF, as the CPC requires. Without it on the floppy the
# Settings app read all-blank and could not persist a change (the kernel falls back to defaults).
printf 'FONT=DEFAULT\r\nICONS=REFINED\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\nBACKDROP=SOLID\r\nWALLPAPER=LOGO\r\nSAVER=SQUARES\r\nSAVERTIME=2\r\n' > build/GEOBENCH.CFG
python3 tools/genfont.py build/DEFAULT.FNT   # 6x8 font -> PAGE_DATA
python3 tools/packfont.py build/CLASSIC.FNT lib/font.asm  # 8x8 ROM font (FONT=CLASSIC)
python3 tools/packicons.py build/DEFAULT.IST \
    lib/icon_floppy.asm lib/icon_ide.asm lib/icon_clock.asm lib/icon_trash.asm \
    lib/icon_geobench.asm lib/icon_basic.asm lib/icon_binary.asm \
    lib/icon_picture.asm lib/icon_text.asm lib/icon_folder.asm \
    lib/icon_app.asm lib/icon_notepad.asm lib/icon_iconeditor.asm \
    lib/icon_font.asm \
    lib/icon_desktop.asm lib/icon_filemanager.asm \
    lib/icon_paint.asm lib/icon_fractal.asm lib/icon_sd.asm \
    lib/icon_viewer.asm \
    lib/icon_telnet.asm lib/icon_network.asm lib/icon_shell.asm \
    lib/icon_up.asm lib/icon_screensaver.asm \
    # slots: 9=folder 10=.APP 11=NOTEPAD 12=ICONED 13=.FNT 14=DESKTOP 15=FILEMGR
    # 16=PAINT 17=FRACTAL 18=SD (Albireo Disk C, #104) 19=VIEWER
    # 20=TELNET 21=NETWORK 22=SHELL 23=UP (FileMgr ".." entry, #142) 24=SCREENSAVER (.SAV, #221 reused gear slot)
    # NOTE (#198): icon_iconset removed - it was byte-identical to icon_app; .IST files
    # now show the .APP icon, shrinking DEFAULT.IST by one slot (the floppy AMSDOS reader
    # garbles the icon set above a size threshold). All slots >=14 shifted up by 1.
# PAINT toolchest set (24x24, ICONED-editable, #114). PAINT's 16K bank caps the loaded
# set at ~6 icons, so the built .IST holds just the 5 live tools (pencil/square/circle/
# fill/undo, TOOL_* order), refreshed from assets/paint-tools.png (#246). The full
# 14-tool art lives in assets/paint/*.asm for ICONED + future tools.
python3 tools/packicons.py build/PAINT.IST \
    assets/paint/pencil.asm assets/paint/square.asm assets/paint/circle.asm \
    assets/paint/fill.asm assets/paint/undo.asm
# Backdrop tiles (#128): stage every assets/backdrops tile as build/<NAME>.BDP - copy any
# ready-made *.BDP, and convert any *.png that has no matching .BDP. Uppercased 8.3 names.
for bdp in assets/backdrops/*.BDP; do
    [ -e "$bdp" ] && cp "$bdp" "build/$(basename "$bdp" | tr 'a-z' 'A-Z')"
done
for png in assets/backdrops/*.png; do
    [ -e "$png" ] || continue
    name="$(basename "$png" .png | tr 'a-z' 'A-Z')"
    [ -e "build/$name.BDP" ] || python3 tools/png2backdrop.py "$png" "build/$name.BDP"
done
DATA_LOC=0x6C00 NET=1 DOC=1 tools/build_capp.sh apps/telnet build/TELNET.RAW # TELNET (#238): windowed ANSI/VT terminal + telnet client (+ Mode-2 80x25 fullscreen)
DATA_LOC=0x7000 NET=1 tools/build_capp.sh apps/nettest build/NETTEST.RAW # NETTEST (#261): card-side DNS/TCP/HTTP diagnostic for the active network backend
DATA_LOC=0x6D00 DOC=1 tools/build_capp.sh apps/desktop build/DESKTOP.RAW # DESKTOP (C/SDCC): System
                                   # menu via the shared gb_doc menu system (#142). Higher data-loc
                                   # for the wallpaper config parse (#212/#216), saver trigger (#219),
                                   # and clip-aware wallpaper repaint path.
DATA_LOC=0x7740 DOC=1 tools/build_capp.sh apps/filemgr build/FILEMGR.RAW # FILEMGR: data-loc above
                                   # the gb_doc-grown code + ".." entry; the 128-entry listing cache
                                   # (#118) fits the rest. DOC=1 = View menu (Fullscreen/Icons-List) (#142)
DATA_LOC=0x5F20 DOCRO=1 tools/build_capp.sh apps/viewer build/VIEWER.RAW # VIEWER: read-only
                                   # gb_doc (DOCRO=1 omits Save/Save As) so a full 10240-B buffer
                                   # (200x200 .PIC) fits. File>Load + View>Fullscreen (#142/#144)
DATA_LOC=0x6BF0 DOC=1 tools/build_capp.sh apps/notepad build/NOTEPAD.RAW # NOTEPAD: doc framework (#142),
                                   # code-heavy, so a higher data-loc gives it ~1.9K code room
                                   # (#97); shared File popup + name prompt (gbdlg/gbprompt, #114)
DATA_LOC=0x62C0 DOC=1 tools/build_capp.sh apps/iconed build/ICONED.RAW # ICONED: data-loc above
                                   # the gb_doc/fullscreen code so the 6656-B icon-set buffer
                                   # (BUFSZ, holds DEFAULT.IST) + 256-B packed grid fit (#110/#142)
DOC=1 tools/build_capp.sh apps/clock  build/CLOCK.RAW # CLOCK (C/SDCC): View>Fullscreen + Options
                                   # via the shared gb_doc menu system (#142) -> build/CLOCK.RAW
DATA_LOC=0x6300 DOC=1 tools/build_capp.sh apps/paint build/PAINT.RAW # PAINT: doc framework (#142)
                                   # + name prompt (gbdlg.c + gbprompt.c) for its File menu (#114)
DOC=1 tools/build_capp.sh apps/xaos build/XAOS.RAW   # XAOS fractal generator:
                                   # File>Save dialog (gbdlg + gbprompt) -> .PIC (#116)
DATA_LOC=0x6F00 DIALOGS=1 tools/build_capp.sh apps/settings build/SETTINGS.RAW # SETTINGS (#129): the control
                                   # panel - pick FONT=/ICONS=/CURSOR= from /GBENCH (gb_popup),
                                   # rewrite GEOBENCH.CFG; data-driven rows grow with colours/etc.
DIALOGS=1 tools/build_capp.sh apps/diskutil build/DISKUTIL.RAW # DISKUTIL: floppy formatter - a physical
                                   # uPD765 FORMAT TRACK straight to the FDC (Data/System/exotic 80-trk DS);
                                   # gb_popup confirm. Reuses the floppy icon (DEFAULT.IST slot 0).
tools/build_capp.sh apps/saver build/SQUARES.RAW  # SAVER (#219/#281): random squares - a
                                   # full-screen blank + squares, shipped as SQUARES.SAV. Launched by
                                   # the desktop idle timer (SAVER=<seconds>); no menu/doc framework.
tools/build_capp.sh apps/deco  build/DECO.RAW     # DECO screensaver (ported from symsav-deco):
                                   # recursive rectangle subdivision -> art-deco panels. -> DECO.SAV
tools/build_capp.sh apps/xmatrix build/XMATRIX.RAW # XMATRIX screensaver (ported from symsav-xmatrix):
                                   # Matrix digital rain, white head -> red -> black glow. -> XMATRIX.SAV
tools/build_capp.sh apps/mountain build/MOUNTAIN.RAW # MOUNTAIN screensaver (ported from symsav-mountain):
                                   # isometric filled terrain + white wireframe, direct #C000 plot. -> MOUNTAIN.SAV
tools/build_capp.sh apps/fractalic build/FRACTALI.RAW # FRACTALIC screensaver (ported from symsav-fractalic):
                                   # random fractal (Sierpinski/Koch/Dragon/Fern), direct #C000 plot.
                                   # CARD-ONLY (too big for the floppy) -> FRACTALI.SAV via stage_dist.sh
tools/build_capp.sh apps/starfield build/STARFLD.RAW # STARFIELD screensaver (fresh impl, inspired by
                                   # symsav-starfield): 3D stars flying toward the viewer, direct #C000 plot.
tools/build_capp.sh apps/xroach build/XROACH.RAW  # XROACH screensaver (ported from symsav-xroach):
                                   # 16x16 cockroaches scatter + flee a wandering "odd roach", direct
                                   # #C000 blit. CARD-ONLY (floppy pack full) -> XROACH.SAV via stage_dist.sh
tools/build_capp.sh apps/munch build/MUNCH.RAW    # MUNCH screensaver (xscreensaver port): munching
                                   # squares XOR moire, direct #C000. CARD-ONLY -> MUNCH.SAV
tools/build_capp.sh apps/rorschach build/RORSCH.RAW # RORSCHACH (xscreensaver port): 4-fold-symmetric
                                   # random-walk ink-blots, direct #C000. CARD-ONLY -> RORSCH.SAV
tools/build_capp.sh apps/truchet build/TRUCHET.RAW # TRUCHET (xscreensaver port): random diagonal-tile
                                   # maze, direct #C000 lines. CARD-ONLY -> TRUCHET.SAV
tools/build_capp.sh apps/ant build/ANT.RAW        # ANT (xscreensaver port): Langton's ant on an 80x50
                                   # grid, gb_fill cells. CARD-ONLY -> ANT.SAV
tools/build_capp.sh apps/lightning build/LIGHTN.RAW # LIGHTNING (xscreensaver port): midpoint-displacement
                                   # forked bolts, direct #C000 lines. CARD-ONLY -> LIGHTN.SAV
tools/build_capp.sh apps/pyro build/PYRO.RAW      # PYRO (xscreensaver port): fixed-point fireworks
                                   # rockets + shrapnel, direct #C000. CARD-ONLY -> PYRO.SAV
tools/build_capp.sh apps/forest build/FOREST.RAW  # FOREST (xscreensaver port): recursive fractal trees
                                   # with red blossoms, direct #C000 lines. CARD-ONLY -> FOREST.SAV
tools/build_capp.sh apps/helix build/HELIX.RAW    # HELIX (xscreensaver port): woven harmonograph curves
                                   # (sin-table), direct #C000 lines. CARD-ONLY -> HELIX.SAV
DATA_LOC=0x6700 tools/build_capp.sh apps/catclock build/CATCLK.RAW # CATCLOCK (inspired by X11 catclock):
                                   # Kit-Cat clock - embedded body bitmap (catimg.h, from png2catclock.py) +
                                   # moving pupils + real hour/minute hands (gb_time). CARD-ONLY -> CATCLK.SAV
tools/build_cfgmod.sh build/GBCFG.RAW              # config-parser C kernel module -> build/GBCFG.RAW
tools/build_fatmod.sh                              # FAT16/IDE write module -> build/GBFAT.RAW
tools/build_floppymod.sh                           # AMSDOS/floppy write module -> build/FLOPPYSV.RAW
tools/build_uimod.sh build/GBUI.RAW                # paged dialog module (#142) -> build/GBUI.RAW
tools/build_netmod.sh build/GBNET.RAW             # W5100 networking module (#238) -> build/GBNET.RAW
tools/build_m4netmod.sh build/GBNETM4.RAW         # M4 TCP networking module (#259) -> build/GBNETM4.RAW
tools/build_m4savemod.sh                          # M4 file save module (#259) -> build/M4SAVE.RAW
# Card distribution: the apps/modules/assets above are shared; we assemble the Albireo
# and M4 kernels, capture their raw images, and stage QA/CARD/ holding the BASIC loader
# GB.BAS + both kernels (GBALB.BIN, GBM4.BIN). Plus a bootable floppy image
# QA/GEOBENCH.DSK using the Albireo kernel (it falls back to floppy when no card is
# present). The IDE backend remains archived (frozen in-tree, not shipped).
build_variant() {                                # $1 = kernel name, $2 = rasm -D flag
    rm -f build/gbkern.dsk                       # save-to-DSK appends; start clean
    "$RASM" kernel/gbkern.asm -eo $2 ${EXTRA_RASM:-} # incbins apps + font + icons -> .dsk + RAW
    "$RASM" kernel/pack_modules.asm -eo          # paged modules that no longer fit gbkern.asm
    "$RASM" kernel/pack_apps.asm -eo             # 2nd pass: overflow apps -> same .dsk (#114)
    "$RASM" kernel/pack_apps2.asm -eo            # 3rd pass: VIEWER + FILEMGR -> same .dsk (#142)
    "$RASM" kernel/pack_apps3.asm -eo            # 4th pass: backdrops/REFINED/pictures -> same .dsk (#198)
    cp build/GBKERN.RAW "build/$1.RAW"           # capture this card's kernel for the unified stage
}
# Clean only the CPC outputs - QA/MSX (the MSX2 target, #287) survives a CPC build.
rm -rf QA/CARD QA/GEOBENCH.DSK QA/COMPANION.DSK QA/GEOBENCH.IMG; mkdir -p QA
# Build both card kernels. QA/GEOBENCH.DSK keeps the Albireo/floppy-capable kernel
# because that is the normal floppy boot image; QA/CARD and QA/GEOBENCH.IMG carry both.
echo "Building the Albireo (GBALB) and M4 (GBM4) card kernels + the shared card -> QA/"
build_variant GBALB "-DSTORAGE_ALBIREO=1"
cp build/gbkern.dsk QA/GEOBENCH.DSK               # bootable floppy image (the GBALB kernel)
build_variant GBM4 "-DSTORAGE_M4=1"
# Add a GB.BAS loader so the floppy also boots via RUN"GB (-> RUN"GBKERN). Must be a
# HEADERLESS ASCII file - RASM's DSK save adds an AMSDOS header, so use iDSK (-t 0).
# Graceful: without iDSK the floppy still boots via RUN"GBKERN.
IDSK="${IDSK:-$HOME/Dev/cpc-mastering/idsk}"
if [ -x "$IDSK" ]; then
    printf '10 RUN"GBKERN\r\n' > build/GB.BAS
    "$IDSK" QA/GEOBENCH.DSK -i build/GB.BAS -t 0 >/dev/null 2>&1 \
        && echo "  + GB.BAS on QA/GEOBENCH.DSK (floppy RUN\"GB)" \
        || echo "  (iDSK present but GB.BAS insert failed - floppy still RUN\"GBKERN)"
else
    echo "  (no iDSK at \$IDSK - floppy boots via RUN\"GBKERN; set IDSK= to add the GB.BAS loader)"
fi
# Companion floppy QA/COMPANION.DSK (#250): a non-bootable DATA disk with the extras
# (Paint/Telnet/Xaos, all screensavers, the gallery pictures). Meant for drive B - the
# kernel loader falls back boot-drive(A) -> browse-drive(B), so these load from B while
# their shared deps stay on Main. Three fresh 64K passes APPEND to one DSK (pass 1
# creates it). All .RAW/.SAV are already built above; pictures are tracked assets.
rm -f build/companion.dsk
"$RASM" kernel/pack_comp1.asm -eo                  # apps + PENGUIN.PIC
"$RASM" kernel/pack_comp2.asm -eo                  # TLEUNG.PIC + savers (1/2)
"$RASM" kernel/pack_comp3.asm -eo                  # savers (2/2)
cp build/companion.dsk QA/COMPANION.DSK
echo "  + QA/COMPANION.DSK (Companion floppy: Paint/Telnet/Xaos + savers + pictures)"
tools/stage_dist.sh QA/CARD                       # GB.BAS auto-detect + GBALB.BIN + GBM4.BIN + /GBENCH
# A ready-to-flash card image (partitioned FAT16) for the Albireo CH376 card and M4 image mode.
tools/build_card_img.sh QA/CARD QA/GEOBENCH.IMG \
    || echo "  (QA/GEOBENCH.IMG skipped - needs sfdisk + mkfs.fat + mtools)"
echo "  QA/CARD: loose files; QA/GEOBENCH.IMG: Albireo/M4 card; QA/GEOBENCH.DSK: floppy (RUN\"GB)"

# Leave build/ as the STORAGE-selected variant (default Albireo) so the --disk-a
# test harness sees a predictable build/gbkern.dsk + build/GBKERN.RAW.
rm -f build/gbkern.dsk
"$RASM" kernel/gbkern.asm -eo $STORAGE_FLAG ${FAT16_FLAG:+$FAT16_FLAG} >/dev/null
"$RASM" kernel/pack_modules.asm -eo >/dev/null  # paged modules that no longer fit gbkern.asm
"$RASM" kernel/pack_apps.asm -eo >/dev/null      # 2nd pass: overflow apps -> .dsk (#114)
"$RASM" kernel/pack_apps2.asm -eo >/dev/null     # 3rd pass: VIEWER + FILEMGR -> .dsk (#142)
"$RASM" kernel/pack_apps3.asm -eo >/dev/null     # 4th pass: backdrops/REFINED/pictures -> .dsk (#198)
if [ -x "$IDSK" ]; then
    "$IDSK" build/gbkern.dsk -i build/GB.BAS -t 0 >/dev/null 2>&1 || true
fi
echo "Built QA/CARD + QA/GEOBENCH.IMG (Albireo/M4 card deploy) + QA/GEOBENCH.DSK (floppy); build/ = ${STORAGE:-albireo} variant"
