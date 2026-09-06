from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_cpc_production import assemble
from cpc_production_loading import CASES, packages, loading_commands, verify_loading
from embed_app_icon import parse_manifest


class LoadingSourceTests(unittest.TestCase):
    def test_shared_transaction_and_admission_are_the_msx_policy(self):
        for name,msx in (("app_launch.asm","gbkern.asm"),("app_admission.asm","msx_gbap4.asm")):
            for entry in (msx,"cpc_loading.asm"):
                self.assertEqual((ROOT/"kernel"/entry).read_text().count(f'include "core/{name}"'),1)
            code="\n".join(l.split(";",1)[0] for l in (ROOT/"kernel/core"/name).read_text().splitlines())
            self.assertNotRegex(code,r"\b(?:CPC_\w+|MSX_\w+|PLATFORM_\w+)\b")
            self.assertNotRegex(code.lower(),r"\b(?:in|out|halt)\b")
        launch=(ROOT/"kernel/core/app_launch.asm").read_text()
        self.assertLess(launch.index("call  APP_ADMISSION_GATE"),launch.index("call  APP_BASE"))
        self.assertIn("call  owner_release",launch[launch.index("wmo_fail\n"):])
        reader=(ROOT/"lib/cpc/app_load.asm").read_text()
        self.assertIn("call storage_gate",reader)
        code="\n".join(l.split(";",1)[0] for l in reader.splitlines())
        self.assertNotRegex(code.lower(),r"\b(?:out|in|ei)\b")
        self.assertIn("ld bc,APP_LOAD_MAX+1",reader)
        self.assertNotIn("#7F00",reader)  # use layout's declared aperture fence

    def test_media_only_and_no_public_abi_or_emulator_injection(self):
        probe=(ROOT/"debug/cpc_production/loading_probe.asm").read_text()
        self.assertIn("call k_wm_open",probe)
        self.assertIn("call k_wm_launch_as",probe)
        self.assertIn("call owner_alloc",probe)
        self.assertIn("call page_alloc_owned",probe)
        self.assertNotIn("incbin",probe)
        self.assertNotIn("call APP_BASE",probe)
        runner=(ROOT/"tools/test_cpc_production_1984.py").read_text()
        self.assertNotRegex(runner,r'send\(.*(?:snapshot-load|poke|write-memory)')
        self.assertIn("m4_image=",runner)
        self.assertNotIn('"--dsk',runner)


@unittest.skipUnless(shutil.which(os.environ.get("RASM","rasm")),"RASM required for native loader composition")
class LoadingAssemblyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="geobench-loading-unit-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name)
        cls.sym=assemble(cls.work,"loading")

    def test_link_memory_boundaries_and_repeatability(self):
        s=self.sym
        self.assertLessEqual(s["cpc_kernel_used_end"],0xC000)
        self.assertEqual(s["app_load_max"],0x3F00)
        self.assertGreaterEqual(s["cpc_app_path"],s["core_fsctx_table"]+4*144)
        self.assertLessEqual(s["gb4_crc_value"]+4,0x2900)
        self.assertLessEqual(s["cpc_app_io_buffer"]+128,s["cpc_app_io_end"])
        self.assertLessEqual(s["cpc_app_io_end"],s["cpc_loading_trace"])
        self.assertLessEqual(s["cpc_loading_trace"]+len(CASES)*32,0x7F00)
        again=self.work/"again"
        assemble(again,"loading")
        for name in ("CORE.RAW","SUPPORT.RAW","SCHED.RAW","HARDWARE.RAW","BOOT.RAW",*packages(s,ROOT)):
            self.assertEqual((again/name).read_bytes(),(self.work/name).read_bytes())

    def test_exact_limit_and_adversarial_packages(self):
        files=packages(self.sym,ROOT)
        for name in ("RETURN.APP","MAXIMUM.APP"):
            self.assertEqual(parse_manifest(files[name])["image_size"],len(files[name]))
        for name in ("BADCRC.APP","IDENTITY.APP","SEGMENT.APP","LENGTH.APP","TRUNC.APP"):
            with self.subTest(name=name),self.assertRaises(ValueError): parse_manifest(files[name])
        self.assertEqual(len(files["MAXIMUM.APP"]),0x3F00)
        self.assertEqual(len(files["HUGE.APP"]),0x3F01)
        self.assertEqual(files["EMPTY.APP"],b"")
        self.assertEqual(parse_manifest(files["MINPAGES.APP"])["minimum_pages"],27)
        self.assertGreater(loading_commands(self.work),1000)

    def test_assembly_asserts_reject_insufficient_fixed_budget(self):
        with self.assertRaises(subprocess.CalledProcessError):
            assemble(self.work/"small","loading",("-DCPC_KERNEL_END=45056",))


if __name__=="__main__": unittest.main()
