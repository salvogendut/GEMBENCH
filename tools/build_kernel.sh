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

# The card ships the Albireo kernel only (IDE is retired - frozen on branch
# legacy-ide). STORAGE picks the backend left in build/ for the dev harness
# (--disk-a): "albireo" (default) or "ide" (the dormant legacy backend, still
# buildable for recovery/tests). Backends are mutually exclusive per build (#104).
STORAGE_FLAG="-DSTORAGE_ALBIREO=1"
if [ "${STORAGE:-albireo}" = "ide" ]; then
    STORAGE_FLAG=""
fi

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

python3 tools/png2cpc.py assets/SPLASH.png build/SPLASH.BIN splash 96x144  # #196: bootsplash lollipop (raw Mode-1 24x144)
# Default GEOBENCH.CFG (#205): one source for BOTH distributions - the card root (stage_dist.sh)
# and the floppy DSK (pack_apps3.asm). CR+LF, as the CPC requires. Without it on the floppy the
# Settings app read all-blank and could not persist a change (the kernel falls back to defaults).
printf 'FONT=DEFAULT\r\nICONS=REFINED\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\nBACKDROP=SOLID\r\nWALLPAPER=LOGO\r\nSAVER=CIRCLE\r\nSAVERTIME=2\r\n' > build/GEOBENCH.CFG
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
python3 tools/packicons.py build/PAINT.IST \
    assets/paint/pencil.asm assets/paint/square.asm assets/paint/circle.asm \
    assets/paint/fill.asm assets/paint/undo.asm   # PAINT toolchest set (24x24), ICONED-editable (#114)
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
NET=1 tools/build_capp.sh apps/nettest build/NETTEST.RAW # NETTEST (#238): GBNET.MOD smoke test
DATA_LOC=0x6600 DOC=1 tools/build_capp.sh apps/desktop build/DESKTOP.RAW # DESKTOP (C/SDCC): System
                                   # menu via the shared gb_doc menu system (#142). Higher data-loc
                                   # for the wallpaper config parse (#212/#216) + saver trigger (#219).
DATA_LOC=0x7240 DOC=1 tools/build_capp.sh apps/filemgr build/FILEMGR.RAW # FILEMGR: data-loc above
                                   # the gb_doc-grown code + ".." entry; the ~3.1K listing cache
                                   # (#118) fits the rest. DOC=1 = View menu (Fullscreen/Icons-List) (#142)
DATA_LOC=0x5F00 DOCRO=1 tools/build_capp.sh apps/viewer build/VIEWER.RAW # VIEWER: read-only
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
DATA_LOC=0x6700 DIALOGS=1 tools/build_capp.sh apps/settings build/SETTINGS.RAW # SETTINGS (#129): the control
                                   # panel - pick FONT=/ICONS=/CURSOR= from /GBENCH (gb_popup),
                                   # rewrite GEOBENCH.CFG; data-driven rows grow with colours/etc.
tools/build_capp.sh apps/saver build/CIRCLE.RAW   # SAVER (#219): the test screensaver - a
                                   # full-screen blank + circle, shipped as CIRCLE.SAV. Launched by
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
# Card distribution: the apps/modules/assets above are shared; we assemble the Albireo
# kernel, capture its raw image, and stage QA/CARD/ holding the BASIC loader GB.BAS +
# the kernel (GBALB.BIN). Plus a bootable floppy image QA/GEOBENCH.DSK (the same kernel
# falls back to floppy when no card is present). The M4 + IDE backends are ARCHIVED
# (frozen in-tree, not built or shipped) - see docs/ARCHIVED.md.
build_variant() {                                # $1 = kernel name, $2 = rasm -D flag
    rm -f build/gbkern.dsk                       # save-to-DSK appends; start clean
    "$RASM" kernel/gbkern.asm -eo $2 ${EXTRA_RASM:-} # incbins apps + font + icons -> .dsk + RAW
    "$RASM" kernel/pack_apps.asm -eo             # 2nd pass: overflow apps -> same .dsk (#114)
    "$RASM" kernel/pack_apps2.asm -eo            # 3rd pass: VIEWER + FILEMGR -> same .dsk (#142)
    "$RASM" kernel/pack_apps3.asm -eo            # 4th pass: backdrops/REFINED/pictures -> same .dsk (#198)
    cp build/GBKERN.RAW "build/$1.RAW"           # capture this card's kernel for the unified stage
}
rm -rf QA; mkdir -p QA
# Build the Albireo card kernel + stage QA/CARD (GBALB.BIN + a GB.BAS that RUN"s it).
# M4 + IDE are archived (frozen in-tree, not shipped); to build either for recovery,
# pass -DSTORAGE_M4=1 (or STORAGE=ide) to rasm by hand - see docs/ARCHIVED.md.
echo "Building the Albireo card kernel (GBALB) + the card -> QA/"
build_variant GBALB "-DSTORAGE_ALBIREO=1"
cp build/gbkern.dsk QA/GEOBENCH.DSK               # bootable floppy image (the GBALB kernel)
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
tools/stage_dist.sh QA/CARD                       # GB.BAS (RUN"GBALB) + GBALB.BIN + /GBENCH
# A ready-to-flash card image (partitioned FAT16) for the Albireo CH376 card.
tools/build_card_img.sh QA/CARD QA/GEOBENCH.IMG \
    || echo "  (QA/GEOBENCH.IMG skipped - needs sfdisk + mkfs.fat + mtools)"
echo "  QA/CARD: loose files; QA/GEOBENCH.IMG: Albireo card; QA/GEOBENCH.DSK: floppy (RUN\"GB)"

# Leave build/ as the STORAGE-selected variant (default Albireo) so the --disk-a
# test harness sees a predictable build/gbkern.dsk + build/GBKERN.RAW.
rm -f build/gbkern.dsk
"$RASM" kernel/gbkern.asm -eo $STORAGE_FLAG ${FAT16_FLAG:+$FAT16_FLAG} >/dev/null
"$RASM" kernel/pack_apps.asm -eo >/dev/null      # 2nd pass: overflow apps -> .dsk (#114)
"$RASM" kernel/pack_apps2.asm -eo >/dev/null     # 3rd pass: VIEWER + FILEMGR -> .dsk (#142)
"$RASM" kernel/pack_apps3.asm -eo >/dev/null     # 4th pass: backdrops/REFINED/pictures -> .dsk (#198)
echo "Built QA/CARD (Albireo card deploy) + QA/GEOBENCH.DSK (floppy); build/ = ${STORAGE:-albireo} variant"
