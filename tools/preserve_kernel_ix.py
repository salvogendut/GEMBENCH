#!/usr/bin/env python3
"""Generate IX-preserving universal trampolines; do not alter native sources.

Wrap only fixed jump-table calls AFTER argument marshalling. A tail JP becomes
a CALL/restore/RET. No application call, register jump or stack offset changes.
"""
import re
import sys
from pathlib import Path

def generate(text):
    pattern=re.compile(r'^(\s*)(call|jp)\s+(0x[0-9A-Fa-f]+)([^\n]*)$',re.M)
    def replace(m):
        address=int(m[3],16)
        if not 0x8000<=address<=0x80D5 or (address-0x8000)%3:
            raise ValueError(f'not a frozen kernel vector: {m[3]}')
        return (f'        push ix\n        call {m[3]}{m[4]}\n        pop ix'+
                ('\n        ret' if m[2]=='jp' else ''))
    return pattern.sub(replace,text)

if __name__=='__main__':
    source,destination=map(Path,sys.argv[1:])
    destination.write_text(generate(source.read_text()))
