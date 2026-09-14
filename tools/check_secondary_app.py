#!/usr/bin/env python3
"""Restricted computation-only SDK audit, not a malicious-Z80-code sandbox."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from check_universal_app import (check_source, check_generated_asm, source_files, MAP_FILE_RE)

FORBIDDEN_API = re.compile(r'\b(?:gb_\w+|malloc|calloc|realloc|free|exit|printf|puts|putchar|getchar|fopen|fread|fwrite|setjmp|longjmp)\s*\(')
CONTROL = re.compile(r'^\s*(?:di|ei|im|halt|rst|reti|retn)\b', re.M|re.I)
PURE_MODULES = {'crt0_secondary','main','memcpy','memmove','memset','memcmp','strlen',
                'strcpy','strncpy','strcmp','strncmp','mul','div','mod'}
ARITHMETIC_MODULE = re.compile(r'^_?(?:mul|div|mod)(?:u?char|u?int|u?long|schar|sint|slong)$')


def audit(sources, assembly, link_map):
    errors=[]
    for source in source_files(sources):
        check_source(source,errors)
        text=source.read_text()
        if FORBIDDEN_API.search(text): errors.append(f'{source}: kernel/runtime service in computation-only code')
    for asm in assembly:
        check_generated_asm(asm,errors)
        text=asm.read_text()
        if CONTROL.search(text): errors.append(f'{asm}: interrupt/control instruction in leaf')
        if re.search(r'\b_gb_\w+',text): errors.append(f'{asm}: kernel symbol in leaf')
    if link_map:
        modules={m[2].strip() for m in MAP_FILE_RE.finditer(link_map.read_text())}
        if not {'crt0_secondary','main'}<=modules: errors.append('missing restricted secondary startup/main')
        for name in modules:
            if name not in PURE_MODULES and not ARITHMETIC_MODULE.fullmatch(name):
                errors.append(f'{link_map}: unaudited secondary linked module {name}')
    return errors


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,action='append',required=True)
    parser.add_argument('--asm',type=Path,action='append',default=[])
    parser.add_argument('--map',type=Path)
    parser.add_argument('--binary',type=Path)
    args=parser.parse_args()
    if args.binary and (not args.asm or not args.map):
        parser.error('--binary requires generated --asm and the linked --map')
    errors=audit(args.source,args.asm,args.map)
    if args.binary:
        data=args.binary.read_bytes()
        if not (9<=len(data)<=0x3F00 and data[:1]==b'\xC3' and data[3:8]==b'GBS4\1' and
                0x4008<=int.from_bytes(data[1:3],'little')<0x4000+len(data)):
            errors.append('invalid bounded GBS4 secondary image')
    if errors: raise SystemExit('\n'.join(errors))
    if args.binary:
        args.binary.with_suffix(args.binary.suffix+'.audit.json').write_text(json.dumps({
            'profile':'gbs4-computation-v1','sha256':hashlib.sha256(data).hexdigest(),
            'sources':[str(p) for p in args.source]},indent=2)+'\n')
    print('restricted secondary audit: PASS')


if __name__=='__main__':main()
