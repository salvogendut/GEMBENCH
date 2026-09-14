#!/usr/bin/env python3
"""Real Desktop -> File Manager -> unified Notepad, on a disposable hard disk."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from test_notepad_1983 import NotepadDriver
from test_msx_stability_1983 import constants


class HandoffDriver(NotepadDriver):
    def application(self,symbol,size=1):
        bank=self.entry(getattr(self,'notepad_slot',2))[0]
        return self.call(f'ram {bank*0x4000+self.symbols[symbol]-0x4000} {size}')

    def fm(self,symbol,size=1):
        bank=self.entry(1)[0]
        return self.call(f'ram {bank*0x4000+self.fm_symbols[symbol]-0x4000} {size}')

    def double_click(self,x,y):
        self.move(x,y)
        for pause in (1,60):
            self.wait(lambda:not self.value('POLL_FLAGS')&4,'button release before next press',150)
            self.call('joystick 0 16')
            for _ in range(150):
                self.frames(1)
                if self.value('POLL_FLAGS')&4:break
            else:raise AssertionError('double click was not polled')
            self.call('joystick 0 0');self.frames(pause)

    def entry_named(self,name):
        self.wait(lambda:self.fm('_list_state')==[0],'File Manager listing complete')
        names=self.fm('_names',1144);order=self.fm('_order',104)
        for index,raw in enumerate(order[:self.fm('_total')[0]]):
            if bytes(names[raw*11:raw*11+11])==name:
                index+=bool(self.fm('_fm_path')[0])
                row=index//3-self.fm('_top')[0];col=index%3
                _,x,y,w,h,*_=self.entry(1)
                self.expect(self.fm('_view')==[1] and 0<=row<(h-16)//44,'entry visible in icon view')
                self.double_click(x+4+((w-5)//3)*(col*2+1)//2,y+14+row*44+12)
                return
        raise AssertionError(f'missing File Manager entry {name!r}')

    def exercise(self,args):
        self.symbols={n:int(v,16) for n,v in re.findall(r'^DEF (\w+) (0x[0-9A-Fa-f]+)',
                      (args.source.parent/'probe.noi').read_text(),re.M)}
        self.fm_symbols=json.loads((args.source.parent/'filemgr-symbols.json').read_text())
        glue=constants(args.worktree/'lib/msx/glue.inc')
        def model_text(count):
            owner=self.read(glue['MSX_WIN_OWNER']+2)[0]
            seal=self.read(0x2180+(owner-1)*8,8)
            native=self.read(glue['MSX_PAGE_NATIVE']+seal[1]-1)[0]
            model_symbols=(args.worktree/'build/universal-secondary/secondary/main.sym').read_text()
            assert re.search(r'^\s+1\s+_leaf_editor\s+00000000\s+R',model_symbols,re.M)
            secondary_link=(args.worktree/'build/universal-secondary/secondary/secondary.noi').read_text()
            data_base=int(re.search(r'^DEF s__DATA (0x[0-9A-Fa-f]+)',secondary_link,re.M)[1],16)
            actual=bytes(self.call(f'ram {native*0x4000+data_base+1-0x4000} {count}'))
            return actual,owner,seal,native
        self.wait(lambda:self.read(0xCF00,2)==[48,6] and self.value('WM_NWIN')==1,'desktop boot',6000)
        self.bank=self.frames(100)['p0']
        self.expect(self.read(0xCF05)==[args.mode] and self.read(0xCF1F)==[3],'Screen mode and filesystem API v3')
        before=self.read(glue['MSX_PAGE_STATE'],32);free=self.read(glue['MSX_PAGE_FREE'])
        self.double_click(5,44)
        self.wait(lambda:self.value('WM_NWIN')==2,'File Manager launch')
        self.frames(100);self.entry_named(b'ADOC       ')
        self.wait(lambda:bytes(self.fm('_fm_path',6))==b'/ADOC\0','ADOC navigation')
        if args.config:
            expected=b'FONT=DEFAULT\nVIEW=ICONS\n'
            self.entry_named(b'GEOBENCHCFG')
            self.wait(lambda:self.value('WM_NWIN')==3 and self.value('WM_FOCUS')==2,
                      'configuration launch and focus')
            self.wait(lambda:self.mode()==0 and self.editor()[:2]==[len(expected),0],
                      'configuration staged load')
            # Reuse the deterministic A key used by the core Notepad editor
            # qualification; it inserts a lowercase byte with this fixture.
            self.frames(100);self.type_keys([(2,64)])
            self.wait(lambda:self.editor()[:2]==[len(expected)+1,0] and self.editor()[13],
                      'configuration edit')
            self.menu(2);self.wait(lambda:self.mode()==0 and not self.editor()[13],
                                   'configuration save and publication')
            changed=b'a'+expected
            length=self.read(0x1200,2)
            self.expect(length==[len(changed),0] and bytes(self.read(0x1000,len(changed)))==changed,
                        'resident configuration cache matches saved bytes')
            self.close(2,2)
        if args.basic:
            disk=b'10 PRINT "ONE"\r\n20 END\r\n';expected=disk.replace(b'\r',b'')
            self.entry_named(b'SEED    TXT')
            self.wait(lambda:self.value('WM_NWIN')==3 and self.value('WM_FOCUS')==2,
                      'seed document launch and focus')
            self.load_file(b'ROUND   BAS')
            self.wait(lambda:self.mode()==0 and self.editor()[:2]==[len(expected),0],
                      'BASIC normalized load')
            actual,owner,seal,native=model_text(len(expected))
            self.expect(actual==expected,
                        f'BASIC CRLF normalized in model: owner={owner}, seal={seal}, native={native}')
            self.frames(100);self.type_keys([(2,64)])
            changed=b'a'+expected
            self.wait(lambda:self.editor()[:2]==[len(changed),0] and self.editor()[13],
                      'BASIC edit')
            self.expect(model_text(len(changed))[0]==changed,'BASIC edited model bytes')
            self.menu(2);self.wait(lambda:self.mode()==0 and not self.editor()[13],
                                   'BASIC CRLF save')
            self.expect(model_text(len(changed))[0]==changed,
                        'BASIC save preserves normalized editor bytes')
            self.load_file(b'ROUND   BAS')
            self.wait(lambda:self.mode()==0 and self.editor()[:2]==[len(changed),0],
                      'BASIC reopen')
            self.expect(model_text(len(changed))[0]==changed,'BASIC exact reopen bytes')
            self.close(2,2)
        for nested in () if args.config or args.basic else (False,True):
            expected=b'Chosen nested document.\n' if nested else b'Chosen root document.\n'
            if nested:
                self.entry_named(b'SUB        ')
                self.wait(lambda:bytes(self.fm('_fm_path',10))==b'/ADOC/SUB\0','nested navigation')
            self.entry_named(b'EXACT   TXT')
            if args.bad_app:
                self.frames(400)
                self.expect(self.value('WM_NWIN')==2 and self.read(glue['MSX_FSCTX_PENDING'])==[0],
                            'failed admission cleared pending document')
                break
            self.wait(lambda:self.value('WM_NWIN')==3 and self.value('WM_FOCUS')==2,'document launch and focus')
            self.wait(lambda:self.mode()==0 and self.editor()[:2]==[len(expected),0],
                      'document staged load')
            self.frames(100)
            self.expect(self.editor()[:2]==[len(expected),0] and self.editor()[13]==0,'exact document length and clean state')
            self.expect(self.read(glue['MSX_FSCTX_PENDING'])==[0],'handoff consumed exactly once')
            # Inspect the real sealed model bank, not a debugger-injected model.
            # crt0_secondary contributes one DATA byte before main's model.
            actual,owner,seal,native=model_text(len(expected))
            self.expect(actual==expected,f'exact loaded bytes from selected path: owner={owner}, seal={seal}, native={native}, got={actual!r}')
            self.border(2)
            # Save the adopted document in place; host verifies both directories.
            self.menu(2);self.wait(lambda:self.mode()==0,'in-place save completed');self.frames(100)
            if args.reuse and not nested:
                # The larger File Manager remains exposed below Notepad. Raise
                # it without closing the editor; the next TXT launch must reuse
                # slot 2 and keep the total at three windows.
                _,x,y,w,h,*_=self.entry(1)
                self.click(x+w-2,y+h-2)
                self.wait(lambda:self.value('WM_FOCUS')==1,'File Manager refocus for reuse')
            else:self.close(2,2)
        self.close(1,1)
        if args.bad_app:
            self.notepad_slot=1
            self.launch() # undamaged Desk alias must open blank, not the failed document
            self.expect(self.read(glue['MSX_FSCTX_PENDING'])==[0],'later blank launch has no stale handoff')
            self.close(1,1)
        after=self.read(glue['MSX_PAGE_STATE'],32);after_free=self.read(glue['MSX_PAGE_FREE'])
        # A deferred boot resource can still occupy one page at the baseline
        # and be released by the first launch.  The invariant is the idle
        # desktop allocation plus no loss of free pages, not byte equality
        # with that transient baseline.
        reclaimed=(after==before and after_free==free) or \
                  (after==[1]+[0]*31 and after_free[0]>=free[0])
        self.expect(reclaimed,
                    f'all application pages reclaimed: {before}/{free} -> {after}/{after_free}')
        self.expect(all(not self.read(glue['MSX_FSCTX_TABLE']+144*i)[0] for i in range(4)), 'all contexts reclaimed')
        self.expect(self.read(0x2180,64)==[0]*64 and not self.value('SCHED_FAULT'),'seals and scheduler clean')
        return dict(status='PASS',checks=self.checks,frames=self.frame,
                    case='config' if args.config else 'basic' if args.basic else
                         'bad-app' if args.bad_app else
                         'reuse' if args.reuse else 'exact-path')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('bridge','omega','sunrise','image','worktree','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--mode',type=int,choices=(6,7),required=True)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--bad-app',action='store_true')
    mode.add_argument('--reuse',action='store_true')
    mode.add_argument('--config',action='store_true')
    mode.add_argument('--basic',action='store_true')
    args=parser.parse_args();args.bios=args.subrom=None;args.short_desk_stress=False
    if args.output.exists():parser.error('output exists; preserve earlier evidence')
    args.source=args.image;source_hash=hashlib.sha256(args.source.read_bytes()).hexdigest()
    app=(args.source.parent/'probe.APP').read_bytes()
    if subprocess.check_output(['mtype','-i',str(args.source)+'@@16384','::/GBENCH/NOTEPAD.APP'])!=app:
        parser.error('image and matching probe.APP differ')
    args.output.mkdir(parents=True);args.image=args.output/'filesystem.img';shutil.copyfile(args.source,args.image)
    if args.bad_app:
        damaged=bytearray((args.source.parent/'probe.APP').read_bytes());damaged[-1]^=1
        file=args.output/'BAD.APP';file.write_bytes(damaged)
        subprocess.run(['mcopy','-o','-i',str(args.image)+'@@16384',str(file),'::/GBENCH/NOTEPAD.APP'],check=True)
    if args.config:
        file=args.output/'GEOBENCH.CFG';file.write_bytes(b'FONT=DEFAULT\nVIEW=ICONS\n')
        subprocess.run(['mcopy','-o','-i',str(args.image)+'@@16384',str(file),'::/ADOC/GEOBENCH.CFG'],check=True)
    if args.basic:
        file=args.output/'ROUND.BAS';file.write_bytes(b'10 PRINT "ONE"\r\n20 END\r\n')
        subprocess.run(['mcopy','-o','-i',str(args.image)+'@@16384',str(file),'::/ADOC/ROUND.BAS'],check=True)
        file=args.output/'SEED.TXT';file.write_bytes(b'Open BASIC through Notepad.\n')
        subprocess.run(['mcopy','-o','-i',str(args.image)+'@@16384',str(file),'::/ADOC/SEED.TXT'],check=True)
    driver=None
    try:
        with (args.output/'bridge.log').open('w') as log:
            driver=HandoffDriver(args,log);report=driver.exercise(args)
    except Exception as error:
        report=dict(status='FAIL',error=str(error),frames=driver.frame if driver else 0)
        if driver:
            report.update(windows=driver.value('WM_NWIN'),machine=driver.frames(0))
            if driver.value('WM_NWIN')>1:
                report['filemgr']={s:driver.fm(s,40 if s=='_fm_path' else 1) for s in
                                  ('_fm_path','_nsel','_dc_timer','_dc_idx','_top','_list_state','_view')}
    finally:
        if driver:
            try:driver.call(f"ppm {args.output.resolve()/'screen.ppm'}")
            finally:driver.process.terminate();driver.process.wait(timeout=10)
    for directory,data in (('ADOC',b'Chosen root document.\n'),('ADOC/SUB',b'Chosen nested document.\n')):
        actual=subprocess.check_output(['mtype','-i',str(args.image)+'@@16384',f'::/{directory}/EXACT.TXT'])
        if actual!=data:report.update(status='FAIL',error='saved file differs: '+directory)
    if args.config:
        actual=subprocess.check_output(['mtype','-i',str(args.image)+'@@16384','::/ADOC/GEOBENCH.CFG'])
        if actual!=b'aFONT=DEFAULT\nVIEW=ICONS\n':
            if report.get('status')=='PASS':
                report.update(status='FAIL',error='saved configuration differs')
            else:
                report['saved_configuration_mismatch']=actual.decode('ascii','backslashreplace')
    if args.basic:
        actual=subprocess.check_output(['mtype','-i',str(args.image)+'@@16384','::/ADOC/ROUND.BAS'])
        if actual!=b'a10 PRINT "ONE"\r\n20 END\r\n':
            if report.get('status')=='PASS':report.update(status='FAIL',error='saved BASIC differs')
            else:report['saved_basic_mismatch']=actual.decode('ascii','backslashreplace')
    unchanged=hashlib.sha256(args.source.read_bytes()).hexdigest()==source_hash
    if not unchanged:report.update(status='FAIL',error='source image changed')
    report.update(source_image_sha256=source_hash,source_image_unchanged=unchanged,mode=args.mode,
                  app_sha256=hashlib.sha256(app).hexdigest(),
                  bridge_sha256=hashlib.sha256(args.bridge.read_bytes()).hexdigest(),
                  click_input='joystick port 1 trigger')
    (args.output/'result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    return report['status']!='PASS'


if __name__=='__main__':raise SystemExit(main())
