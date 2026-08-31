# GEOBENCH tools

The active toolchain builds and validates the MSX2 target only. Retired CPC and
PCW tools are available on `archive/cpc-pcw-targets`.

## Distribution and execution

- `build_kernel_msx.sh` — complete MSX2 apps, kernel, assets, card tree, hard
  disk image, and floppy build.
- `build_msx_img.sh` — create the partitioned FAT16 hard-disk image.
- `build_msx_floppy.sh` — create the FAT12 system and extras disks.
- `fetch_msx_deps.sh` — fetch/stage Nextor, openMSXnet, and test-machine inputs.
- `run_msx.sh` — launch the hard-disk image or a supplied floppy in openMSX.
- `rebuild_app.sh` — fast registered MSX2 application rebuild and staging.

## Kernel, modules, and applications

- `build_capp.sh` — build one `-DGB_MSX2` SDCC application with explicit
  optional library profiles and strict code/data/stack limits.
- `build_scheduler.sh` — build the MSX2 fixed-RAM app-worker scheduler.
- `build_cfgmod.sh`, `build_uimod.sh`, `build_appickmod.sh`, `build_webmod.sh`,
  `build_imgmod.sh`, and `build_fsctxmod.sh` — active paged modules.
- `build_titlebarmod.sh` — build the MSX2 title/gadget installer and stage themes.
- `build_secondary.sh` — build application secondary mapper payloads.
- `gblib_subset.py` — derive a per-app trampoline subset from `gblib.s`.
- `embed_app_icon.py` — build/check GBAP application preambles and manifests.

## Resources and assets

- `gbrc.py`, `gbrverify.py` — compile and validate GBR1 resources.
- `picconv.py`, `png2cpc.py` — produce canonical and MSX2-native pictures.
- `packicons.py`, `ist_*` — create and modify canonical icon sets.
- `iconedit.py`, `patternedit.py`, `titlebaredit.py` — interactive asset editors.
- `genfont.py` — generate the default 6×8 font.
- `make_bootsplash.py` — compose the kernel splash from GEOBENCH artwork.
- `png2backdrop.py`, `png2mahjong.py`, `png2catclock.py` — specialized assets.
- `gen_pic_luts.py` — generate MSX2 reversible picture conversion tables.

The name `png2cpc.py` is historical: MSX2 still consumes the canonical
four-pen Mode-1 packing it produces. Its presence does not represent a CPC
build target.

## Checks and emulator workflows

- `check_gembench_abi.py`, `check_geobench_v2_abi.py`, `check_abi_table.py`,
  `check_app_layout.py` — frozen ABI, proposed universal ABI, and binary-layout
  guards.
- `check_lowram_map.py --profile msx` — fixed low-RAM overlap audit.
- `check_pic_distribution.py`, `check_msx_floppies.py` — committed media audits.
- `test_*_openmsx.sh` — target workflows for windows, compositor visibility,
  timers, resources, services, typed scrap, Paint, Settings, and GB-BASIC.
- `gembench_baseline.py` plus `debug/gembench_*` — 1983/openMSX measurement and
  regression capture.

Run the complete host gate with `make check` and the complete target build with
`make geobench-msx`.
