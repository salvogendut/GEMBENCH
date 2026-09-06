"""M4 directory/metadata protocol gate. Observations are not fake FS entries."""
from __future__ import annotations

BIG_SIZE = 0x12345
TRACE = 0x7E200  # F7:6200
STRIDE = 144


def transactions():
    return [
        ("root", 0x08, b"/\0"),
        ("catalog", 0x08, b"CATALOG\0"),
        ("path", 0x13, b""),
        ("legacy-start", 0x25, b"\0"),
        ("legacy-directory", 0x06, b""),
        ("extended-start", 0x25, b"\0"),
        ("extended-directory", 0x06, bytes((64,))),
        ("stat-directory", 0x16, b"EIGHTCHR\0"),
        ("stat-file", 0x16, b"BIG.BIN\0"),
        ("stat-missing", 0x16, b"MISSING.BIN\0"),
        ("open-file", 0x01, b"\x81BIG.BIN\0"),
        ("size-file", 0x11, bytes((3,))),
        ("close-file", 0x04, bytes((3,))),
        ("restore-root", 0x08, b"/\0"),
        ("restored-path", 0x13, b""),
    ]


def emit_vectors(path):
    lines = [f"DP_CASES equ {len(transactions())}", "dp_vectors"]
    for i, (_, _, args) in enumerate(transactions()):
        lines += [f"db {2+len(args)}", f"dw dp_packet_{i}"]
    for i, (_, command, args) in enumerate(transactions()):
        lines += [f"dp_packet_{i}", "db " + ",".join(map(str, bytes((command, 0x43)) + args))]
    path.write_text("\n".join(lines) + "\n")


def files():
    return {"CATALOG/BIG.BIN": bytes((i*13+11)&255 for i in range(BIG_SIZE))}


def observe(ram, sym):
    """Check transport/restoration first; report unmet protocol requirements.

    A missing facility is NOT a passing qualification. The runner saves the
    report and returns a nonzero exit status, retaining the raw response bytes.
    Only the first NUL-terminated long name is relevant to the directory test;
    FSTAT's separately documented short name, attributes and size are checked.
    """
    count = len(transactions())
    if ram[sym["dp_done"]] != count:
        raise AssertionError("directory protocol checkpoint count")
    if int.from_bytes(ram[sym["dp_commands"]:sym["dp_commands"]+2], "little") != count:
        raise AssertionError("directory protocol command accounting")
    responses = {}
    for i, (name, command, args) in enumerate(transactions()):
        at = TRACE+i*STRIDE
        raw = bytes(ram[at:at+136])
        meta = bytes(ram[at+136:at+STRIDE])
        if meta != bytes((0, 0xF7, 0x8D, 0, 0, 0, 1, 0)):
            raise AssertionError(f"directory protocol {name}: transport/bank/ROM/lock/IFF {meta.hex()}")
        size = raw[0]
        if not 2 <= size < 136 or raw[1:3] != bytes((command, 0x43)):
            raise AssertionError(f"directory protocol {name}: malformed frame {raw.hex()}")
        if raw[size+1:] != b"\xD7"*(135-size):
            raise AssertionError(f"directory protocol {name}: response overrun")
        responses[name] = {"command": f"43{command:02X}", "arguments_hex": args.hex(),
                           "response_hex": raw[:size+1].hex(), "payload": raw[3:size+1]}
    payload = lambda name: responses[name]["payload"]
    # Existing facilities are controls: a bad boot/path/file fixture must not
    # be reported as merely missing extended directory support.
    for name, want in (("path", b"/CATALOG\0"), ("restored-path", b"/\0"),
                       ("open-file", b"\x03\0"), ("close-file", b"\0"),
                       ("size-file", BIG_SIZE.to_bytes(4, "little"))):
        if payload(name) != want:
            raise AssertionError(f"directory protocol {name}: control differs {payload(name).hex()}")
    missing = []
    if payload("extended-directory").split(b"\0", 1)[0] != b">EIGHTCHR":
        missing.append("READDIR(max_name_len=64) did not preserve the full eight-character directory name")
    for name, short, size, directory in (("stat-directory", b"EIGHTCHR", 0, True),
                                         ("stat-file", b"BIG.BIN", BIG_SIZE, False)):
        data = payload(name)
        if len(data) < 23 or data[0] != 0:
            missing.append(f"{name}: FSTAT lacks its documented success/metadata payload")
        elif (int.from_bytes(data[1:5], "little") != size or
              bool(data[9]&0x10) != directory or
              data[10:23].split(b"\0", 1)[0] != short):
            missing.append(f"{name}: FSTAT size/attributes/short-name mismatch")
    if not payload("stat-missing") or payload("stat-missing")[0] == 0:
        missing.append("stat-missing: FSTAT did not return an explicit nonzero error")
    for row in responses.values():
        row.pop("payload")
    return {"directory_protocol_qualified": not missing, "missing_requirements": missing,
            "directory_protocol_commands": count, "responses": responses}
