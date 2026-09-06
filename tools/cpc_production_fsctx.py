"""Build the same FSCTX C policy for the CPC F7 module and private M4 checks."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import struct

from check_app_layout import read_areas
from cpc_production_lifetime import physical
from cpc_fsdir_cases import DIRECTORY_VARIANTS, inputs as dir_inputs, files as dir_files, entries as dir_entries

FSCTX_VARIANTS={"fsctx":None,"fsctx-bad-owner":"CPC_FAULT_FS_OWNER", "fsctx-protocol":None, **DIRECTORY_VARIANTS}
TRACE_PAGES=(0xC5,0xC6,0xC7,0xCC)


def inputs(directory=False):
    if directory: return dir_inputs()
    rows=[]
    def add(name,op,handle=0,native=0xC0,drive=0,length=0,payload=b"",save=255):
        rows.append(dict(name=name,op=op,handle=handle,native=native,drive=drive,
                         length=length,payload=payload,save=save,iff=len(rows)%2))
    add("bad-drive",0,drive=1)
    add("root-allocate",0,save=1)
    add("worker-owner-allocate",0,native=0xC4,save=2)
    add("root-path",2,1,payload=b"DOCS/SUB\0")
    add("other-path",2,2,0xC4,payload=b"/ALT\0")
    add("root-name",3,1,payload=b"A       BIN")
    add("other-name",3,2,0xC4,payload=b"B       BIN")
    add("root-read-128",8,1,length=128)
    add("other-read-300",8,2,0xC4,length=300)
    add("root-read-512",8,1,length=512)
    add("other-short-read",8,2,0xC4,length=512)
    add("root-short-read",8,1,length=128)
    add("root-eof",8,1,length=1)
    add("zero-length",8,1)
    add("oversized-read",8,1,length=513)
    add("wrong-owner",8,1,0xC4,length=128)
    add("close-other",1,2,0xC4)
    add("closed-handle",8,2,0xC4,length=128)
    add("reuse-context",0,native=0xC4,save=3)
    add("stale-generation",8,2,0xC4,length=128)
    add("reuse-path",2,3,0xC4,payload=b"ALT\0")
    add("reuse-name",3,3,0xC4,payload=b"B       BIN")
    add("prepare-launch",12,1,payload=b"A       BIN")
    add("adopt-launch",13,native=0xC4,save=4)
    add("adopted-read",8,4,0xC4,length=512)
    add("adopt-once",13,native=0xC4)
    add("fourth-context",0,save=5)
    add("full-contexts",0)
    add("directory-unsupported",5,1)
    add("write-unsupported",9,1,length=2,payload=b"NO")
    add("free-unsupported",10,1)
    add("missing-path",2,1,payload=b"MISSING\0")
    add("failed-activation",4,1)
    add("restore-path",2,1,payload=b"DOCS/SUB\0")
    add("cancel-rewinds",11,1)
    add("read-after-cancel",8,1,length=512)
    add("close-root",1,1)
    add("close-fourth",1,5)
    add("owner-cleanup",255)
    add("cleanup-stale",8,4,0xC4,length=128)
    add("fresh-context",0,save=6)
    add("fresh-path",2,6,payload=b"DOCS/SUB\0")
    add("fresh-name",3,6,payload=b"A       BIN")
    add("fresh-read",8,6,length=128)
    add("final-close",1,6)
    return rows


def files():
    return {"DOCS/SUB/A.BIN":bytes((i*7+3)&255 for i in range(700)),
            "ALT/B.BIN":bytes((255-i*3)&255 for i in range(333))}


def compile_module(work,sym,root,directory=False,fault_metadata=False):
    sdcc=shutil.which(os.environ.get("SDCC","sdcc"))
    if not sdcc: raise RuntimeError("SDCC is required for shared FSCTX policy")
    bindir=Path(sdcc).parent
    sdas=os.environ.get("SDAS",str(bindir/"sdasz80"))
    bridge=".module cpc_fs_bridge\n"
    for name in ("cpc_fs_exchange","cpc_fs_read128"):
        bridge+=f".globl _{name}\n_{name} = {sym[name]}\n"
    (work/"fs_bridge.s").write_text(bridge)
    subprocess.run([sdas,"-o","fs_bridge.rel","fs_bridge.s"],cwd=work,check=True)
    subprocess.run([sdas,"-o","fs_crt.rel",str(root/"lib/gb/crt0.s")],cwd=work,check=True)
    subprocess.run([sdcc,"-mz80","--std-c99","--opt-code-size","--max-allocs-per-node","100000",
                    *(["-DCPC_FS_DIRECTORY"] if directory else []),
                    *(["-DCPC_FAULT_FS_META"] if fault_metadata else []),
                    "--fomit-frame-pointer","-c",str(root/"kernel/kc/gbfsctx_cpc.c"),"-o","fs_mod.rel"],cwd=work,check=True)
    subprocess.run([sdcc,"-mz80","--no-std-crt0","--code-loc","0x4400","--data-loc","0x5F00",
                    "fs_crt.rel","fs_mod.rel","fs_bridge.rel","-o","fs_mod.ihx"],cwd=work,check=True)
    areas=read_areas(work/"fs_mod.map")
    if any(n and not 0x4400<=a<a+n<=0x6000 for a,n in areas.values()):
        raise AssertionError(f"CPC FSCTX module exceeds F7 allocation: {areas}")
    subprocess.run([str(bindir/"makebin"),"-p","fs_mod.ihx","fs_mod.bin"],cwd=work,check=True)
    binary=(work/"fs_mod.bin").read_bytes()[0x4400:]
    if not 0<len(binary)<=0x1B00: raise AssertionError("CPC FSCTX loaded bytes overflow")
    (work/"FSCTX.BIN").write_bytes(binary)
    (work/"fsctx_size.inc").write_text(f"CPC_FS_MODULE_BYTES equ {len(binary)}\n")


def emit_vectors(path,directory=False):
    cases=inputs(directory)
    rows=[f"FP_CASES equ {len(cases)}",f"FP_TRACE_PAGES equ {len(TRACE_PAGES)}","FP_VECTOR_SIZE equ 15","fp_vectors"]
    for i,c in enumerate(cases):
        rows += [f'db {c["op"]},{c["native"]},{c["handle"]},{c["drive"]}',
                 f'dw {c["length"]},fp_payload_{i}',
                 f'db {len(c["payload"])},{c["iff"]},{c["save"]},{i//12}',f'dw {0x4000+(i%12)*1280}', f'db {c.get("flags",0)}']
    for i,c in enumerate(cases):
        rows += [f"fp_payload_{i}"]
        if c["payload"]: rows += ["db "+",".join(map(str,c["payload"]))]
    path.write_text("\n".join(rows)+"\n")


def expected(directory=False):
    """Independent observable model; never used to seed emulator state."""
    contexts=[None]*4
    generations=[0]*4
    handles={0:0}
    pending=bytearray(64)
    rows=[]
    commands=0
    def allocate(owner,drive):
        if drive: return 5,0
        slot=next((i for i,c in enumerate(contexts) if c is None or not c[0]),None)
        if slot is None: return 4,0
        generations[slot]=(generations[slot]+1)%256 or 1
        c=bytearray(144)
        c[:5]=bytes((1,generations[slot],owner&255,owner>>8,drive))
        c[16:27]=b" "*11; c[28]=ord('\\')
        contexts[slot]=c
        return 0,(generations[slot]<<8)|(slot+1)
    for item in inputs(directory):
        op,h=item["op"],handles[item["handle"]]
        owner=0x102 if item["native"]==0xC4 else 0x101
        req=bytearray(32)
        struct.pack_into("<BBHHBBH",req,0,op if op!=255 else 0,0,h,owner if op!=255 else 0xDEAD,
                         item["drive"],item.get("flags",0),item["length"])
        payload=bytearray(b"\xA5"*512)
        payload[:len(item["payload"])]=item["payload"]
        status=0; amount=0
        slot=(h&255)-1
        ctx=contexts[slot] if 0<=slot<4 else None
        if op==255:
            for c in contexts:
                if c and int.from_bytes(c[2:4],"little")==0x102: c[0]=0
        elif op in ((9,10) if directory else (5,6,9,10,14)): status=1
        elif op==0 or op==13:
            if op==13 and not pending[0]: status=2
            else:
                status,new=allocate(owner,pending[3] if op==13 else item["drive"])
                if not status:
                    h=new
                    if op==13:
                        contexts[(h&255)-1][16:27]=pending[4:15]
                        contexts[(h&255)-1][28:76]=pending[16:64]
                        pending[0]=0
        elif ctx is None or not ctx[0] or ctx[1]!=(h>>8): status=2
        elif int.from_bytes(ctx[2:4],"little")!=owner: status=3
        elif op==1: ctx[0]=0
        elif op==2:
            p=item["payload"].split(b"\0",1)[0].replace(b"/",b"\\")
            if not p.startswith(b"\\"): p=b"\\"+p
            ctx[28:29+len(p)]=p+b"\0"
        elif op==3: ctx[16:27]=payload[:11]
        elif op in (7,11): ctx[8:12]=bytes(4)
        elif op==12:
            pending[:4]=bytes((1,owner&255,owner>>8,ctx[4]))
            pending[4:15]=payload[:11]; pending[16:64]=ctx[28:76]
        elif directory and op in (5,6,14):
            length=item["length"] if op==14 else 1
            if op==14 and not 1<=length<=4: status=5
            else:
                path=bytes(ctx[28:76]).split(b"\0",1)[0].decode().replace('\\','/').strip('/')
                commands+=2+len(path.split('/')) if path else 2
                if path not in ("CATALOG","ALT","CATALOG/EIGHTCHR"): status=6
                else:
                    first=(op==5 or (op==14 and item.get("flags",0)))
                    cursor=bytearray(ctx[76:140])
                    normalized='/'+path
                    if first:
                        cursor=bytearray(64);cursor[2]=0xD1
                        cursor[16:17+len(normalized)]=normalized.encode()+b"\0"
                    elif cursor[2]!=0xD1 or cursor[16:].split(b"\0",1)[0]!=normalized.encode(): status=5
                    if not status:
                        ordinal=int.from_bytes(cursor[:2],"little")
                        commands+=1+ordinal  # reset and replay device iterator
                        listing=dir_entries(path)
                        for _ in range(length):
                            commands+=1
                            if ordinal==len(listing): break
                            name,attr,size=listing[ordinal];commands+=1
                            ordinal+=1;cursor[:2]=ordinal.to_bytes(2,"little")
                            ctx[76:140]=cursor
                            if op==14:
                                payload[amount*16:(amount+1)*16]=name+bytes((attr,))+size.to_bytes(4,"little")
                                amount+=1
                            else:
                                payload[:11]=name;req[20]=attr;req[21]=1
                                req[16:20]=size.to_bytes(4,"little")
        elif op in (4,8):
            length=item["length"]
            if op==8 and not 1<=length<=512: status=5
            else:
                path=bytes(ctx[28:76]).split(b"\0",1)[0].decode().replace('\\','/').strip('/')
                commands+=2+len(path.split('/')) if path else 2
                if path not in ("","DOCS","DOCS/SUB","ALT","CATALOG"): status=6
                elif op==8:
                    name=bytes(ctx[16:24]).decode().rstrip()+'.'+bytes(ctx[24:27]).decode().rstrip()
                    source={**files(),**dir_files()}
                    source["CATALOG/LONGNA~1.TXT"]=source["CATALOG/Long named file.txt"]
                    data=source[path+'/'+name]
                    offset=int.from_bytes(ctx[8:12],"little")
                    chunk=data[offset:offset+length]; amount=len(chunk)
                    # Each full requested 128-byte leaf needs no additional EOF read.
                    commands+=4*((amount+127)//128 if amount==length else amount//128+1)
                    payload[:amount]=chunk
                    ctx[8:12]=(offset+amount).to_bytes(4,"little")
                    req[12:16]=ctx[8:12]
        else: status=5
        if item["save"]!=255: handles[item["save"]]=h
        req[1]=status
        struct.pack_into("<H",req,2,h)
        struct.pack_into("<H",req,10,amount)
        table=b"".join(bytes(c) if c else bytes(144) for c in contexts)
        meta=bytes((status,item["native"],item["iff"],1,0,0,0,26-len(TRACE_PAGES)))
        rows.append(bytes(req)+table+bytes(pending)+bytes(payload)+meta)
    return rows,commands


def verify_fsctx(ram,sym,work):
    def require(ok,why):
        if not ok: raise AssertionError("fsctx "+why)
    directory="cpc_fs_directory_enabled" in sym
    rows,commands=expected(directory)
    require(ram[sym["fp_done"]]==len(rows),"checkpoint count")
    for i,want in enumerate(rows):
        at=physical(TRACE_PAGES[i//12])+(i%12)*1280
        actual=ram[at:at+len(want)]
        if actual!=want:
            offset=next(j for j,(a,b) in enumerate(zip(actual,want)) if a!=b)
            raise AssertionError(f'fsctx {inputs(directory)[i]["name"]}: byte {offset} got {actual[offset]:02x} expected {want[offset]:02x}')
        require(ram[at+len(want):at+1280]==b"\xD7"*(1280-len(want)),"trace boundary")
    require(int.from_bytes(ram[sym["fp_commands"]:sym["fp_commands"]+2],"little")==commands,"command accounting")
    require(ram[0x10204]==7,"real worker admission")
    require(ram[sym["core_page_free"]]==26,"trace page reclamation")
    require(ram[sym["core_page_state"]:sym["core_page_state"]+28]==bytes((1,1))+bytes(26),"page leaks")
    require(all(ram[sym["core_fsctx_table"]+i*144]==0 for i in range(4)),"context cleanup")
    for filename,at in (("FSCTX.BIN",0x7C400),("DEFAULT.FNT",0x7C000)):
        data=(work/filename).read_bytes()
        require(ram[at:at+len(data)]==data,"module/font integrity")
    code=(work/"SUPPORT.RAW").read_bytes()
    actual=bytearray(ram[0x400:0x400+len(code)])
    for name,size in (("up_request",16),("up_text_copy",49)):
        at=sym[name]-0x400; actual[at:at+size]=code[at:at+size]
    require(actual==code,"low support integrity")
    require(ram[0xC000:0x10000]==bytes((a>>8)^(a&255) for a in range(0xC000,0x10000)),"unrequested framebuffer write")
    return dict(fsctx_checkpoints=len(rows),fsctx_commands=commands,fsctx_module_bytes=len((work/"FSCTX.BIN").read_bytes()))
