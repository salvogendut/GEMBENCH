"""Step-3C request vectors and host byte oracle, not a portable filesystem API."""
from __future__ import annotations

import hashlib
from pathlib import Path
import struct
import subprocess

STORAGE_VARIANTS = {"storage": None, "storage-bad-bank": "FAULT_STORAGE_BANK",
                    "storage-bad-rom": "FAULT_STORAGE_ROM",
                    "storage-bad-copy": "FAULT_STORAGE_COPY",
                    "storage-close-error": None, "storage-open-error": None}
INPUT = bytes((i * 37 + (i >> 8) + 11) & 255 for i in range(257))
PAYLOAD = INPUT[:128]
FILES = {"INPUT.BIN": INPUT, "EMPTY.BIN": b"",
         "HEADER.BIN": bytes(18) + b"\x02" + bytes(109) + b"raw-not-AMSDOS-stripped"}
TRACE_START, TRACE_SIZE, ROUNDS = 0x1010, 144, 8


def descriptor(op=1, path=0x4180, pathlen=11, buffer=0x4200, count=128,
               offset=0, version=1, reserved=0, tail=0):
    return struct.pack("<BBHBBHHIH", op, version, path, pathlen, reserved,
                       buffer, count, offset, tail)


def cases(variant="storage"):
    result = []
    def add(name, *, op=1, path=b"/INPUT.BIN\0", status=0, actual=None,
            commands=None, fault=0, pointer=0x4000, length=16, busy=0,
            offline=0, expected=None, **kw):
        index = len(result)
        count = kw.get("count", 128)
        record = descriptor(op, pathlen=len(path), **kw)
        buf = int.from_bytes(record[6:8], "little")
        pathptr = int.from_bytes(record[2:4], "little")
        if actual is None:
            actual = count if status == 0 else 0
        if commands is None:
            commands = (4 if op == 1 else 3) if count else (0 if op == 1 else 2)
        result.append(dict(name=name, record=record, status=status, actual=actual,
                           commands=commands, fault=fault, pointer=pointer,
                           length=length, busy=busy, offline=offline,
                           ga=(0x8D, 0x85, 0x8C, 0x84, 0x8E, 0x86)[index % 6],
                           slot=(0, 6, 7)[index % 3], bank=(0xC0, 0xC4, 0xC5)[index % 3],
                           pathseed=pathptr if 0x4000 <= pathptr <= 0x7F00-len(path) else 0x4180,
                           bufseed=buf if op == 2 and 0x4000 <= buf <= 0x7E80 else 0x4400,
                           observe=buf if op == 1 and 0x4000 <= buf <= 0x7E80 else 0x4200,
                           path=path, expected=expected))
    add("exact-128", expected=INPUT[:128])
    add("second-128", offset=128, expected=INPUT[128:256])
    add("short-tail", offset=250, status=1, actual=7, expected=INPUT[250:])
    add("exact-end-byte", offset=256, count=1, expected=INPUT[256:])
    add("past-end", offset=257, status=1, actual=0, expected=b"")
    add("empty-file", path=b"/EMPTY.BIN\0", status=1, actual=0, expected=b"")
    add("zero-read", count=0, buffer=0xFFFF, expected=b"")
    add("replace-128", op=2, path=b"/OUTPUT.BIN\0")
    add("readback-128", path=b"/OUTPUT.BIN\0", expected=PAYLOAD)
    add("truncate-17", op=2, path=b"/OUTPUT.BIN\0", count=17)
    add("readback-17", path=b"/OUTPUT.BIN\0", status=1, actual=17, expected=PAYLOAD[:17])
    add("restore-128", op=2, path=b"/OUTPUT.BIN\0")
    add("create-empty", op=2, path=b"/ZERO.BIN\0", count=0, buffer=0xFFFF)
    add("read-created-empty", path=b"/ZERO.BIN\0", status=1, actual=0, expected=b"")
    add("raw-header", path=b"/HEADER.BIN\0", expected=FILES["HEADER.BIN"][:128])
    add("missing", path=b"/ABSENT.BIN\0", status=3, commands=1)
    add("missing-parent", op=2, path=b"/ABSENT/OUT.BIN\0", status=3, commands=1)
    add("max-path-length", path=b"/"+b"P"*62+b"\0", status=3, commands=1)
    add("last-buffer", buffer=0x7E80, expected=INPUT[:128])
    # Descriptor and string may end exactly at 7F00; they are copied first.
    add("last-descriptor", pointer=0x7EF0, expected=INPUT[:128])
    # 'path' is the bytes parameter above; patch its descriptor pointer explicitly.
    add("last-path", expected=INPUT[:128])
    result[-1]["record"] = descriptor(path=0x7EF5)
    result[-1]["pathseed"] = 0x7EF5
    add("last-write-buffer", op=2, path=b"/OUTPUT.BIN\0", buffer=0x7E80)
    for pointer in (0, 0x3FFF, 0x7EF1, 0xC030, 0xFFF8):
        add(f"bad-descriptor-{pointer:04x}", pointer=pointer, status=2, commands=0)
    for length in (0, 15, 17, 0xFFFF):
        add(f"bad-length-{length}", length=length, status=2, commands=0)
    for op in (1, 2):
        add(f"oversize-{op}", op=op, count=129, status=2, commands=0)
        for buf in (0x3FFF, 0x7E81, 0xC030, 0xFFFF):
            add(f"bad-buffer-{op}-{buf:04x}", op=op, buffer=buf, status=2, commands=0)
    for pathptr in (0x3FFF, 0x7EFA, 0xC030, 0xFFF8):
        add(f"bad-path-{pathptr:04x}", status=2, commands=0)
        result[-1]["record"] = descriptor(path=pathptr)
    for n in (0, 2, 65):
        add(f"bad-path-length-{n}", status=2, commands=0)
        result[-1]["record"] = descriptor(pathlen=n)
    for path in (b"/INPUT.BIN!", b"/IN\0UT.BIN\0", b"INPUT.BIN\0",
                 b"/IN\\UT.BIN\0", b"/IN\nUT.BIN\0"):
        add(f"bad-path-text-{len(result)}", path=path, status=2, commands=0)
    for field in ({"version": 2}, {"reserved": 1}, {"tail": 1}, {"op": 3}, {"op": 0}):
        add(f"bad-schema-{len(result)}", status=2, commands=0, **field)
    add("write-offset", op=2, offset=1, status=2, commands=0)
    add("offset-wrap", offset=0xFFFFFFF0, status=2, commands=0)
    add("busy", busy=1, status=5, commands=0)
    add("unsupported-mode", status=6, commands=0)
    result[-1]["ga"] = 0x8F
    # Faults affect a copied response AFTER a real command, not the emulator.
    for fault, name, status, commands in ((1, "read-echo", 4, 4),
            (2, "read-frame-length", 4, 4), (3, "read-overcount", 4, 4),
            (4, "read-error", 3, 4), (6, "seek-error", 3, 3),
            (9, "read-empty-response", 4, 4), (10, "read-truncated-header", 4, 4),
            (11, "read-wrong-echo-high", 4, 4), (12, "real-read-bad-fd", 3, 4)):
        add(name, fault=fault, status=status, commands=commands)
    add("write-error", op=2, path=b"/FAULT.BIN\0", fault=5, status=3)
    add("real-write-bad-fd", op=2, path=b"/BADFD.BIN\0", fault=13, status=3)
    add("recovery-read", expected=INPUT[:128])
    if variant in ("storage-close-error", "storage-open-error"):
        is_close = variant == "storage-close-error"
        add("uncertain-close" if is_close else "uncertain-open",
            fault=7 if is_close else 8, status=3 if is_close else 4,
            commands=4 if is_close else 1, offline=1)
        add("offline-reject", status=7, commands=0, offline=1)
    return result


def rounds(variant):
    return 1 if variant in ("storage-close-error", "storage-open-error") else ROUNDS


def emit_vectors(path: Path, variant="storage"):
    rows = ["storage_cases"]
    paths = list(dict.fromkeys(case["path"] for case in cases(variant)))
    for case in cases(variant):
        prefix = case["record"] + bytes((case["status"], case["fault"]))
        prefix += struct.pack("<HHBBBBHHH", case["pointer"], case["length"],
                              case["ga"], case["slot"], case["bank"], case["busy"],
                              case["pathseed"], case["bufseed"], case["observe"])
        rows += [f"; {case['name']}", "db " + ",".join(f"#{b:02X}" for b in prefix),
                 f"dw storage_path_{paths.index(case['path'])}",
                 f"dw {case['actual']},{case['commands']}", f"db {case['offline']},0"]
    for index, value in enumerate(paths):
        rows += [f"storage_path_{index}", f"db {len(value)}",
                 "db " + ",".join(f"#{b:02X}" for b in value)]
    rows += ["storage_payload", "db " + ",".join(f"#{b:02X}" for b in PAYLOAD),
             f"storage_case_count equ {len(cases(variant))}", "storage_case_size equ 40",
             f"storage_rounds equ {rounds(variant)}"]
    path.write_text("\n".join(rows) + "\n")


def seeded_page(case):
    page = bytearray(b"\x5A" * 16384)
    start = 0x7EF0 if case["pointer"] == 0x7EF0 else 0x4000
    page[start-0x4000:start-0x4000+16] = case["record"]
    start = case["pathseed"] - 0x4000
    page[start:start+len(case["path"])] = case["path"]
    start = case["bufseed"] - 0x4000
    page[start:start+128] = PAYLOAD
    return page


def expected_page(case):
    page = seeded_page(case)
    if case["expected"] is not None:
        buf = int.from_bytes(case["record"][6:8], "little") - 0x4000
        if case["expected"]:
            page[buf:buf+len(case["expected"])] = case["expected"]
    return page


def verify_storage(header, ram, sym, raw, variant="storage"):
    def byte(name):
        return ram[sym[name]]
    def word(name):
        return int.from_bytes(ram[sym[name]:sym[name]+2], "little")
    if ram[sym["magic"]:sym["magic"]+6] != b"CPF3C\x01":
        raise AssertionError("storage probe did not boot")
    if byte("phase") != 0xA5 or byte("failure"):
        raise AssertionError(f"storage phase={byte('phase'):02X} failure={byte('failure')}, case={byte('case_index')}")
    vectors = cases(variant)
    total_rounds = rounds(variant)
    if len(ram) != 512*1024 or byte("rounds_done") != total_rounds:
        raise AssertionError("incomplete storage rounds/memory")
    if word("request_count") != total_rounds*len(vectors):
        raise AssertionError("incomplete storage requests")
    if word("command_count") != 1 + total_rounds*sum(c["commands"] for c in vectors):
        raise AssertionError("unexpected storage command count")
    if total_rounds > 1 and word("irq_count") < len(vectors)*(total_rounds//2):
        raise AssertionError("missing real interrupt coverage")
    if (header[0x41], header[0x40], header[0x55]) != (0, 0x0D, 7):
        raise AssertionError("final bank/ROM/video not restored")
    if header[0x1B:0x1D] != b"\0\0" or header[0x25] != 1:
        raise AssertionError("final interrupt context")
    if word("final_sp") != sym["main_stack_top"] or int.from_bytes(header[0x21:0x23], "little") != sym["main_stack_top"]:
        raise AssertionError("unbalanced storage stack")
    for key, address in sym.items():
        if key.endswith("_guard_low") or key.endswith("_guard_high"):
            if ram[address:address+16] != b"\xD7"*16:
                raise AssertionError(f"{key} guard damaged")
    for stem in ("main", "irq"):
        stack = ram[sym[f"{stem}_stack"]:sym[f"{stem}_stack_top"]]
        used = len(stack)-next((i for i, b in enumerate(stack) if b != 0xA6), len(stack))
        if used != word(f"{stem}_stack_used") or used >= len(stack):
            raise AssertionError(f"{stem} stack measurement")
    if ram[0x8000:sym["code_end"]] != raw[:sym["code_end"]-0x8000]:
        raise AssertionError("resident storage code changed")
    if ram[0xC000:0x10000] != bytes((a>>8) ^ (a&255) for a in range(0xC000, 0x10000)):
        raise AssertionError("framebuffer changed by storage")
    last_by_bank = {}
    for i, case in enumerate(vectors):
        row = ram[TRACE_START+i*TRACE_SIZE:TRACE_START+(i+1)*TRACE_SIZE]
        expected = bytes((case["status"], (total_rounds-1)&1, case["bank"], case["ga"],
                          case["slot"]))
        if row[:5] != expected:
            raise AssertionError(f"storage trace state {case['name']}: {row[:5].hex()} != {expected.hex()}")
        if row[6:8] != bytes((case["offline"], case["busy"])):
            raise AssertionError(f"storage lock/offline {case['name']}")
        if not case["offline"] and row[5] != 0:
            raise AssertionError(f"storage handle leaked {case['name']}")
        if struct.unpack("<HH", row[8:12]) != (case["actual"], case["commands"]):
            raise AssertionError(f"storage transfer/commands {case['name']}")
        page = expected_page(case)
        start = case["observe"]-0x4000
        if row[12:140] != page[start:start+128]:
            raise AssertionError(f"storage bytes {case['name']}")
        if row[140:144] != b"\x5A"*4:
            raise AssertionError(f"caller boundary {case['name']}")
        last_by_bank[case["bank"]] = page
    for tag, physical in ((0xC0, 0x4000), (0xC4, 0x10000), (0xC5, 0x14000)):
        if ram[physical:physical+16384] != last_by_bank[tag]:
            raise AssertionError(f"caller page {tag:02X} changed")
    # All unused expansion pages, including the deliberately mapped F7 service
    # page, are poisoned. None may be used for caller data or ROM responses.
    if ram[0x18000:0x80000] != b"\xA9"*(0x80000-0x18000):
        raise AssertionError("service/unused expansion page changed")
    return dict(rounds=total_rounds, requests=word("request_count"),
                commands=word("command_count"), interrupts=word("irq_count"),
                byte_checkpoints=len(vectors), main_stack_bytes=word("main_stack_used"),
                irq_stack_bytes=word("irq_stack_used"),
                resident_code_bytes=sym["code_end"]-0x8000,
                adapter_bytes=sym["storage_driver_end"]-sym["storage_gate"],
                offline=byte("io_offline"))


def verify_files(image: Path):
    hashes = {}
    expected = {**FILES, "OUTPUT.BIN": PAYLOAD, "ZERO.BIN": b"", "FAULT.BIN": PAYLOAD,
                "BADFD.BIN": b""}
    for name, content in expected.items():
        data = subprocess.check_output(["mtype", "-i", str(image)+"@@16384", f"::/{name}"])
        if data != content:
            raise AssertionError(f"M4 file bytes differ: {name}")
        hashes[name] = hashlib.sha256(data).hexdigest()
    # Invalid requests must not create a path; read errors must not modify input.
    missing = subprocess.run(["mtype", "-i", str(image)+"@@16384", "::/ABSENT.BIN"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if missing.returncode == 0:
        raise AssertionError("invalid/missing request created a file")
    return hashes
