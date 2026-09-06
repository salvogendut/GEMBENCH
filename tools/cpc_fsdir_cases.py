"""Inputs and independent file metadata for the private shared directory gate."""
from cpc_fsdir_protocol import BIG_SIZE

DIRECTORY_VARIANTS = {"fsctx-directory": None, "fsctx-directory-bad-meta": "CPC_FAULT_FS_META"}


def files():
    return {"CATALOG/BIG.BIN": bytes((i*13+11)&255 for i in range(BIG_SIZE)),
            "CATALOG/Long named file.txt": b"long-name alias\n",
            "CATALOG/TAIL.BIN": b""}


def entries(path):
    return {"CATALOG": [(b"EIGHTCHR   ",0x10,0), (b"BIG     BIN",0x27,BIG_SIZE),
                         (b"LONGNA~1TXT",0x20,16), (b"TAIL    BIN",0x20,0)],
            "ALT": [(b"B       BIN",0x20,333)], "CATALOG/EIGHTCHR": []}[path]


def inputs():
    rows=[]
    def add(name,op,handle=0,native=0xC0,drive=0,length=0,payload=b"",save=255,flags=0):
        rows.append(dict(name=name,op=op,handle=handle,native=native,drive=drive,
                         length=length,payload=payload,save=save,flags=flags,iff=len(rows)%2))
    add("root-allocate",0,save=1)
    add("other-allocate",0,native=0xC4,save=2)
    add("root-path",2,1,payload=b"CATALOG\0")
    add("other-path",2,2,0xC4,payload=b"ALT\0")
    add("next-without-first",6,1)
    add("root-first-directory",5,1)
    add("other-first-file",5,2,0xC4)
    add("root-next-large",6,1)
    add("root-batch-tail",14,1,length=4)
    add("other-eof",6,2,0xC4)
    add("root-eof",6,1)
    add("root-batch-restart",14,1,length=2,flags=1)
    add("wrong-owner",6,1,0xC4)
    add("batch-zero",14,1)
    add("batch-oversized",14,1,length=5)
    add("empty-path",2,1,payload=b"CATALOG/EIGHTCHR\0")
    add("changed-path-next",6,1)
    add("empty-first",5,1)
    add("restore-path",2,1,payload=b"CATALOG\0")
    add("restart-first",5,1)
    add("name-large",3,1,payload=b"BIG     BIN")
    add("interleaved-read",8,1,length=128)
    add("next-after-read",6,1)
    add("name-alias",3,1,payload=b"LONGNA~1TXT")
    add("rewind-file",7,1)
    add("read-by-short-alias",8,1,length=128)
    add("batch-after-read",14,1,length=4)
    add("close-root",1,1)
    add("closed-handle",6,1)
    add("reuse-root",0,save=3)
    add("reuse-path",2,3,payload=b"CATALOG\0")
    add("stale-generation",5,1)
    add("reuse-first",5,3)
    add("owner-cleanup",255)
    add("cleaned-other",6,2,0xC4)
    add("full-batch",14,3,length=4,flags=1)
    add("batch-eof",14,3,length=4)
    add("missing-path",2,3,payload=b"MISSING\0")
    add("activation-error",5,3)
    add("final-root-close",1,3)
    add("fresh-other",0,native=0xC4,save=4)
    add("fresh-path",2,4,0xC4,payload=b"ALT\0")
    add("fresh-first",5,4,0xC4)
    add("final-other-close",1,4,0xC4)
    return rows
