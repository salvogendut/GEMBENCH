#!/usr/bin/env bash
# tools/fetch_msx_deps.sh - fetch the external pieces the MSX2 target needs for
# emulator testing (issue #287). Everything lands outside the git tree:
#
#   QA/MSXDEPS/            (git-ignored)  Nextor system files for image staging:
#     NEXTOR.SYS COMMAND2.COM UNAPINET.COM
#   ~/.openMSX/share/systemroms/          ROMs openMSX identifies by sha1:
#     Nextor-2.1.1.SunriseIDE.ROM         (matches the bundled SunriseIDE_Nextor
#                                          extension's expected sha1)
#     nms8250_basic-bios2.rom nms8250_msx2sub.rom nms8250_disk.rom
#                                         (Philips NMS 8250 system ROMs, carved
#                                          by sha1 out of the MiSter MSX pack)
#
# Nextor is (c) Konamiman, distributed via its GitHub releases (COMMAND2.COM is
# licensed for distribution with Nextor). The NMS 8250 ROMs are copyrighted
# Philips firmware fetched from the archive.org MiSter BIOS pack - fetching
# them is the user's call, so this script asks unless FETCH_ROMS=1.
set -euo pipefail
cd "$(dirname "$0")/.."

DEPS=QA/MSXDEPS
ROMS="$HOME/.openMSX/share/systemroms"
NEXTOR_ROM_VER=v2.1.1        # must match the sha1 in openMSX's SunriseIDE_Nextor.xml
NEXTOR_SYS_VER=v2.1.3        # newest release that ships NEXTOR.SYS
NEXTOR_TOOLS_VER=v2.1.0      # newest release that ships tools.zip (COMMAND2.COM)
OPENMSXNET_VER=v0.9.7
UNAPINET_SHA256=86e7bb27d1f020e235929a6806f5f2dc8188c458119041c4017afd93a3c13227

mkdir -p "$DEPS" "$ROMS"

fetch() { # url dest
    [ -s "$2" ] && { echo "have  $2"; return; }
    echo "fetch $2"
    curl -sfL -o "$2" "$1"
}

verify_sha256() { # path expected
    local actual
    actual="$(python3 - "$1" <<'PY'
import hashlib, sys
with open(sys.argv[1], "rb") as source:
    print(hashlib.sha256(source.read()).hexdigest())
PY
)"
    [ "$actual" = "$2" ] || {
        echo "ERROR: SHA-256 mismatch for $1" >&2
        echo "expected $2" >&2
        echo "actual   $actual" >&2
        exit 1
    }
}

# --- Nextor kernel ROM + system files ---------------------------------------
fetch "https://github.com/Konamiman/Nextor/releases/download/$NEXTOR_ROM_VER/Nextor-2.1.1.SunriseIDE.ROM" \
      "$ROMS/Nextor-2.1.1.SunriseIDE.ROM"
fetch "https://github.com/Konamiman/Nextor/releases/download/$NEXTOR_SYS_VER/NEXTOR.SYS" \
      "$DEPS/NEXTOR.SYS"
if [ ! -s "$DEPS/COMMAND2.COM" ]; then
    fetch "https://github.com/Konamiman/Nextor/releases/download/$NEXTOR_TOOLS_VER/tools.zip" \
          "$DEPS/tools.zip"
    unzip -o -q "$DEPS/tools.zip" COMMAND2.COM -d "$DEPS"
    rm -f "$DEPS/tools.zip"
    echo "have  $DEPS/COMMAND2.COM"
fi

# --- openMSXnet TCP/IP UNAPI guest driver ----------------------------------
# This is the guest half of the port-mapped host bridge. It remains in the
# ignored dependency/staging directories and is never committed to GeoBench.
fetch "https://github.com/antxiko/openMSXnet/releases/download/$OPENMSXNET_VER/UNAPINET.COM" \
      "$DEPS/UNAPINET.COM"
verify_sha256 "$DEPS/UNAPINET.COM" "$UNAPINET_SHA256"

# --- Philips NMS 8250 system ROMs (sha1-carved from the MiSter BIOS pack) ----
need_roms=0
for r in nms8250_basic-bios2.rom nms8250_msx2sub.rom nms8250_disk.rom; do
    [ -s "$ROMS/$r" ] || need_roms=1
done
if [ "$need_roms" = 1 ]; then
    if [ "${FETCH_ROMS:-0}" != 1 ]; then
        echo "The Philips NMS 8250 system ROMs are copyrighted firmware." >&2
        echo "Re-run with FETCH_ROMS=1 to download and carve them from the" >&2
        echo "archive.org MiSter MSX BIOS pack, or drop your own dumps into" >&2
        echo "$ROMS (openMSX matches them by sha1, any filename)." >&2
        exit 1
    fi
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    fetch "https://archive.org/download/mistermsxbiosFW/Philips_NMS_8250.MSX" "$tmp/NMS8250.MSX"
    python3 - "$tmp/NMS8250.MSX" "$ROMS" <<'EOF'
import hashlib, sys, os
data = open(sys.argv[1], 'rb').read()
out = sys.argv[2]
targets = {  # sha1s from openMSX's Philips_NMS_8250.xml
 '6103b39f1e38d1aa2d84b1c3219c44f1abb5436e': ('nms8250_basic-bios2.rom', 0x8000),
 '5c1f9c7fb655e43d38e5dd1fcc6b942b2ff68b02': ('nms8250_msx2sub.rom',     0x4000),
 'dab3e6f36843392665b71b04178aadd8762c6589': ('nms8250_disk.rom',        0x4000),
 'c3efedda7ab947a06d9345f7b8261076fa7ceeef': ('nms8250_disk.rom',        0x4000),
 '8625c6b633d9cca2875e4dc33404fb98653379d7': ('nms8250_disk.rom',        0x4000),
}
found = set()
for h, (name, size) in targets.items():
    for off in range(0, len(data) - size + 1):
        if hashlib.sha1(data[off:off+size]).hexdigest() == h:
            open(os.path.join(out, name), 'wb').write(data[off:off+size])
            print(f"carved {name} (offset {off:#x})")
            found.add(name)
            break
missing = {n for n, _ in targets.values()} - found
if missing:
    sys.exit(f"FAILED to carve: {missing}")
EOF
fi

echo "MSX deps ready: $DEPS (including UNAPINET.COM) + $ROMS"
