#!/usr/bin/env python3
"""Build the private opt-in MSX stream module set; never stage release media."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def compose(parts):
    """Validate the versioned fixed-layout parts before creating a boot image."""
    checks = [('GBAPV4.RAW', 3014, b'GBV4\x05'),
              ('GBPKIO.RAW', 293, b'GBIO\x03'),
              ('GBDPAGE.RAW', 492, b'GBDP\x01'),
              ('GBPKLOAD.RAW', 747, b'GBPK\x02')]
    for name, size, signature in checks:
        data = parts[name]
        if len(data) != size or data[0] != 0xC3 or data[3:8] != signature:
            raise ValueError(f'{name}: wrong size or module version')
    crc = parts['GBPKCRC.RAW']
    extra = parts['GBPKEX.RAW']
    if len(crc) != 186 or not extra or len(extra) > 0xD3F0-0xD3A6:
        raise ValueError('CRC/extra helpers overlap their fixed slots')
    high = parts['GBPKIO.RAW'] + parts['GBDPAGE.RAW'] + crc + extra
    high = high.ljust(0xD400-0xCFDB, b'\0')
    return {'GBAPV4.MOD': parts['GBAPV4.RAW'], 'GBPKFIX.MOD': high,
            'GBPKLOAD.MOD': parts['GBPKLOAD.RAW']}


def build(output):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for source in ('msx_gbap4', 'msx_data_pages', 'msx_package'):
        subprocess.run([os.environ.get('RASM', 'rasm'), str(ROOT/f'kernel/{source}.asm'),
                        '-DPORTABLE_DATA_PAGES=1', '-DPORTABLE_PACKAGE_STREAM=1',
                        '-s', '-sq', '-o', source], cwd=output, check=True)
    parts = {name: (output/name).read_bytes() for name in
             ('GBAPV4.RAW', 'GBPKIO.RAW', 'GBDPAGE.RAW', 'GBPKLOAD.RAW', 'GBPKCRC.RAW', 'GBPKEX.RAW')}
    for name, data in compose(parts).items():
        (output/name).write_bytes(data)
        print(f'{name}: {len(data)} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    build(parser.parse_args().out)
