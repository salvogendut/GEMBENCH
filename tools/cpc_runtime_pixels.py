"""Independent expected surfaces for the real universal ABI Probe, not a WM."""
from cpc_graphics_fixture import CURSOR, address, put_pixel
from cpc_production_registration import chrome


def frame(rects, order, accents, pointer, font, clock=(0, 0), menu=b'\0', titles=None, popup=None, calculators=None):
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
    text(result,1,0,'512K',2,1)
    text(result,68,0,f'{clock[0]:02}:{clock[1]:02}',2,1)
    for i in range(min(menu[0],4)):
        text(result,menu[1+i*9],0,menu[2+i*9:10+i*9].split(b'\0',1)[0].decode(),2,1)
    for slot in order:
        if not slot: continue
        x,y,w,h=rects[slot]
        calculator=(calculators or {}).get(slot)
        surface=chrome((x,y,w,h),11 if calculator is not None else 7,
                       (titles or {}).get(slot,'Universal ABI'),font)
        fill(surface,x+1,y+14,w-2,h-15,1)
        if calculator is not None:
            def box(bx,by,bw,bh,pen):
                for edge in ((bx,by,bw,1),(bx,by+bh-1,bw,1),(bx,by,1,bh),(bx+bw-1,by,1,bh)):
                    fill(surface,*edge,pen)
            fill(surface,x+2,y+17,27,20,2);box(x+2,y+17,27,20,3)
            text(surface,x+28-(len(calculator)*6+3)//4,y+23,calculator,3,2)
            labels=('C','SQR','%','/','7','8','9','x','4','5','6','-',
                    '1','2','3','+','0','.','+/-','=')
            for i,label in enumerate(labels):
                bx,by=x+2+(i%4)*7,y+42+(i//4)*20
                fill(surface,bx,by,6,18,1);box(bx,by,6,18,2)
                text(surface,bx+(6-(len(label)*6+3)//4)//2,by+5,label,2,1)
        else:
            text(surface,x+4,y+22,'GEOBENCH-2 ABI',2,1)
            text(surface,x+4,y+38,'ONE APP / 3 Z80S',2,1)
            fill(surface,x+4,y+54,w-8,6,3 if accents[slot] else 2)
        for yy in range(y,y+h):
            for xx in range(x,x+w):
                at=address(xx*4,yy);result[at]=surface[at]
    if popup is not None:
        x,hot,*custom=popup
        labels=custom[0] if custom else ('Toggle','Cancel')
        y,w,h=8,max((len(s)*6+3)//4+4 for s in labels),len(labels)*10+4
        fill(result,x,y,w,h,1)
        for rx,ry,rw,rh in ((x,y,w,1),(x,y+h-1,w,1),(x,y,1,h),(x+w-1,y,1,h)):
            fill(result,rx,ry,rw,rh,2)
        for i,label in enumerate(labels):
            paper,pen=(2,1) if i==hot else (1,2)
            fill(result,x+1,y+2+i*10,w-2,10,paper)
            text(result,x+1,y+2+i*10,label,pen,paper)
    px,py=pointer
    for y,row in enumerate(CURSOR):
        for x,ch in enumerate(row):
            if ch!='.' and px+x<320 and py+y<200: put_pixel(result,px+x,py+y,int(ch))
    return bytes(result)


def verify_pixels(ram,sym,work,rects,order,accents,menu=b'\0',titles=None,popup=None,calculators=None):
    px=int.from_bytes(ram[sym['pointer_x']:sym['pointer_x']+2],'little')
    py=ram[sym['pointer_y']]
    if ram[sym['menu_def']:sym['menu_def']+len(menu)]!=menu:
        raise AssertionError('focused menu snapshot differs')
    expected=frame(rects,order,accents,(px,py),(work/'DEFAULT.FNT').read_bytes(),
                   tuple(ram[0x1240:0x1242]),menu,titles,popup,calculators)
    actual=ram[0xC000:0x10000]
    if actual!=expected:
        at=next(i for i,(a,b) in enumerate(zip(actual,expected)) if a!=b)
        raise AssertionError(f'composited pixels at {at:04X}: got {actual[at]:02X}, expected {expected[at]:02X}')
    return actual
