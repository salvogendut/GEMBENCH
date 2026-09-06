"""Independent expected surfaces for the real universal ABI Probe, not a WM."""
from cpc_graphics_fixture import CURSOR, address, put_pixel
from cpc_production_registration import chrome


def frame(rects, order, accents, pointer, font):
    def fill(image,x,y,w,h,pen):
        for yy in range(max(0,y),min(200,y+h)):
            for xx in range(max(0,x)*4,min(80,x+w)*4): put_pixel(image,xx,yy,pen)
    def text(image,x,y,value,pen,paper):
        fw,fh=font[7:9]
        for i,ch in enumerate(value):
            at=16+(ord(ch)-font[5])*fh
            for gy in range(fh):
                for gx in range(fw):
                    xx,yy=x*4+i*fw+gx,y+gy
                    if 0<=xx<320 and 0<=yy<200:
                        put_pixel(image,xx,yy,pen if font[at+gy]&(128>>gx) else paper)
    # Keep the boot pattern in non-display raster gaps; draw only visible pixels.
    result=bytearray((a>>8)^(a&255) for a in range(0xC000,0x10000))
    fill(result,0,0,80,200,0);fill(result,0,0,80,8,1)
    text(result,1,0,'CPC F3: APP F4: M4 F5: FS S: save',2,1)
    for slot in order:
        if not slot: continue
        x,y,w,h=rects[slot]
        surface=chrome((x,y,w,h),7,'Universal ABI',font)
        fill(surface,x+1,y+14,w-2,h-15,1)
        text(surface,x+4,y+22,'GEOBENCH-2 ABI',2,1)
        text(surface,x+4,y+38,'ONE APP / 3 Z80S',2,1)
        fill(surface,x+4,y+54,w-8,6,3 if accents[slot] else 2)
        for yy in range(y,y+h):
            for xx in range(x,x+w):
                at=address(xx*4,yy);result[at]=surface[at]
    px,py=pointer
    for y,row in enumerate(CURSOR):
        for x,ch in enumerate(row):
            if ch!='.' and px+x<320 and py+y<200: put_pixel(result,px+x,py+y,int(ch))
    return bytes(result)


def verify_pixels(ram,sym,work,rects,order,accents):
    px=int.from_bytes(ram[sym['pointer_x']:sym['pointer_x']+2],'little')
    py=ram[sym['pointer_y']]
    expected=frame(rects,order,accents,(px,py),(work/'DEFAULT.FNT').read_bytes())
    actual=ram[0xC000:0x10000]
    if actual!=expected:
        at=next(i for i,(a,b) in enumerate(zip(actual,expected)) if a!=b)
        raise AssertionError(f'composited pixels at {at:04X}: got {actual[at]:02X}, expected {expected[at]:02X}')
    return actual
