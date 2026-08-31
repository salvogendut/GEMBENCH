# GB-BASIC — GEOBENCH's MSX2 GW-BASIC-style BASIC.
# Deliverable: dist/GBBASIC-MSX.DSK.
GEOBENCH ?= ../..
export GEOBENCH

BASIC_ICON := apps/basic/icon.asm

.PHONY: all msx raws-msx dsk-msx qa-msx clean

all: msx

# --- MSX ---------------------------------------------------------------------
raws-msx:
	APP_ICON=$(BASIC_ICON) APPDEFS=-DGB_MSX2 DOC=1 DATA_LOC=0x6BF0 bash tools/build_app.sh apps/basic build/msx/BASIC.RAW
	MSX2=1 bash tools/build_engine.sh build/msx/BASRUN2.BIN
	APPDEFS="-DGB_MSX2 -DBUILTIN_OFF" NOGBWIN=1 DATA_LOC=0x7F40 bash tools/build_app.sh apps/basrun build/msx/BASRUN.RAW

dsk-msx: raws-msx
	bash tools/build_msx_dsk.sh

msx: dsk-msx

qa-msx: msx
	bash tools/run_msx.sh

clean:
	rm -rf build dist
