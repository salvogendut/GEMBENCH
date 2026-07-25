.PHONY: all cpc msx pcw formref check test
.NOTPARALLEL:

all: cpc msx pcw

cpc:
	bash tools/build_kernel.sh

msx:
	bash tools/build_kernel_msx.sh

pcw:
	bash tools/build_kernel_pcw.sh

formref:
	DATA_LOC=0x6200 WIDGETS=1 SELECTOR=1 FORM=1 FORM_SELECT=1 tools/build_capp.sh apps/formref build/FORMREF.RAW
	APPDEFS="-DGB_MSX2" DATA_LOC=0x6200 WIDGETS=1 SELECTOR=1 FORM=1 FORM_SELECT=1 tools/build_capp.sh apps/formref build/msx/FORMREF.RAW
	APPDEFS="-DGB_PCW" DATA_LOC=0x6200 WIDGETS=1 SELECTOR=1 FORM=1 FORM_SELECT=1 tools/build_capp.sh apps/formref build/pcw/FORMREF.RAW

check:
	git diff --check
	python3 tools/gen_pic_luts.py --check
	python3 tools/test_picconv.py
	python3 tools/png2mahjong.py --check assets/katakana.png assets/hiragana.png apps/mahjong/kana.h
	python3 tools/check_pic_distribution.py
	python3 tools/check_lowram_map.py
	python3 tools/check_lowram_map.py --profile msx
	python3 tools/check_abi_table.py
	kernel/kc/run_tests.sh
	lib/gb/run_tests.sh

test: check
