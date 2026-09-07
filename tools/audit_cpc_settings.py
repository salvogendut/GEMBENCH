#!/usr/bin/env python3
"""Compile the actual Settings source and inventory unbound CPC requirements.

This is intentionally not a linker/packager. It produces a relocatable object
and an audit report, never executable media or a permissive runtime profile.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

# Every external reference in the real application must have a reviewed class.
# "shared" does not mean linked/qualified in a native Settings APP: its helper
# allocations and callbacks are still required. Hardware-backed operations are
# deliberately listed by their native SDK names, not reimplemented as no-ops.
GROUPS = {
    'native_filesystem_binding_required': (
        'gb_back', 'gb_chdir', 'gb_dir1', 'gb_dirn', 'gb_drives', 'gb_entname',
        'gb_fs_load', 'gb_fs_save', 'gb_get_drive', 'gb_isdir', 'gb_set_drive', 'gb_set_name'),
    'native_asset_binding_required': ('gb_reload', 'gb_titlebar_install', 'gb_gadgets_install'),
    'modal_provider_allocation_required': ('gb_alert', 'gb_popup'),
    'shared_widgets': ('gb_select', 'gb_select_hit', 'gb_stepper', 'gb_stepper_hit',
                       'gb_actions', 'gb_actions_hit'),
    'shared_window_and_drawing': (
        'gb_wm_x', 'gb_wm_y', 'gb_wm_w', 'gb_wm_h', 'gb_wm_managed', 'gb_wm_close',
        'gb_wm_damage', 'gb_wm_setpos', 'gb_restore_parent', 'gb_drag_window',
        'gb_fill', 'gb_frame', 'gb_textbw', 'gb_restorerect', 'gb_mx', 'gb_my',
        'gb_curhide', 'gb_curshow', 'gb_getkey'),
    'platform_storage_required': (
        'settings_font_name', 'settings_icon_name', 'settings_cursor_name',
        'settings_backdrop_name', 'settings_config_text', 'settings_config_length',
        'settings_backdrop_solid', 'settings_backdrop_drive', 'settings_backdrop_tile',
        'settings_inks', 'settings_framepen', 'settings_saver_op', 'settings_saver_result',
        'settings_saver_text', 'settings_saver_modname', 'settings_copybuf',
        'settings_storage_claim', 'settings_message'),
    'platform_calls_required': ('settings_set_ink', 'settings_run_saver'),
    'compiler_runtime': ('_divuint', '_moduchar', '_divuchar', '_mulint', '_moduint'),
}


def inspect_object(text, assembly):
    refs = set(re.findall(r'^S (_\w+) Ref[0-9A-Fa-f]+$', text, re.M))
    if not refs:
        raise ValueError('Settings object has no external requirements')
    classified = {group: sorted('_'+name for name in names if '_'+name in refs)
                  for group, names in GROUPS.items()}
    known = {name for names in classified.values() for name in names}
    if refs - known:
        raise ValueError('unreviewed Settings dependencies: '+', '.join(sorted(refs-known)))
    # A provider must leave address binding to relocation. Direct native RAM or
    # firmware accesses in main would bypass the requirement inventory entirely.
    instructions = '\n'.join(line.split(';', 1)[0] for line in assembly.splitlines()
                             if not line.lstrip().startswith('.'))
    if re.search(r'\b(?:call|jp)\s+(?:(?:nz|z|nc|c|po|pe|p|m),\s*)?'
                 r'(?:#?0x[0-9a-f]+|#?[0-9]+)(?=\s|$)|'
                 r'\(\s*(?:#?0x[0-9a-f]+|#?[0-9]+)\s*\)', instructions, re.I):
        raise ValueError('absolute service/state access bypasses Settings provider')
    areas = {name: int(size, 16) for name, size in
             re.findall(r'^A (_\w+) size ([0-9A-Fa-f]+) flags ', text, re.M)}
    if not areas.get('_CODE') or not areas.get('_DATA'):
        raise ValueError('missing Settings code/data areas')
    return areas, classified


def audit(work, sdcc=None):
    compiler = shutil.which(sdcc or os.environ.get('SDCC', 'sdcc'))
    if not compiler:
        raise RuntimeError('SDCC required for the Settings portability audit')
    work = Path(work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    source = ROOT/'apps/settings/main.c'
    provider = ROOT/'apps/settings/platform/unbound.h'
    subprocess.run([compiler, '-mz80', '--std-c99', '--fomit-frame-pointer',
                    '--opt-code-size', '--max-allocs-per-node', '100000',
                    '-DGB_PREEMPTIVE', '-DGB_CPC_RESTART',
                    f'-DGB_SETTINGS_PROVIDER="{provider}"',
                    '-I', str(ROOT/'lib/gb'), '-c', str(source),
                    '-o', str(work/'settings.rel')], check=True)
    areas, requirements = inspect_object((work/'settings.rel').read_text(),
                                        (work/'settings.asm').read_text())
    # This is the application's own data, not a final linked-layout assertion.
    # Provider storage, helper data, CRT, alignment and code are additional.
    data_bytes = sum(areas.get(name, 0) for name in ('_DATA', '_INITIALIZED', '_BSS'))
    report = {
        'status': 'compile-only; native Settings launch remains disabled',
        'source': 'apps/settings/main.c', 'profile': 'CPC 320x200, preemptive',
        'executable': False, 'areas': areas, 'requirements': requirements,
        'application_data_bytes': data_bytes,
        'cpc_snapshot_base': 0x7F00,
        'latest_possible_data_base_before_helpers': 0x7F00-data_bytes,
        'legacy_data_base': 0x7C40,
        'legacy_data_overrun_bytes': max(0, 0x7C40+data_bytes-0x7F00),
        'legacy_copy_buffer_bytes': 0x1A00,
        'remaining': [
            'native package admission and complete linked memory layout',
            'owned filesystem facade and bounded IST header reads',
            'verified persistence/publication using W1 (not legacy best-effort save)',
            'paged popup/save-under and native title/gadget/palette services',
            'separate saver module dispatch and desktop-owned settings',
            'M4 runtime qualification before enabling launch'],
    }
    (work/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        help='keep relocatable object/assembly/report here; never an APP')
    args = parser.parse_args()
    if args.output:
        report = audit(args.output)
    else:
        with tempfile.TemporaryDirectory(prefix='cpc-settings-audit-') as tmp:
            report = audit(tmp)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
