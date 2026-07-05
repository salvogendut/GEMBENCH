.PHONY: all cpc msx check test
.NOTPARALLEL:

all: cpc msx

cpc:
	bash tools/build_kernel.sh

msx:
	bash tools/build_kernel_msx.sh

check:
	git diff --check
	python3 tools/check_lowram_map.py
	python3 tools/check_abi_table.py
	kernel/kc/run_tests.sh

test: check
