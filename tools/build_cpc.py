#!/usr/bin/env python3
"""Build the M4 Desktop/File Manager/Settings target, preserving parked QA/CPC."""
from build_cpc_runtime import build
from cpc_desktop_media import validate


if __name__ == '__main__':
    media = build(desktop=True, filemgr=True, settings=True, delivery=True)
    validate(media, pristine=True)
    print('CPC Desktop built: '+str(media))
    print('Run: bash tools/run_cpc.sh (Disk C opens the native File Manager)')
    print('System > Settings: font, icons, cursor, title bar, gadgets and backdrop')
