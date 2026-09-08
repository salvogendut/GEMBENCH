"""Independent native File Manager surface oracle (no guest screen copying)."""
from cpc_graphics_fixture import put_pixel


def listing(files, path=''):
    prefix=path.strip('/')
    if prefix: prefix+='/'
    items={}
    for full in files:
        if not full.startswith(prefix): continue
        name=full[len(prefix):].split('/')[0]
        if not name: continue
        directory='/' in full[len(prefix):]
        ext=name.rsplit('.',1)[-1] if '.' in name else ''
        slot=8 if directory else {'TXT':7,'CFG':7,'BAS':4,'BIN':5,'MOD':3,'FNT':10}.get(ext,5)
        if ext=='APP': slot={'CLOCK.APP':1,'CALC.APP':20,'DESKTOP.APP':11,'FILEMGR.APP':12}.get(name,9)
        items[name]=slot
    rank={8:0,1:1,9:1,11:1,12:1,20:1,6:2,7:3,4:4,10:6,3:7}
    return sorted(items.items(),key=lambda row:(rank.get(row[1],8),row[0]))


def draw(surface,rect,state,icons,fill,text):
    x,y,w,h=rect;cx=x+4;cy=y+14;cw=w-5;ch=h-16
    rows=state['items'];top=state.get('top',0);view=state.get('view',1);selected=state.get('selected',0)
    total=(len(rows)+2)//3 if view else len(rows)
    page=ch//(44 if view else 18)
    thumb=ch if total<=page else min(ch,max(6,ch*page//total))
    ty=cy if total<=page else cy+(ch-thumb)*min(top,total-page)//(total-page)
    fill(surface,x+1,cy,3,ch,1)
    fill(surface,x+2,ty+1,1,thumb-2,3)
    for ay,glyph in ((cy,'\x80'),(cy+ch-8,'\x81')):
        fill(surface,x+1,ay,3,8,1);text(surface,x+2,ay,glyph,2,1)
    def icon(slot,bx,by,half=False):
        off=int.from_bytes(icons[16+4*slot:18+4*slot],'little')
        iw,ih=icons[18+4*slot:20+4*slot]
        if half: off+=(ih//4)*iw;ih//=2
        for yy in range(ih):
            for xx in range(iw*4):
                value=icons[off+yy*iw+xx//4];shift=xx%4
                pen=((value>>(7-shift))&1)|(((value>>(3-shift))&1)<<1)
                if pen and x*4<=bx*4+xx<(x+w)*4 and y<=by+yy<y+h:
                    put_pixel(surface,bx*4+xx,by+yy,pen)
    for i in range(page*(3 if view else 1)):
        pos=top*3+i if view else top+i
        bx=cx+(i%3)*(cw//3) if view else cx
        by=cy+(i//3)*44 if view else cy+i*18
        bw=cw//3 if view else cw;bh=43 if view else 18
        fill(surface,bx,by,bw,bh,0)
        if pos>=len(rows): continue
        name,slot=rows[pos]
        if name=='..':
            icon(14,bx+(bw-4)//2 if view else bx,by+9 if view else by+1)
            text(surface,bx+(bw-3)//2 if view else bx+9,by+34 if view else by+6,'..',1,0)
        else:
            icon(slot,bx+(bw-8)//2 if view else bx,by+1,not view)
            text(surface,bx if view else bx+9,by+34 if view else by+6,
                 name[:min(13,bw*4//6)] if view else name,1,0)
        if selected==pos+1:
            hh=43 if view else 17
            for edge in ((bx,by,bw,1),(bx,by+hh-1,bw,1),(bx,by,1,hh),(bx+bw-1,by,1,hh)):
                fill(surface,*edge,3)
