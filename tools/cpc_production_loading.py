"""M4 launch transaction inputs; loaded bytes, not injected RAM/app entrypoints."""
from __future__ import annotations

from pathlib import Path
import struct
import zlib

from embed_app_icon import (_read_v4_manifest_spec, make_v4_preamble,
                           parse_icon, refresh_v4_crc, v4_preamble_size)
from cpc_production_lifetime import physical
from cpc_graphics_fixture import CURSOR, put_pixel

LOADING_VARIANTS = {"loading": None, "loading-bad-admission": "CPC_FAULT_LOAD_ADMISSION"}
DATA_PHYSICAL = 0x7C000             # reserved F7, deliberately outside owner pool
CASES = ("RETURN", "BADCRC", "VERSION", "IDENTITY", "SEGMENT", "LENGTH", "TRUNC",
         "EMPTY", "HUGE", "MISSING", "BAD/NAME", "MINPAGES", "WINDOW", "WINDOW",
         "NOOWNER", "NOPAGE", "MAXIMUM")


def emit_vectors(path: Path):
    rows = [f"LP_CASES equ {len(CASES)}", "LP_LAUNCH_AS equ 13", "LP_NOOWNER equ 14", "LP_NOPAGE equ 15", "lp_inputs"]
    rows += [f'db "{(name if name not in ("NOOWNER","NOPAGE") else "RETURN"):8s}APP"' for name in CASES]
    path.write_text("\n".join(rows)+"\n")


def packages(sym, root):
    # Native fixture entry increments telemetry and returns. WINDOW also calls
    # the private native registration adapter; this is NOT an SDK app/API claim.
    marker = sym["lp_executed"]
    entry = b"\x21"+struct.pack("<H", marker)+b"\x34\xC9"
    spec = _read_v4_manifest_spec(root/"apps/abiprobe/manifest.json")
    icon = parse_icon(root/"apps/abiprobe/icon.asm")
    def canonical(length):
        pre = make_v4_preamble(icon, spec, length, length)
        body = entry + bytes((i*7+3)&255 for i in range(length-len(pre)-len(entry)))
        return bytes(refresh_v4_crc(bytearray(pre+body)))
    good = canonical(v4_preamble_size(False, 1)+len(entry))
    manifest = int.from_bytes(good[14:16], "little")
    def mutate(offset, value, crc=True):
        b = bytearray(good)
        b[offset] = value
        if crc:
            b[manifest+56:manifest+60] = bytes(4)
            struct.pack_into("<I", b, manifest+56, zlib.crc32(b))
        return bytes(b)
    # Fixed native descriptor resides INSIDE the file at 4040. A null callback
    # avoids claiming public drawing/event services which are not linked yet.
    window = (entry[:-1]+b"\x21\x40\x40\x3E\xB6\xCD"+
              struct.pack("<H", sym["k_wm_managed"])+b"\xC9")
    window = window.ljust(0x40, b"\0") + bytes((40,60,24,40,10,24))
    window += struct.pack("<HHH", 0, 0x4050, 0)+bytes((31,))
    window = window.ljust(0x50, b"\0")+b"Loaded\0"
    minpages=bytearray(good)
    minpages[manifest+32:manifest+34]=bytes((27,27))
    refresh_v4_crc(minpages)
    return {"RETURN.APP": good, "BADCRC.APP": mutate(120,good[120]^1,False),
            "VERSION.APP": mutate(7,5,False), "IDENTITY.APP": mutate(manifest+20,ord('a')),
            "SEGMENT.APP": mutate(manifest+64+7,0x41),
            "LENGTH.APP": mutate(manifest+40,0), "TRUNC.APP":good[:-1],
            "EMPTY.APP":b"", "HUGE.APP": entry+b"\xA5"*(0x3F01-len(entry)),
            "MAXIMUM.APP":canonical(0x3F00), "MINPAGES.APP":bytes(minpages), "WINDOW.APP":window}


def verify_loading(ram: bytes, sym, work: Path):
    def at(name): return ram[sym[name]]
    def require(ok, label):
        if not ok: raise AssertionError("loading "+label)
    require(at("lp_done")==len(CASES), "checkpoints")
    base = DATA_PHYSICAL + sym["cpc_loading_trace"]-0x4000
    rows = [ram[base+i*32:base+(i+1)*32] for i in range(len(CASES))]
    executed=0
    for i, row in enumerate(rows):
        live = i in (12,13)
        if i in (0,12,13,16): executed+=1
        require(row[6]==executed, f"{i} admission/entry count")
        require(row[:6]==bytes((25 if live else 0 if i==15 else 26,3 if live else 2,
                                2 if live else 1,0xC0,0,0)), f"{i} transaction rollback/focus")
        owners=bytes((1,))*8 if i==14 else bytes((1,1,int(live),0,0,0,0,0))
        require(row[7]==i and row[8:16]==owners, f"{i} owner table")
        require(row[22:25]==bytes((int(i not in (14,15)),1,0)), f"{i} IRQ/root lock")
        require(row[26:28]==bytes(2), f"{i} M4 close/offline")
        require(row[30]==0, f"{i} strict one-shot")
        if live:
            require(row[16:20]==bytes((0xC5,3,i+1,19)), f"{i} registered identity")
            require(row[28:30]==bytes((0xC5,3)), f"{i} code page")
            require(row[31]==(ord('D') if i==13 else 0), f"{i} launch argument")
        else:
            require(row[28:30]==bytes(2), f"{i} unpublished code page")
        if i in (0,12,13,16):
            name=CASES[i]+".APP"
            require(int.from_bytes(row[20:22],"little")==len((work/name).read_bytes()), f"{i} exact loaded size")
    require(ram[physical(0xC5)+0x3F00:physical(0xC5)+0x4000]==b"\xD7"*256,"app/context fence")
    last=(work/"MAXIMUM.APP").read_bytes()
    require(ram[physical(0xC5):physical(0xC5)+len(last)]==last,"last file bytes")
    for file,addr in (("SUPPORT.RAW",sym["cpc_support_base"]),("DEFAULT.FNT",DATA_PHYSICAL)):
        code=(work/file).read_bytes()
        observed=bytearray(ram[addr:addr+len(code)])
        if file=="SUPPORT.RAW":
            for name,size in (("up_request",16),("up_text_copy",49)):
                offset=sym[name]-addr
                observed[offset:offset+size]=code[offset:offset+size]
        require(observed==code,"code/font integrity")
    require(ram[sym["core_owner_active"]:sym["core_owner_active"]+8]==bytes((1,1,0,0,0,0,0,0)),"final owners")
    require(at("core_page_free")==26 and ram[sym["core_pending_owner"]:sym["core_pending_owner"]+2]==bytes(2),"final rollback")
    expected=bytearray((a>>8)^(a&255) for a in range(0xC000,0x10000))
    # Last-window cleanup restores the pointer, even with null paint callbacks.
    for y,row in enumerate(CURSOR):
        for x,ch in enumerate(row):
            if ch!=".": put_pixel(expected,x,y,int(ch))
    require(ram[0xC000:0x10000]==expected,"unrequested framebuffer write")
    require(at("pointer_visible")==1 and ram[sym["pointer_x"]:sym["pointer_x"]+3]==bytes(3),"pointer restore")
    require(ram[sym["core_page_state"]:sym["core_page_state"]+28]==bytes((1,1))+bytes(26),"page pool leaks")
    require(ram[sym["core_fsctx_table"]:sym["core_fsctx_table"]+4*144]==bytes(4*144),"reserved FS contexts damaged")
    return {"loading_checkpoints":len(rows), "app_entries":executed,
            "maximum_file_bytes":0x3F00, "loaded_window_registrations":2}


def loading_commands(work):
    return sum(0 if name in ("BAD/NAME","NOOWNER","NOPAGE") else 1 if name=="MISSING" else
               4*(min((work/(name+".APP")).stat().st_size,0x3F00)//128+1) for name in CASES)
