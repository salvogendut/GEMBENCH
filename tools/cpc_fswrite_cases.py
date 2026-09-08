"""Private write/free inputs and read-only FAT16/mtools media observations."""
import struct
import subprocess

WRITE_VARIANTS={"fsctx-write":None,"fsctx-write-bad-append":"CPC_FAULT_FS_APPEND"}


def inputs():
    rows=[]
    def add(name,op,handle=0,native=0xC0,drive=0,length=0,payload=b"",save=255,flags=0):
        rows.append(dict(name=name,op=op,handle=handle,native=native,drive=drive,
                         length=length,payload=payload,save=save,flags=flags,iff=len(rows)%2))
    add("root-allocate",0,save=1)
    add("other-allocate",0,native=0xC4,save=2)
    add("root-path",2,1,payload=b"DOCS/SUB\0")
    add("other-path",2,2,0xC4,payload=b"ALT\0")
    add("root-name",3,1,payload=b"OUT     BIN")
    add("other-name",3,2,0xC4,payload=b"OUT     BIN")
    add("free-before",10,1)
    add("root-write-512",9,1,length=512,payload=b"ROOT-512")
    add("other-write-129",9,2,0xC4,length=129,payload=b"OTHER-129")
    add("root-append-129",9,1,length=129,payload=b"ROOT-129")
    add("root-rewind",7,1)
    add("root-read-512",8,1,length=512)
    add("other-append-300",9,2,0xC4,length=300,payload=b"OTHER-300")
    add("root-read-tail",8,1,length=512)
    add("root-rewind-again",7,1)
    add("root-read-one",8,1,length=1)
    add("append-after-read",9,1,length=1,payload=b"!")
    add("zero-append",9,1)
    add("directory-first",5,1)
    add("directory-written-size",6,1)
    add("oversized-write",9,1,length=513)
    add("wrong-owner-write",9,1,0xC4,length=1,payload=b"X")
    add("missing-path",2,1,payload=b"MISSING\0")
    add("activation-error",9,1,length=1,payload=b"X")
    add("restore-path",2,1,payload=b"DOCS/SUB\0")
    add("other-rewind",7,2,0xC4)
    add("other-readback",8,2,0xC4,length=512)
    add("root-truncate-rewind",7,1)
    add("zero-truncate",9,1)
    add("free-after-truncate",10,1)
    add("directory-restart",5,1)
    add("directory-empty-size",6,1)
    add("other-empty-name",3,2,0xC4,payload=b"EMPTY   BIN")
    add("other-cancel",11,2,0xC4)
    add("zero-create",9,2,0xC4)
    add("free-after-empty",10,2,0xC4)
    add("root-close",1,1)
    add("closed-write",9,1,length=1,payload=b"X")
    add("owner-cleanup",255)
    add("cleaned-write",9,2,0xC4,length=1,payload=b"X")
    add("fresh-root",0,save=3)
    add("fresh-path",2,3,payload=b"DOCS/SUB\0")
    add("untouched-name",3,3,payload=b"A       BIN")
    add("untouched-read",8,3,length=128)
    add("final-close",1,3)
    return rows


def space(image):
    """Independent read-only oracle for our generated FAT16 fixture, not a driver."""
    data=image.read_bytes()
    if len(data)<512: raise AssertionError('missing M4 image header')
    base=struct.unpack_from('<I',data,454)[0]*512
    if base+512>len(data): raise AssertionError('missing FAT volume')
    bps,spc,reserved,fats,roots,total,_,spf=struct.unpack_from('<HBHBHHBH',data,base+11)
    if bps!=512 or not spc or not reserved or not fats or not spf:
        raise AssertionError('invalid FAT16 geometry')
    if not total: total=struct.unpack_from('<I',data,base+32)[0]
    root_sectors=(roots*32+bps-1)//bps
    count=(total-reserved-fats*spf-root_sectors)//spc
    if bps!=512 or not 4085<=count<65525 or spc*bps%1024:
        raise AssertionError('write oracle requires generated FAT16/KiB-aligned clusters')
    fat=base+reserved*bps
    if (count+2)*2>spf*bps or base+total*bps>len(data):
        raise AssertionError('truncated FAT16 volume/table')
    free=sum(struct.unpack_from('<H',data,fat+c*2)[0]==0 for c in range(2,count+2))
    return free*spc*bps//1024,spc*bps//1024


def verify_media(image,expected_files,original_files):
    # mtype independently reads files from the emulated, mutated FAT image.
    for name,want in {**original_files,**expected_files}.items():
        got=subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/'+name])
        if got!=want: raise AssertionError('written M4 media differs: '+name)
    return len(expected_files)
