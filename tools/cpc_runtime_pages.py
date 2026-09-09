"""Same portable page APP on the existing CPC M4 launcher, private only."""
import hashlib
import os
import subprocess
from cpc_production_lifetime import physical

def prepare(root,image):
    app=root/'build/universal/PAGEPRB.APP'
    subprocess.run(['bash','tools/build_uapp.sh','apps/pageprobe',str(app)],cwd=root,
        env={**os.environ,'UNIVERSAL_DATA_PAGES':'1','UNIVERSAL_SCRAP':'1',
             'APP_ICON':'apps/abiprobe/icon.asm',
             'APP_ICON16':os.environ.get('PORTABLE_PROBE_ICON16','')},check=True)
    subprocess.run(['mcopy','-o','-i',str(image)+'@@16384',str(app),'::/GBENCH/FSPROBE.APP'],check=True)

def exercise(root,work,sym,image,key,state,checked):
    app=(root/'build/universal/PAGEPRB.APP').read_bytes()
    if subprocess.check_output(['mtype','-i',str(image)+'@@16384','::/GBENCH/FSPROBE.APP'])!=app:
        raise AssertionError('data-page APP bytes differ')
    original=hashlib.sha256(image.read_bytes()).hexdigest()
    at=next(int(line.split()[2],16) for line in (root/'build/universal-obj/pageprobe/app.noi').read_text().splitlines()
            if line.startswith('DEF _pageprobe_state '))
    ram=checked('data-pages-baseline')
    baseline=bytes(ram[sym['core_page_state']:sym['core_page_state']+32])
    results=[];identities=[]
    for cycle in range(3):
        key('F5');ram=state('data-pages-'+str(cycle))
        if ram[sym['wm_nwin']]!=3 or ram[sym['wm_focus']]!=2:
            raise AssertionError('data-page APP launch/focus')
        base=physical(ram[sym['wm_table']+50])-0x4000
        result=list(ram[base+at:base+at+8])
        if result[0]!=85 or result[1]+256*result[2]<130 or result[4]!=bool(cycle):
            raise AssertionError(f'data-page cycle {cycle}: {result}')
        if ram[base+0x4000:base+0x4000+len(app)]!=app:
            raise AssertionError('data-page code changed')
        identity=(ram[sym['core_win_owner']+2],ram[sym['core_win_owner_gen']+2])
        if identity in identities:raise AssertionError('owner generation reused')
        identities.append(identity);results.append(result)
        key('ESCAPE');ram=checked('data-pages-close-'+str(cycle))
        if bytes(ram[sym['core_page_state']:sym['core_page_state']+32])!=baseline:
            raise AssertionError('data pages leaked after owner teardown')
    if hashlib.sha256(image.read_bytes()).hexdigest()!=original:raise AssertionError('page probe changed disk')
    return dict(status='PASS',results=results,owners=identities,image_unchanged=True,
                app_sha256=hashlib.sha256(app).hexdigest())
