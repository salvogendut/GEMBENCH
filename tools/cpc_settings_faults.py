"""Disk-only Settings fixtures. Never modify accepted or mounted media."""
import os
from pathlib import Path
import shutil
import subprocess
import zlib

CASES = ('empty-icons', 'malformed-icons', 'long-backdrops', 'directory-error',
         'read-error', 'config-oversized', 'config-nul', 'config-full', 'write-denied',
         'readback-error', 'contexts', 'stress')


def prepare(case, root, work, image, artifacts, extras):
    if image.is_symlink() or image.resolve() != (artifacts/'RUNTIME.IMG').resolve():
        raise ValueError('faults require a disposable artifact image')
    target = ['-i', str(image)+'@@16384']
    removed = set()
    result = dict(removed=removed)
    def put(name, raw):
        path = artifacts/('fixture-'+name.split('/')[-1]); path.write_bytes(raw)
        subprocess.run(['mcopy', '-o', *target, str(path), '::/'+name], check=True)
        extras[name] = raw
    if case == 'empty-icons':
        for path in (work/'DEFAULT.IST', work/'REFINED.IST'):
            name = 'GBENCH/'+path.name
            subprocess.run(['mdel', *target, '::/'+name], check=True)
            removed.add(name)
    if case == 'malformed-icons':
        good = (work/'REFINED.IST').read_bytes()[:16]
        for name, raw in (('SHORT.IST', good[:15]), ('BADMAGIC.IST', b'NOPE'+good[4:]),
                          ('BADCOUNT.IST', good[:5]+b'\x14'+good[6:])):
            put('GBENCH/'+name, raw)
    if case == 'long-backdrops':
        # More than the 16-entry cap, all with maximal eight-character stems.
        for i in range(20):
            put(f'GBENCH/TILE{i:04}.BDP', (root/'assets/backdrops/waves.BDP').read_bytes())
    if case == 'directory-error':
        # A legal FAT long name exceeds the bounded M4 directory response.
        put('GBENCH/'+'L'*70+'.TXT', b'long directory entry\r\n')
    if case == 'read-error':
        put('GBENCH/BROKEN.IST', b'GBIS\x01\x15'+bytes(10))
        sdcc = shutil.which(os.environ.get('SDCC', 'sdcc')); bindir = Path(sdcc).parent
        subprocess.run([sdcc, '-mz80', '--opt-code-size', '--fomit-frame-pointer',
                        '-DGB_PREEMPTIVE', '-I', str(root/'lib/gb'),
                        '-I', str(root/'include/gembench'),
                        f'-DGB_FSCTX_PLATFORM_HEADER="{work/"cpc_fs_client.h"}"',
                        '-c', str(root/'tests/cpc_settings_asset_fault.c'), '-o', 'fault.rel'],
                       cwd=artifacts, check=True)
        objects=['crt','main','provider','selector','ui','gblib','sys','kind','repaint','native_fs']
        subprocess.run([sdcc, '-mz80', '--no-std-crt0', '--code-loc', '0x4000',
                        '--data-loc', '0x7800', *[str(work/'settings'/(n+'.rel')) for n in objects],
                        'fault.rel', '-o', 'settings.ihx'], cwd=artifacts, check=True)
        from check_app_layout import read_areas, LOADED_AREAS
        for area, (at, size) in read_areas(artifacts/'settings.map').items():
            lo, hi = (0x4000, 0x7800) if area in LOADED_AREAS else (0x7800, 0x7F00)
            if size and not lo <= at < at+size <= hi: raise AssertionError('fault Settings overflow')
        subprocess.run([str(bindir/'makebin'), '-s', '65536', '-p', 'settings.ihx', 'settings.bin'],
                       cwd=artifacts, check=True)
        raw=(artifacts/'settings.bin').read_bytes()[0x4000:]
        put('GBENCH/SETTINGS.BIN',raw)
        from build_cpc_runtime import symbols
        sym=symbols(work/'runtime.sym');at=sym['cpc_settings_contract']-0x8000
        kernel=(work/'CORE.RAW').read_bytes()
        kernel=kernel[:at]+len(raw).to_bytes(2,'little')+zlib.crc32(raw).to_bytes(4,'little')+kernel[at+6:]
        put('CORE.BIN',kernel)
        result.update(kernel=kernel,settings_raw=raw,settings_noi=artifacts/'settings.noi')
    if case in ('config-oversized', 'config-nul', 'config-full'):
        cfg = subprocess.check_output(['mtype', *target, '::/GEOBENCH.CFG'])
        cfg += b'#\0bad\r\n' if case == 'config-nul' else b'#'*((512 if case=='config-full' else 513)-len(cfg))
        put('GEOBENCH.CFG', cfg)
    if case == 'write-denied':
        subprocess.run(['mattrib', *target, '+r', '::/GEOBENCH.CFG'], check=True)
    if case == 'readback-error':
        # Explicit test-only client: the actual module writes through M4, then
        # receives one corrupted byte on its verification read. No guest RAM
        # injection and no change to the shipped module or emulator.
        sdcc = shutil.which(os.environ.get('SDCC', 'sdcc'))
        bindir = Path(sdcc).parent
        subprocess.run([sdcc, '-mz80', '--opt-code-size', '--fomit-frame-pointer',
                        '-I', str(root/'include/gembench'),
                        '-I', str(root/'lib/gb'),
                        f'-DGB_FSCTX_PLATFORM_HEADER="{work/"cpc_fs_client.h"}"',
                        '-c', str(root/'tests/cpc_settings_readback_fault.c'),
                        '-o', 'fault.rel'], cwd=artifacts, check=True)
        subprocess.run([sdcc, '-mz80', '--no-std-crt0', '--code-loc', '0x4000',
                        '--data-loc', '0x5800', str(work/'native_crt.rel'),
                        str(work/'native_edit.rel'), 'fault.rel', str(work/'native_fs.rel'),
                        '-o', 'fault.ihx'], cwd=artifacts, check=True)
        from check_app_layout import read_areas, LOADED_AREAS
        for area, (at, size) in read_areas(artifacts/'fault.map').items():
            lo, hi = (0x4000, 0x5800) if area in LOADED_AREAS else (0x5800, 0x5B00)
            if size and not lo <= at < at+size <= hi: raise AssertionError('fault module overflow')
        subprocess.run([str(bindir/'makebin'), '-s', '65536', '-p', 'fault.ihx', 'fault.bin'],
                       cwd=artifacts, check=True)
        put('GBENCH/GBEDIT.MOD', (artifacts/'fault.bin').read_bytes()[0x4000:].ljust(6144, b'\0'))
    return result
