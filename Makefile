.PHONY: all cpc cpc-preemptive msx msx-preemptive msx-preemptive-diagnostic msx-floppies pcw pcw-preemptive pcw-preemptive-diagnostic app formref sndtest taskdemo titlebar-editor check test
.NOTPARALLEL:

all: cpc msx pcw

cpc:
	bash tools/build_kernel.sh

# Development image with the desktop-carried scheduler and CPC firmware IRQ
# hook. It works with floppy, Albireo, and M4 kernels and requires no ROM.
cpc-preemptive:
	PREEMPTIVE=1 bash tools/build_kernel.sh

msx:
	bash tools/build_kernel_msx.sh

# Development image with the desktop-carried scheduler. Diagnostics are not
# staged or launched.
msx-preemptive:
	PREEMPTIVE=1 bash tools/build_kernel_msx.sh

# Explicit scheduler stress image: stage and auto-open TASKDEMO workers.
msx-preemptive-diagnostic:
	PREEMPTIVE=1 PREEMPTIVE_DIAGNOSTIC=1 bash tools/build_kernel_msx.sh

msx-floppies:
	bash tools/build_msx_floppy.sh

pcw:
	bash tools/build_kernel_pcw.sh

# Development image with the PCW 300 Hz timer adapter. Diagnostics are not
# staged or launched.
pcw-preemptive:
	PREEMPTIVE=1 bash tools/build_kernel_pcw.sh

# Explicit scheduler stress image: stage and auto-open TASKDEMO workers.
pcw-preemptive-diagnostic:
	PREEMPTIVE=1 PREEMPTIVE_DIAGNOSTIC=1 bash tools/build_kernel_pcw.sh

app:
	@if [ -z "$(APP)" ]; then echo "usage: make app APP=mahjong"; exit 2; fi
	bash tools/rebuild_app.sh "$(APP)"

formref:
	APP_ICON=apps/formref/icon.asm APP_ICON16=apps/formref/icon16.asm DATA_LOC=0x6200 WIDGETS=1 STEPPER=1 SELECTOR=1 ACTIONS=1 FORM=1 FORM_SELECT=1 tools/build_capp.sh apps/formref build/FORMREF.RAW
	APP_ICON=apps/formref/icon.asm APP_ICON16=apps/formref/icon16.asm APPDEFS="-DGB_MSX2" DATA_LOC=0x6200 WIDGETS=1 STEPPER=1 SELECTOR=1 ACTIONS=1 FORM=1 FORM_SELECT=1 tools/build_capp.sh apps/formref build/msx/FORMREF.RAW
	APP_ICON=apps/formref/icon.asm APP_ICON16=apps/formref/icon16.asm APPDEFS="-DGB_PCW" DATA_LOC=0x6200 WIDGETS=1 STEPPER=1 SELECTOR=1 ACTIONS=1 FORM=1 FORM_SELECT=1 tools/build_capp.sh apps/formref build/pcw/FORMREF.RAW

sndtest:
	DATA_LOC=0x6200 BUTTON=1 SOUND=1 tools/build_capp.sh apps/sndtest build/SNDTEST.RAW
	APPDEFS="-DGB_MSX2" DATA_LOC=0x6200 BUTTON=1 SOUND=1 tools/build_capp.sh apps/sndtest build/msx/SNDTEST.RAW
	APPDEFS="-DGB_PCW" DATA_LOC=0x6200 BUTTON=1 SOUND=1 tools/build_capp.sh apps/sndtest build/pcw/SNDTEST.RAW

# Development-only preemption proof. TASKDEMO's worker never yields, so do not
# run it with a normal release kernel (PREEMPTIVE_CONTEXT=0).
taskdemo:
	TASK=1 TASK_STACK_RESERVE=256 DATA_LOC=0x6200 tools/build_capp.sh apps/taskdemo build/TASKDEMO.RAW
	TASK=1 TASK_STACK_RESERVE=256 APPDEFS="-DGB_MSX2" DATA_LOC=0x6200 tools/build_capp.sh apps/taskdemo build/msx/TASKDEMO.RAW
	TASK=1 TASK_STACK_RESERVE=256 APPDEFS="-DGB_PCW" DATA_LOC=0x6200 tools/build_capp.sh apps/taskdemo build/pcw/TASKDEMO.RAW

titlebar-editor:
	python3 tools/titlebaredit.py assets/titlebars/ORIGINAL.TBR assets/gadgets/ORIGINAL.GDT

check:
	git diff --check
	python3 tools/gen_pic_luts.py --check
	python3 tools/test_picconv.py
	python3 tools/png2mahjong.py --check assets/katakana.png assets/hiragana.png apps/mahjong/kana.h
	python3 tools/check_pic_distribution.py
	python3 tools/check_msx_floppies.py
	python3 tools/check_lowram_map.py
	python3 tools/check_lowram_map.py --profile msx
	python3 tools/check_abi_table.py
	python3 tools/test_app_layout.py
	python3 tools/test_appicon.py
	python3 tools/test_iconedit_tools.py
	python3 tools/test_titlebaredit.py
	bash apps/calculator/run_tests.sh
	kernel/kc/run_tests.sh
	lib/gb/run_tests.sh

test: check
