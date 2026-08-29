PYTHON ?= python3

GBR_EXAMPLE_SOURCE := examples/hello-dialog.json
GBR_EXAMPLE_OUTPUT := build/examples/hello-dialog.gbr

.PHONY: all cpc cpc-preemptive cpc-cooperative msx msx-preemptive msx-cooperative msx-preemptive-diagnostic msx-floppies pcw pcw-preemptive pcw-cooperative pcw-preemptive-diagnostic gembench-msx gembench-msx-banked gembench-m7-resident-probe gembench-abi-check gembench-theme-assets gembench-baseline-report gembench-baseline-1983 gembench-baseline-probes-1983 gembench-baseline-input-1983 gembench-baseline-input-openmsx app formref formref-banked sndtest taskdemo titlebar-editor distribution-check-fixtures gbr-check gbevent-check gbregion-check gbscrap-check gbshell-check gbaccessory-check gbr-example check test
.NOTPARALLEL:

all: cpc msx pcw

cpc:
	bash tools/build_kernel.sh

# Compatibility alias: preemptive scheduling is the release default.
cpc-preemptive: cpc

cpc-cooperative:
	PREEMPTIVE=0 bash tools/build_kernel.sh

msx:
	bash tools/build_kernel_msx.sh

# GEMBENCH's fixed-target entry point. Keep the upstream alias during bootstrap.
gembench-msx: msx

# Milestone-7 comparison image: auxiliary mapper resource with the existing
# app-linked renderer. The ordinary release remains embedded/app-linked.
gembench-msx-banked:
	GEMBENCH_M7_BANKED=1 bash tools/build_kernel_msx.sh

gembench-m7-resident-probe:
	bash tools/build_gbr_resident_probe.sh

gembench-abi-check:
	$(PYTHON) tools/check_gembench_abi.py

# Reproduce the MSX2-only four-pen wallpaper from the clean logo source.
gembench-theme-assets:
	$(PYTHON) tools/picconv.py assets/GEMBENCH_LOGO.png \
		assets/msx/GEMLOGO.PIC --gembench -d ordered -w 176 --height 176

# Generate a static report from the staged distribution. The 1983 target adds
# guarded mapper/VRAM boot telemetry plus a desktop screenshot.
gembench-baseline-report: gbr-example
	mkdir -p build/baseline
	$(PYTHON) tools/gembench_baseline.py \
		--markdown build/baseline/gembench-baseline.md \
		--json build/baseline/gembench-baseline.json

gembench-baseline-1983: gembench-msx gbr-example
	$(PYTHON) debug/gembench_baseline_1983.py

# Rebuild with diagnostic-only scheduler and repaint probes, while retaining
# release artifact sizes and hashes from the ordinary baseline capture.
gembench-baseline-probes-1983: gembench-baseline-1983
	cp build/baseline/gembench-baseline.json build/baseline/release-baseline.json
	GEMBENCH_BASELINE=1 PREEMPTIVE=1 PREEMPTIVE_DIAGNOSTIC=1 MSX_UNAPI_TSR= bash tools/build_kernel_msx.sh
	$(PYTHON) debug/gembench_baseline_1983.py \
		--runtime-probes \
		--static-json build/baseline/release-baseline.json

# Inject a real MSX matrix key after the diagnostic image has armed its input
# telemetry. The guest publishes the acknowledgement only after drawing it.
gembench-baseline-input-1983: gembench-baseline-probes-1983
	$(PYTHON) debug/gembench_baseline_1983.py \
		--runtime-probes \
		--input-response \
		--static-json build/baseline/release-baseline.json

# Repeat the reference input run twice. openMSX can drive the cursor-key pointer
# path directly; its results complement 1983's headless keyboard capture.
gembench-baseline-input-openmsx: gembench-baseline-input-1983
	$(PYTHON) debug/gembench_input_openmsx.py

# Compatibility alias: preemptive scheduling is the release default.
msx-preemptive: msx

msx-cooperative:
	PREEMPTIVE=0 bash tools/build_kernel_msx.sh

# Explicit scheduler stress image: stage and auto-open TASKDEMO workers.
msx-preemptive-diagnostic:
	PREEMPTIVE=1 PREEMPTIVE_DIAGNOSTIC=1 bash tools/build_kernel_msx.sh

msx-floppies:
	bash tools/build_msx_floppy.sh

pcw:
	bash tools/build_kernel_pcw.sh

# Compatibility alias: preemptive scheduling is the release default.
pcw-preemptive: pcw

pcw-cooperative:
	PREEMPTIVE=0 bash tools/build_kernel_pcw.sh

# Explicit scheduler stress image: stage and auto-open TASKDEMO workers.
pcw-preemptive-diagnostic:
	PREEMPTIVE=1 PREEMPTIVE_DIAGNOSTIC=1 bash tools/build_kernel_pcw.sh

app:
	@if [ -z "$(APP)" ]; then echo "usage: make app APP=mahjong"; exit 2; fi
	bash tools/rebuild_app.sh "$(APP)"

formref:
	python3 tools/gbrc.py apps/formref/formref.json --output build/msx/FORMREF.GBR --c-header apps/formref/formref_gbr.h --symbol-prefix FORMREF
	APP_ICON=apps/formref/icon.asm APP_ICON16=apps/formref/icon16.asm DATA_LOC=0x6200 WIDGETS=1 STEPPER=1 SELECTOR=1 ACTIONS=1 FORM=1 FORM_SELECT=1 tools/build_capp.sh apps/formref build/FORMREF.RAW
	APP_ICON=apps/formref/icon.asm APP_ICON16=apps/formref/icon16.asm APPDEFS="-DGB_MSX2" APP_CFLAGS="--opt-code-size --max-allocs-per-node 100000" DATA_LOC=0x7E90 WIDGETS=1 FORM=1 FORM_MODAL_ONLY=1 GBR_FORM_ENGINE=1 GBR_FIXED_TREE=1 GBR_EMBEDDED=1 tools/build_capp.sh apps/formref build/msx/FORMREF.RAW
	APP_ICON=apps/formref/icon.asm APP_ICON16=apps/formref/icon16.asm APPDEFS="-DGB_PCW" DATA_LOC=0x6200 WIDGETS=1 STEPPER=1 SELECTOR=1 ACTIONS=1 FORM=1 FORM_SELECT=1 tools/build_capp.sh apps/formref build/pcw/FORMREF.RAW

formref-banked:
	python3 tools/gbrc.py apps/formref/formref-m7.json --output build/msx/FORMREF.GBR --c-header apps/formref/formref_m7_gbr.h --symbol-prefix FORMREF
	APP_ICON=apps/formref/icon.asm APP_ICON16=apps/formref/icon16.asm APPDEFS="-DGB_MSX2 -DGBR_BANKED -DGBR_M7_LEGACY_FORMS -DGEMBENCH_GBR_METADATA_ONLY" APP_CFLAGS="--opt-code-size --max-allocs-per-node 100000" DATA_LOC=0x7E50 WIDGETS=1 FORM=1 FORM_MODAL_ONLY=1 GBR_FORMS=1 GBR_FIXED_TREE=1 GBR_BANKED=1 tools/build_capp.sh apps/formref build/msx/FORMREF.RAW

sndtest:
	DATA_LOC=0x6200 BUTTON=1 SOUND=1 tools/build_capp.sh apps/sndtest build/SNDTEST.RAW
	APPDEFS="-DGB_MSX2" DATA_LOC=0x6200 BUTTON=1 SOUND=1 tools/build_capp.sh apps/sndtest build/msx/SNDTEST.RAW
	APPDEFS="-DGB_PCW" DATA_LOC=0x6200 BUTTON=1 SOUND=1 tools/build_capp.sh apps/sndtest build/pcw/SNDTEST.RAW

# Development-only preemption proof. TASKDEMO's worker never yields, so do not
# run it with an explicit cooperative kernel (PREEMPTIVE_CONTEXT=0).
taskdemo:
	TASK=1 TASK_STACK_RESERVE=256 DATA_LOC=0x6200 tools/build_capp.sh apps/taskdemo build/TASKDEMO.RAW
	TASK=1 TASK_STACK_RESERVE=256 APPDEFS="-DGB_MSX2" DATA_LOC=0x6200 tools/build_capp.sh apps/taskdemo build/msx/TASKDEMO.RAW
	TASK=1 TASK_STACK_RESERVE=256 APPDEFS="-DGB_PCW" DATA_LOC=0x6200 tools/build_capp.sh apps/taskdemo build/pcw/TASKDEMO.RAW

titlebar-editor:
	$(PYTHON) tools/titlebaredit.py assets/titlebars/ORIGINAL.TBR assets/gadgets/ORIGINAL.GDT

gbr-check:
	$(PYTHON) -m unittest discover -s tests -v
	bash tests/run_gbr_reader_tests.sh

gbevent-check:
	bash tests/run_gbevent_tests.sh

gbregion-check:
	bash tests/run_gbregion_tests.sh

gbscrap-check:
	bash tests/run_gbscrap_tests.sh

gbshell-check:
	bash tests/run_gbshell_tests.sh

gbaccessory-check:
	$(PYTHON) tools/gen_desk_accessories.py apps/desktop/accessories.json \
		--output include/gembench/gbdesk_catalog.h --check
	$(PYTHON) tests/test_desk_accessories.py

gbr-example: $(GBR_EXAMPLE_OUTPUT)

$(GBR_EXAMPLE_OUTPUT): $(GBR_EXAMPLE_SOURCE) tools/gbrc.py
	mkdir -p $(dir $@)
	$(PYTHON) tools/gbrc.py $< --output $@

# The distribution audit compares committed QA media with all three generated
# title modules. Produce those small fixtures so `make check` works in a clean
# checkout without requiring a full CPC/MSX/PCW distribution build first.
distribution-check-fixtures:
	bash tools/build_titlebarmod.sh

check: gbr-check gbevent-check gbregion-check gbscrap-check gbshell-check gbaccessory-check gbr-example distribution-check-fixtures
	git diff --check
	$(PYTHON) tools/gen_pic_luts.py --check
	$(PYTHON) tools/test_picconv.py
	$(PYTHON) tools/png2mahjong.py --check assets/katakana.png assets/hiragana.png apps/mahjong/kana.h
	$(PYTHON) tools/check_pic_distribution.py
	$(PYTHON) tools/check_msx_floppies.py
	$(PYTHON) tools/check_lowram_map.py
	$(PYTHON) tools/check_lowram_map.py --profile msx
	$(PYTHON) tools/check_abi_table.py
	$(PYTHON) tools/check_gembench_abi.py
	$(PYTHON) tools/test_app_layout.py
	$(PYTHON) tools/test_appicon.py
	$(PYTHON) tools/test_iconedit_tools.py
	$(PYTHON) tools/test_titlebaredit.py
	bash apps/calculator/run_tests.sh
	kernel/kc/run_tests.sh
	lib/gb/run_tests.sh

test: check
