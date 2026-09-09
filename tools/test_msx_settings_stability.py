#!/usr/bin/env python3
"""Verify normal MSX Settings persistence and cold-boot reload on private media."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

def symbol(noi, name):
    return int(re.search(rf"^DEF {re.escape(name)} (0x[0-9A-Fa-f]+)", noi.read_text(), re.M)[1], 16)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--built-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", type=int, choices=(6,7), required=True)
    args = parser.parse_args()
    root, out = args.built_root.resolve(), args.output.resolve()
    tools = Path(__file__).resolve().parent
    subprocess.run(["python3", str(tools/"prepare_msx_stability.py"), "--built-root", str(root),
                    "--output", str(out), "--mode", str(args.mode)], check=True)
    env = dict(os.environ, MSX_HEADLESS="1", MSX_UNAPI="0", MSX_MOUSE="0",
               GEMBENCH_ACCESSORY_LAYOUT=str(root/"kernel/lowram.inc"),
               GEMBENCH_ACCESSORY_OUTPUT=str(out/"unused-accessory.txt"),
               GEMBENCH_ACCESSORY_SCREENSHOT=str(out/"screen.png"),
               MSX_SCRIPT=str(tools.parent/"debug/msx_settings_stability.tcl"))
    for app, prefix, package in [("uclock", "CLOCK", "CLOCK"), ("ucalculator", "CALC", "CALC")]:
        address = symbol(root/f"build/universal-obj/{app}/app.noi", "_main")
        data = (root/f"build/universal/{package}.APP").read_bytes()[address-0x4000:address-0x4000+3]
        env[f"GEMBENCH_ACCESSORY_{prefix}_MAIN"] = str(address)
        for index, value in enumerate(data):
            env[f"GEMBENCH_ACCESSORY_{prefix}_SIG{index}"] = str(value)
    noi = root/"build/msx-obj/settings/app.noi"
    address = symbol(noi, "_main")
    offset = int(re.search(r"^\s+1\s+_cfgbuf\s+([0-9A-Fa-f]+)",
                          (root/"build/msx-obj/settings/main.sym").read_text(), re.M)[1], 16)
    env["MSX_SETTINGS_MAIN"] = str(address)
    env["MSX_SETTINGS_CFGBUF"] = str(symbol(noi, "s__DATA") + offset)
    data = (root/"build/msx/SETTINGS.RAW").read_bytes()[address-0x4000:address-0x4000+3]
    env["MSX_SETTINGS_SIGNATURE"] = ",".join(map(str, data))
    image = out/"GEOBENCH.IMG"
    report = dict(status="FAIL", mode=args.mode)
    try:
        for phase in ("save", "verify"):
            result = out/f"{phase}.txt"
            env.update(MSX_SETTINGS_PHASE=phase, MSX_SETTINGS_RESULT=str(result))
            with (out/f"{phase}.log").open("w") as log:
                subprocess.run(["bash", "tools/run_msx.sh", str(image)], cwd=root,
                               env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
            if "STATUS=PASS" not in result.read_text().splitlines():
                raise RuntimeError(result.read_text())
            config = subprocess.check_output(["mtype", "-i", str(image)+"@@16384", "::/GEOBENCH.CFG"])
            if b"TITLEBAR=FANCY.TBR" not in config.splitlines():
                raise AssertionError("saved disk config lacks TITLEBAR=FANCY.TBR")
            (out/f"{phase}-GEOBENCH.CFG").write_bytes(config)
        report["status"] = "PASS"
    except Exception as error:
        report["error"] = str(error)
    report["image_sha256"] = hashlib.sha256(image.read_bytes()).hexdigest()
    (out/"result.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
