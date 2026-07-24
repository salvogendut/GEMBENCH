.PHONY: all cpc msx pcw check test
.NOTPARALLEL:

all: cpc msx pcw

cpc:
	bash tools/build_kernel.sh

msx:
	bash tools/build_kernel_msx.sh

pcw:
	bash tools/build_kernel_pcw.sh

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
