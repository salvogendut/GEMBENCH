"""Independent expected surfaces for the real universal ABI Probe, not a WM."""
from cpc_graphics_fixture import CURSOR, address, put_pixel
from cpc_production_registration import chrome
from pathlib import Path

_ROOT=Path(__file__).resolve().parents[1]
DEFAULT_THEME=(_ROOT/'assets/titlebars/ORIGINAL.TBR').read_bytes()+(_ROOT/'assets/gadgets/ORIGINAL.GDT').read_bytes()


def cursor_grid(sprite):
    """Decode phase zero of the CPC file; no guest phase table as an oracle."""
    if len(sprite)!=256: raise ValueError('CPC cursor must be 256 bytes')
    rows=[]
    for y in range(16):
        row=''
        for x in range(16):
            mask,ink=sprite[y*8+(x//4)*2:y*8+(x//4)*2+2]
            shift=x%4
            row += '.' if mask & (0x88>>shift) else str(((ink>>(7-shift))&1)|(((ink>>(3-shift))&1)<<1))
        rows.append(row)
    return rows


def cursor_phases(sprite):
    """Independent pixel-level encode of all four phases for integrity checks."""
    result=bytearray()
    for phase in range(4):
        for row in cursor_grid(sprite):
            pixels='.'*phase+row
            for col in range(4):
                mask,ink=255,0
                for x,ch in enumerate(pixels[col*4:col*4+4]):
                    if ch!='.':
                        mask &= ~(0x88>>x)
                        ink |= (int(ch)&1)<<(7-x) | (int(ch)>>1)<<(3-x)
                result.extend((mask,ink))
    return bytes(result)


def frame(rects, order, accents, pointer, font, clock=(0, 0), menu=b'\0', titles=None, popup=None, calculators=None, clocks=None, dialog=None, frame_pen=2, cursor=None, backdrop=None, icons=None, theme=DEFAULT_THEME, title_ready=True):
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
    fill(result,0,0,80,200,0)
    if backdrop is not None:
        for y in range(200):
            for x in range(80): result[address(x*4,y)]=backdrop[(y%16)*4+x%4]
    if icons is not None:
        for slot,x,y,half in ((0,2,32,False),(3,34,32,False),(20,72,32,False),(8,18,144,True)):
            if slot>=icons[5]: continue
            off=int.from_bytes(icons[16+4*slot:18+4*slot],'little')
            w,h=icons[18+4*slot:20+4*slot]
            if half: off+=(h//4)*w;h//=2
            for yy in range(h):
                for xx in range(w*4):
                    if x*4+xx>=320 or y+yy>=200: continue
                    b=icons[off+yy*w+xx//4];i=xx%4
                    pen=((b>>(7-i))&1)|(((b>>(3-i))&1)<<1)
                    if half or pen: put_pixel(result,x*4+xx,y+yy,pen)
    fill(result,0,0,80,8,1)
    text(result,1,0,'512K',2,1)
    text(result,68,0,f'{clock[0]:02}:{clock[1]:02}',2,1)
    for i in range(min(menu[0],4)):
        text(result,menu[1+i*9],0,menu[2+i*9:10+i*9].split(b'\0',1)[0].decode(),2,1)
    for slot in order:
        if not slot: continue
        x,y,w,h=rects[slot]
        calculator=(calculators or {}).get(slot)
        watch=(clocks or {}).get(slot)
        surface=chrome((x,y,w,h),31 if watch is not None else 11 if calculator is not None else 7,
                       (titles or {}).get(slot,'Universal ABI'),font,frame_pen,theme,title_ready)
        fill(surface,x+1,y+14,w-2,h-15,0 if watch is not None else 1)
        if watch is not None:
            # Independent Clock geometry/pixels at the observed completed time,
            # not copies of guest screen data or the Z80 compositor algorithm.
            from cpc_runtime_clock import draw_clock
            draw_clock(surface,(x,y,w,h),watch,fill,text)
        elif calculator is not None:
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
    if dialog is not None:
        def box(x,y,w,h,pen=2):
            fill(result,x,y,w,h,1)
            for edge in ((x,y,w,1),(x,y+h-1,w,1),(x,y,1,h),(x+w-1,y,1,h)):
                fill(result,*edge,pen)
        if dialog['kind']=='prompt':
            box(12,60,52,34)
            text(result,14,63,'Name:',2,1)
            text(result,14,76,dialog.get('value',''),2,1)
        elif dialog['kind']=='size':
            box(21,70,38,50)
            text(result,23,74,'New picture',2,1)
            values=dialog.get('values',('320','200'));active=dialog.get('active',0)
            for i,x in enumerate((24,43)):
                box(x,88,8,15,3 if i==active else 2)
                text(result,x+1,91,values[i],2,1)
            text(result,37,91,'by',2,1)
            box(36,107,8,10);text(result,38,108,'OK',2,1)
        elif dialog['kind']=='about':
            box(10,69,60,62)
            text(result,13,74,'GEOBENCH (C) salvogendut 2026',2,1)
            text(result,13,86,dialog['build'],2,1)
            text(result,13,98,'RAM:',2,1);text(result,20,98,'512K',2,1)
        else: raise AssertionError('unknown expected native dialog')
    if popup is not None:
        native=isinstance(popup,dict)
        if native:
            x,y,hot,labels=(popup[k] for k in ('x','y','hot','labels'))
        else:
            x,hot,*custom=popup
            labels=custom[0] if custom else ('Toggle','Cancel')
            y=8
        w=max((len(s)*6+(0 if native else 3))//4+4 for s in labels)
        h=len(labels)*10+4
        fill(result,x,y,w,h,1)
        for rx,ry,rw,rh in ((x,y,w,1),(x,y+h-1,w,1),(x,y,1,h),(x+w-1,y,1,h)):
            fill(result,rx,ry,rw,rh,2)
        for i,label in enumerate(labels):
            paper,pen=(2,1) if i==hot else (1,2)
            if not native: fill(result,x+1,y+2+i*10,w-2,10,paper)
            text(result,x+1,y+2+i*10,label,pen,paper)
    px,py=pointer
    for y,row in enumerate(CURSOR if cursor is None else cursor_grid(cursor)):
        for x,ch in enumerate(row):
            if ch!='.' and px+x<320 and py+y<200: put_pixel(result,px+x,py+y,int(ch))
    return bytes(result)


def verify_pixels(ram,sym,work,rects,order,accents,menu=b'\0',titles=None,popup=None,calculators=None,clocks=None,dialog=None, font=None, frame_pen=2, cursor=None, backdrop=None, icons=None, theme=DEFAULT_THEME, title_ready=True):
    px=int.from_bytes(ram[sym['pointer_x']:sym['pointer_x']+2],'little')
    py=ram[sym['pointer_y']]
    if ram[sym['menu_def']:sym['menu_def']+len(menu)]!=menu:
        raise AssertionError('focused menu snapshot differs')
    expected=frame(rects,order,accents,(px,py),font if font is not None else (work/'DEFAULT.FNT').read_bytes(),
                   tuple(ram[0x1240:0x1242]),menu,titles,popup,calculators,clocks,dialog,frame_pen,
                   (work/'DEFAULT.SPR').read_bytes() if cursor is None else cursor,backdrop,icons,theme,title_ready)
    actual=ram[0xC000:0x10000]
    if actual!=expected:
        at=next(i for i,(a,b) in enumerate(zip(actual,expected)) if a!=b)
        raise AssertionError(f'composited pixels at {at:04X}: got {actual[at]:02X}, expected {expected[at]:02X}')
    return actual
