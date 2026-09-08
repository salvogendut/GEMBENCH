"""Delivery boundary for the actual CPC Desktop, separate from parked media."""
import hashlib
import json
import zlib
from pathlib import Path


def check_destination(media, files, directories):
    """Never follow output symlinks or silently retain unrelated CARD contents.

    Rebuilding resets generated files, including configuration. User data belongs
    on a separate copy of the image/card, not inside this generated staging tree.
    """
    media = Path(media)
    for path in (media, media/'CARD', media/'GEOBENCH.IMG', media/'manifest.json', media/'1984.conf'):
        if path.is_symlink():
            raise ValueError('refusing symlinked Desktop output: '+str(path))
    card = media/'CARD'
    if card.exists():
        for path in card.rglob('*'):
            name = path.relative_to(card).as_posix()
            if path.is_symlink() or (name not in directories if path.is_dir() else name not in files):
                raise ValueError('unmanaged Desktop CARD entry; preserve it outside generated media: '+str(path))


def validate(media, *, pristine=False):
    """Verify the explicit delivered profile before running its acceptance test."""
    media = Path(media).resolve()
    manifest = json.loads((media/'manifest.json').read_text())
    if manifest.get('profile') not in ('cpc-desktop-m4-v1', 'cpc-desktop-m4-v2', 'cpc-desktop-m4-v3') or manifest.get('storage') != 'm4':
        raise ValueError('not a CPC Desktop M4 delivery manifest')
    files = manifest['files']
    if {name for name in files if name.endswith('.APP')} != {'GBENCH/CLOCK.APP', 'GBENCH/CALC.APP'}:
        raise ValueError('unexpected Desktop application set')
    if manifest['profile'] == 'cpc-desktop-m4-v1':
        if 'filemgr' in manifest['sections'] or 'GBENCH/FILEMGR.BIN' in files:
            raise ValueError('native File Manager must remain outside Sprint 2 delivery')
    else:
        fm = manifest['sections'].get('filemgr', {})
        if (not fm.get('staged') or not fm.get('private_integration') or
                fm.get('source') != 'apps/filemgr/main.c' or 'GBENCH/FILEMGR.BIN' not in files):
            raise ValueError('build-matched native File Manager is not staged')
    has_settings=manifest['profile']=='cpc-desktop-m4-v3'
    if has_settings:
        setting=manifest['sections'].get('settings',{})
        if (not setting.get('staged') or not setting.get('private_integration') or
                setting.get('source')!='apps/settings/main.c' or
                setting.get('settings')!=['FONT','ICONS','CURSOR','TITLEBAR','GADGETS','BACKDROP'] or
                'GBENCH/SETTINGS.BIN' not in files):
            raise ValueError('build-matched appearance Settings is not staged')
    elif 'settings' in manifest['sections'] or 'GBENCH/SETTINGS.BIN' in files:
        raise ValueError('Settings requires the v3 delivery profile')
    if manifest.get('directories') != ['GBENCH']:
        raise ValueError('diagnostic directories in Desktop delivery')
    if not manifest['sections']['bar'].get('staged') or manifest['sections']['bar']['source'] != 'apps/desktop/main.c':
        raise ValueError('actual shared Desktop is not staged')
    image = media/'GEOBENCH.IMG'
    if Path(manifest['image']).resolve() != image:
        raise ValueError('Desktop image does not belong to its delivery directory')
    check_destination(media, files, manifest['directories'])
    for name, expected in files.items():
        if not name or name.startswith('/') or '..' in Path(name).parts:
            raise ValueError('invalid staged path')
        if hashlib.sha256((media/'CARD'/name).read_bytes()).hexdigest() != expected:
            raise ValueError('staged Desktop file differs: '+name)
    contracts=[]
    if manifest['profile']!='cpc-desktop-m4-v1':contracts.append(('File Manager','FILEMGR.BIN',fm))
    if has_settings:contracts.append(('Settings','SETTINGS.BIN',setting))
    for title,filename,app in contracts:
        payload = (media/'CARD/GBENCH'/filename).read_bytes()
        core = (media/'CARD/CORE.BIN').read_bytes()
        at = app.get('runtime_contract', 0) - 0x8000
        if not 0 < len(payload) <= 0x3800:
            raise ValueError('native '+title+' exceeds its code budget')
        contract = len(payload).to_bytes(2, 'little') + zlib.crc32(payload).to_bytes(4, 'little')
        if (app.get('code_bytes') != len(payload) or
                app.get('code_sha256') != files['GBENCH/'+filename] or
                app.get('contract') != contract.hex() or
                not 0 <= at <= len(core)-6 or core[at:at+6] != contract):
            raise ValueError('native '+title+' does not match the kernel admission contract')
    if pristine and hashlib.sha256(image.read_bytes()).hexdigest() != manifest['image_sha256']:
        raise ValueError('acceptance test requires a freshly built Desktop image')
    return manifest
