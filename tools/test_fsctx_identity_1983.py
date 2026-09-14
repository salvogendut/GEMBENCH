#!/usr/bin/env python3
"""Run the copied-identity FS probe via Desk on a disposable 1983 hard disk."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from test_msx_stability_1983 import Driver


class IdentityDriver(Driver):
    def exercise(self,args):
        symbols=(args.source_image.parent/'probe.noi').read_text()
        address=int(re.search(r'^DEF _fsprobe_state (0x[0-9A-Fa-f]+)',symbols,re.M)[1],16)
        self.wait(lambda:self.read(0xCF00,2)==[48,6] and self.value('WM_NWIN')==1,
                  'desktop boot',6000)
        self.bank=self.frames(100)['p0']
        self.expect(self.read(0xCF05)[0]==args.mode and self.read(0xCF1F)[0]==2,
                    'requested mode and filesystem API v2')
        baseline=self.busy()
        outcomes=[]
        for _ in range(3):
            self.click(11,4);self.click(12,14)
            self.wait(lambda:self.value('WM_NWIN')==2 and self.value('WM_FOCUS')==1,
                      'real Desk probe launch')
            self.frames(100)
            native=self.entry(1)[0]
            result=self.call(f'ram {native*0x4000+address-0x4000} 8')
            self.expect(result[:2]==[85,54],f'all identity and FS checks: {result}')
            for slot in range(4):
                self.expect(self.read(0xC600+slot*144)[0]==0,'contexts explicitly closed')
            outcomes.append(result)
            self.close(1,1)
            self.expect(self.busy()==baseline and self.value('SCHED_FAULT')==0,
                        'owner cleanup and scheduler guard')
        return dict(status='PASS',checks=self.checks,frames=self.frame,results=outcomes)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('bridge','omega','sunrise','image','worktree','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--mode',type=int,choices=(6,7),required=True)
    args=parser.parse_args()
    if args.output.exists():parser.error('output exists; use a fresh evidence directory')
    args.source_image=args.image
    source_hash=hashlib.sha256(args.image.read_bytes()).hexdigest()
    app=(args.image.parent/'probe.APP').read_bytes()
    if subprocess.check_output(['mtype','-i',str(args.image)+'@@16384','::/GBENCH/CLOCK.APP'])!=app:
        parser.error('source image and probe.APP differ')
    args.output.mkdir(parents=True)
    args.image=args.output/'filesystem.img';shutil.copyfile(args.source_image,args.image)
    args.bios=args.subrom=None;args.short_desk_stress=False
    driver=None
    try:
        with (args.output/'bridge.log').open('w') as log:
            driver=IdentityDriver(args,log);report=driver.exercise(args)
    except Exception as error:
        report=dict(status='FAIL',error=str(error),frame=driver.frame if driver else 0)
    finally:
        if driver:
            try:driver.call(f"ppm {args.output.resolve()/'screen.ppm'}")
            finally:driver.process.terminate();driver.process.wait(timeout=10)
    if report['status']=='PASS':
        data=subprocess.check_output(['mtype','-i',str(args.image)+'@@16384','::/UFSTEST/RESULT.BIN'])
        if data!=b'DONE':report.update(status='FAIL',error='independent write readback differs')
    unchanged=hashlib.sha256(args.source_image.read_bytes()).hexdigest()==source_hash
    if not unchanged:report.update(status='FAIL',error='source image changed')
    report.update(mode=args.mode,source_image_unchanged=unchanged,
                  source_image_sha256=source_hash,app_sha256=hashlib.sha256(app).hexdigest(),
                  bridge_sha256=hashlib.sha256(args.bridge.read_bytes()).hexdigest())
    (args.output/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return report['status']!='PASS'


if __name__=='__main__':raise SystemExit(main())
