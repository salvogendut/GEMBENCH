#!/usr/bin/env python3
"""Read-only 1983 bridge + real pointer input for the shared chooser workflow."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from test_msx_stability_1983 import Driver
from filepick_scenario import exercise, status_pixels


class ChooserDriver(Driver):
    def exercise(self,args,app):
        linked={v[1]:int(v[2],16) for line in
                (args.worktree/'build/universal-obj/filepickprobe/app.noi').read_text().splitlines()
                if len(v:=line.split())==3 and v[0]=='DEF'}
        self.wait(lambda:self.read(0xCF00,2)==[48,6] and self.value('WM_NWIN')==1,
                  'desktop boot',6000)
        self.bank=self.frames(100)['p0']
        self.expect(self.read(0xCF05)[0]==args.mode,'screen mode')
        baseline=self.busy()
        self.click(11,4);self.click(12,14)

        def observe(name,fields):
            def data():
                base=self.entry(1)[0]*0x4000-0x4000
                return base,self.call(f"ram {base+linked['_filepickprobe_state']} 12")
            self.wait(lambda:self.value('WM_NWIN')==2 and self.value('WM_FOCUS')==1 and
                      all(data()[1][k]==v for k,v in fields.items()),name)
            font=(args.worktree/'build/msx/DEFAULT.FNT').read_bytes()
            for _ in range(200):
                self.frames(5);base,values=data()
                y=40 if values[10] else 156
                low=self.call(f'vram {y*128} 1024')
                high=self.call(f'vram {65536+y*128} 1024') if args.mode==7 else None
                def pixel(x,py):
                    at=(py-y)*128+x//4
                    if high is not None:
                        return ((high if (x//2)%2 else low)[at] >> (0 if x%2 else 4)) & 15
                    return (low[at] >> ((3-x%4)*2)) & 3
                if status_pixels(values,font,pixel): break
            else: raise AssertionError(name+': status text was not repainted')
            self.expect(True,'visible status text repainted')
            self.expect(values[11]==85,'4096-byte document guard')
            loaded=b''.join(bytes(self.call(f'ram {base+0x4000+i} {min(4096,len(app)-i)}'))
                            for i in range(0,len(app),4096))
            self.expect(loaded==app,'application code intact')
            self.expect(self.value('SCHED_FAULT')==0,'scheduler guard')
            self.expect(sum(bool(self.read(0xC600+144*i)[0]) for i in range(4))==
                        (0 if values[0]==8 else 1),'context ownership/count')
            self.border(1)
            p=base+linked['_picker'];n=values[8]+256*values[9]
            self.call(f"ppm {args.output.resolve()/(name+'.ppm')}")
            print(name,values,flush=True)
            return dict(path=bytes(self.call(f'ram {p+17} 48')).split(b'\0',1)[0].decode(),
                        name=bytes(self.call(f'ram {p+65} 11')),
                        data=bytes(self.call(f"ram {base+linked['_text']+1} {n}")) if n else b'')

        cases=exercise(self.click,observe)
        self.click(6,24)
        self.wait(lambda:self.value('WM_NWIN')==1,'close')
        self.expect(self.busy()==baseline,'app page reclaimed')
        self.expect(not any(self.read(0xC600+144*i)[0] for i in range(4)),'contexts reclaimed')
        return dict(status='PASS',checkpoints=cases,checks=self.checks,frames=self.frame)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('bridge','omega','sunrise','image','worktree','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--mode',type=int,choices=(6,7),required=True)
    parser.add_argument('--bios',type=Path);parser.add_argument('--subrom',type=Path)
    args=parser.parse_args();args.short_desk_stress=False
    if bool(args.bios)!=bool(args.subrom): parser.error('supply both BIOS and subROM')
    if args.output.exists(): parser.error('use a new output directory; retain old evidence')
    app=(args.worktree/'build/universal/PICKPRB.APP').read_bytes()
    if subprocess.check_output(['mtype','-i',str(args.image)+'@@16384','::/GBENCH/CLOCK.APP'])!=app:
        parser.error('test image and APP symbols must match')
    before=hashlib.sha256(args.image.read_bytes()).hexdigest()
    args.output.mkdir(parents=True)
    driver=None
    try:
        with (args.output/'bridge.log').open('w') as log:
            driver=ChooserDriver(args,log);report=driver.exercise(args,app)
    except Exception as error:
        report=dict(status='FAIL',error=str(error),frame=driver.frame if driver else 0)
    finally:
        if driver:
            try: driver.call(f"ppm {args.output.resolve()/'screen.ppm'}")
            except Exception as error: report.update(status='FAIL',capture_error=str(error))
            finally: driver.process.terminate();driver.process.wait(timeout=10)
    if hashlib.sha256(args.image.read_bytes()).hexdigest()!=before:
        report.update(status='FAIL',media_changed=True)
    report.update(mode=args.mode,app_sha256=hashlib.sha256(app).hexdigest(),
                  image_sha256=before,bridge_sha256=hashlib.sha256(args.bridge.read_bytes()).hexdigest())
    (args.output/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return 0 if report['status']=='PASS' else 1


if __name__=='__main__': raise SystemExit(main())
