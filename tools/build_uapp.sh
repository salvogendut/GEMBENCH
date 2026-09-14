#!/usr/bin/env bash
# Build one GEOBENCH-2 compile-once GBAP v4 application. This host-side gate
# emits a byte-stable package; kernels do not execute it until they implement
# and advertise the v6 universal loader contract.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-apps/abiprobe}"
OUT="${2:-build/universal/ABIPROBE.APP}"
APP_MANIFEST="${APP_MANIFEST:-$APP/manifest.json}"
APP_ICON="${APP_ICON:-$APP/icon.asm}"
APP_ICON16="${APP_ICON16:-}"
APP_SECONDARY="${APP_SECONDARY:-}" # packaged code only; no secondary-call service implied
GBLIB_SYMBOLS="${GBLIB_SYMBOLS:-$APP/gblib.symbols}"
GBLIB_UNIVERSAL="lib/gb/gblib_universal.symbols"
APP_CFLAGS="${APP_CFLAGS:-}"
UNIVERSAL_TASK="${UNIVERSAL_TASK:-0}"
UNIVERSAL_WINDOW_KIND="${UNIVERSAL_WINDOW_KIND:-0}"
UNIVERSAL_ACCESSORY="${UNIVERSAL_ACCESSORY:-0}"
UNIVERSAL_MENU="${UNIVERSAL_MENU:-0}"
UNIVERSAL_FS="${UNIVERSAL_FS:-0}"
UNIVERSAL_FS_IDENTITY="${UNIVERSAL_FS_IDENTITY:-0}"
UNIVERSAL_SCRAP="${UNIVERSAL_SCRAP:-0}"
UNIVERSAL_DOCIO="${UNIVERSAL_DOCIO:-0}"
UNIVERSAL_FILEPICK="${UNIVERSAL_FILEPICK:-0}"
UNIVERSAL_DATA_PAGES="${UNIVERSAL_DATA_PAGES:-0}"
UNIVERSAL_COMPUTE="${UNIVERSAL_COMPUTE:-0}"
UNIVERSAL_IX="${UNIVERSAL_IX:-0}" # opt-in preserved kernel IX + compact C frames
UNIVERSAL_MINIMAL="${UNIVERSAL_MINIMAL:-0}"
UNIVERSAL_MENU_BORROWED="${UNIVERSAL_MENU_BORROWED:-0}"
DATA_LOC="${DATA_LOC:-0x7000}"
LOAD_LIMIT="0x7F00"

for path in "$APP/main.c" "$APP_MANIFEST" "$APP_ICON" "$GBLIB_SYMBOLS" \
    "$GBLIB_UNIVERSAL"; do
    [ -f "$path" ] || { echo "ERROR: missing universal input $path" >&2; exit 1; }
done
case " ${APPDEFS:-} ${GLOBAL_APPDEFS:-} $APP_CFLAGS " in
    *GB_MSX2*|*GB_PCW*|*PLATFORM_MSX*|*PLATFORM_CPC*|*PLATFORM_PCW*)
        echo "ERROR: target build defines are forbidden for a universal APP" >&2
        exit 2
        ;;
esac
if [[ ! "$DATA_LOC" =~ ^(0[xX][0-9A-Fa-f]+|[1-9][0-9]*|0)$ ]]; then
    echo "ERROR: universal DATA_LOC must be a hexadecimal or decimal address" >&2
    exit 2
fi
if (( DATA_LOC < 0x4000 || DATA_LOC > 0x7F00 )); then
    echo "ERROR: universal DATA_LOC must be in 0x4000..0x7F00" >&2
    exit 2
fi
for feature in "$UNIVERSAL_TASK" "$UNIVERSAL_WINDOW_KIND" "$UNIVERSAL_ACCESSORY" \
    "$UNIVERSAL_MENU" "$UNIVERSAL_FS" "$UNIVERSAL_FS_IDENTITY" "$UNIVERSAL_SCRAP" \
    "$UNIVERSAL_DOCIO" "$UNIVERSAL_FILEPICK" "$UNIVERSAL_DATA_PAGES" "$UNIVERSAL_COMPUTE" "$UNIVERSAL_IX" \
    "$UNIVERSAL_MINIMAL" "$UNIVERSAL_MENU_BORROWED"; do
    [ "$feature" = 0 ] || [ "$feature" = 1 ] || {
        echo "ERROR: universal feature flags must be 0 or 1" >&2
        exit 2
    }
done
if { [ "$UNIVERSAL_DOCIO" = 1 ] || [ "$UNIVERSAL_FILEPICK" = 1 ] || [ "$UNIVERSAL_FS_IDENTITY" = 1 ]; } && [ "$UNIVERSAL_FS" != 1 ]; then
    echo "ERROR: universal document I/O and file picker require UNIVERSAL_FS=1" >&2
    exit 2
fi

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"
work="build/universal-obj/$(basename "$APP")"
mkdir -p "$work" "$(dirname "$OUT")"

icon_args=("$APP_ICON")
secondary_args=()
if [ -n "$APP_SECONDARY" ]; then
    [ -f "$APP_SECONDARY" ] || { echo "ERROR: missing secondary payload $APP_SECONDARY" >&2; exit 1; }
    secondary_args=(--secondary "$APP_SECONDARY")
fi
# This SDK emits GB_PARAMS calls. Do not allow a manifest to claim ABI 2.0
# compatibility: an older loader must reject it before reaching application code.
python3 - "$APP_MANIFEST" <<'PY'
import json, sys
spec = json.load(open(sys.argv[1]))
if spec.get("minimum_abi") != [2, 1] or "caller-parameters" not in spec.get("required_capabilities", []):
    raise SystemExit("ERROR: this SDK requires minimum_abi [2, 1] and caller-parameters")
PY
if [ -n "$APP_ICON16" ]; then
    [ -f "$APP_ICON16" ] || { echo "ERROR: missing APP_ICON16 $APP_ICON16" >&2; exit 1; }
    icon_args+=("$APP_ICON16")
fi
preamble_size=$(python3 tools/embed_app_icon.py size-v4 \
    "$APP_MANIFEST" "${icon_args[@]}")
CODE_LOC=$(printf '0x%X' $((0x4000 + preamble_size)))

# Universal apps can run with interrupts enabled on every target. Never pop a
# two-byte word and rewind SP to consume one byte: an IRQ can overwrite the
# caller's next live stack byte (e.g. Clock's saved digit X coordinate).
python3 tools/gblib_subset.py --interrupt-safe lib/gb/gblib.s "$work/gblib.s" \
    "$GBLIB_UNIVERSAL" "$GBLIB_SYMBOLS"
app_frames=(--fomit-frame-pointer)
app_optimization=()
minimal_flags=()
menu_flags=()
[ "$UNIVERSAL_MINIMAL" = 0 ] || minimal_flags=(-DGB_UNIVERSAL_MINIMAL)
[ "$UNIVERSAL_MENU_BORROWED" = 0 ] || menu_flags=(-DGB_UNIVERSAL_POPUP_BORROWED)
sys_source=lib/gb/gbsys.s
kind_source=lib/gb/gbwindow_kind.s
if [ "$UNIVERSAL_IX" = 1 ]; then
    app_frames=()
    app_optimization=(--max-allocs-per-node 100000)
    python3 tools/preserve_kernel_ix.py "$work/gblib.s" "$work/gblib.s"
    python3 tools/preserve_kernel_ix.py lib/gb/gbsys.s "$work/gbsys.s"
    python3 tools/preserve_kernel_ix.py lib/gb/gbwindow_kind.s "$work/gbwindow_kind.s"
    sys_source="$work/gbsys.s";kind_source="$work/gbwindow_kind.s"
fi
"$SDAS" -o "$work/crt0_v4.rel" lib/gb/crt0_v4.s
"$SDAS" -o "$work/gbsys.rel" "$sys_source"
"$SDAS" -o "$work/gblib.rel" "$work/gblib.s"
"$SDAS" -o "$work/gbuniversal_draw.rel" lib/gb/gbuniversal_draw.s
extra_rels=()
if [ "$UNIVERSAL_COMPUTE" = 1 ]; then
    python3 - "$APP_MANIFEST" "$APP_SECONDARY" <<'PY'
import hashlib, json, pathlib, sys
spec=json.load(open(sys.argv[1]))
if "portable-secondary-calls" not in spec["required_capabilities"]:
    raise SystemExit("ERROR: UNIVERSAL_COMPUTE requires portable-secondary-calls")
if not sys.argv[2]: raise SystemExit("ERROR: UNIVERSAL_COMPUTE requires an audited APP_SECONDARY")
image=pathlib.Path(sys.argv[2]); record=json.loads(image.with_suffix(image.suffix+'.audit.json').read_text())
if record.get('profile')!='gbs4-computation-v1' or record.get('sha256')!=hashlib.sha256(image.read_bytes()).hexdigest():
    raise SystemExit("ERROR: secondary audit does not match payload")
PY
    "$SDCC" -mz80 --std-c99 --opt-code-size "${app_frames[@]}" \
        -DGB_UNIVERSAL -I lib/gb -I include/gembench \
        -c lib/gembench/gbcompute.c -o "$work/gbcompute.rel"
    python3 tools/check_universal_app.py --source lib/gembench/gbcompute.c --asm "$work/gbcompute.asm"
    extra_rels+=("$work/gbcompute.rel")
fi
if [ "$UNIVERSAL_DATA_PAGES" = 1 ]; then
    python3 - "$APP_MANIFEST" <<'PY'
import json, sys
if "portable-data-pages" not in json.load(open(sys.argv[1]))["required_capabilities"]:
    raise SystemExit("ERROR: UNIVERSAL_DATA_PAGES requires portable-data-pages in the manifest")
PY
    "$SDCC" -mz80 --std-c99 --opt-code-size "${app_frames[@]}" \
        -DGB_UNIVERSAL -I lib/gb -I include/gembench \
        -c lib/gembench/gbdatapage.c -o "$work/gbdatapage.rel"
    python3 tools/check_universal_app.py --source lib/gembench/gbdatapage.c \
        --asm "$work/gbdatapage.asm"
    extra_rels+=("$work/gbdatapage.rel")
fi
if [ "$UNIVERSAL_SCRAP" = 1 ]; then
    python3 - "$APP_MANIFEST" <<'PY'
import json, sys
if "typed-clipboard" not in json.load(open(sys.argv[1]))["required_capabilities"]:
    raise SystemExit("ERROR: UNIVERSAL_SCRAP requires typed-clipboard in the manifest")
PY
    "$SDCC" -mz80 --std-c99 --opt-code-size "${app_frames[@]}" \
        -DGB_UNIVERSAL -I lib/gb -I include/gembench \
        -c lib/gembench/gbscrap_universal.c -o "$work/gbscrap_universal.rel"
    extra_rels+=("$work/gbscrap_universal.rel")
fi
if [ "$UNIVERSAL_FS" = 1 ]; then
    python3 - "$APP_MANIFEST" <<'PY'
import json, sys
if "portable-filesystem" not in json.load(open(sys.argv[1]))["required_capabilities"]:
    raise SystemExit("ERROR: UNIVERSAL_FS requires portable-filesystem in the manifest")
PY
    for unit in gbfsctx gbfsctx_universal; do
        fs_flags=()
        [ "$UNIVERSAL_MINIMAL" = 0 ] || fs_flags=(-DGB_FSCTX_BATCH_ONLY -DGB_FSCTX_DOCUMENT_ONLY)
        "$SDCC" -mz80 --std-c99 --opt-code-size "${app_frames[@]}" \
            -DGB_UNIVERSAL "${fs_flags[@]}" -I lib/gb -I include/gembench \
            -c "lib/gembench/$unit.c" -o "$work/$unit.rel"
        extra_rels+=("$work/$unit.rel")
    done
fi
document_units=()
[ "$UNIVERSAL_FS_IDENTITY" = 0 ] || document_units+=(gbfsctx_identity)
[ "$UNIVERSAL_DOCIO" = 0 ] || document_units+=(gbdocio)
[ "$UNIVERSAL_FILEPICK" = 0 ] || document_units+=(gbfilepick gbfilepick_ui)
for unit in "${document_units[@]}"; do
    doc_flags=()
    if [ "$UNIVERSAL_MINIMAL" = 1 ] && [ "$unit" = gbdocio ]; then doc_flags=(-DGB_DOCIO_CHUNKS_ONLY); fi
    # Model/I/O call only the IX-preserving GB_PARAMS filesystem bridge.
    # Keep IX frames there for substantially smaller struct access. Rendering
    # still requires the IY profile: legacy drawing leaves IX as scratch.
    frame_flags=()
    [ "$unit" != gbfilepick_ui ] || frame_flags+=("${app_frames[@]}")
    "$SDCC" -mz80 --std-c99 --opt-code-size --max-allocs-per-node 100000 \
        "${frame_flags[@]}" "${doc_flags[@]}" -DGB_UNIVERSAL -I lib/gb -I include/gembench \
        -c "lib/gembench/$unit.c" -o "$work/$unit.rel"
    python3 tools/check_universal_app.py --source "lib/gembench/$unit.c" \
        --asm "$work/$unit.asm"
    extra_rels+=("$work/$unit.rel")
done
if [ "$UNIVERSAL_TASK" = 1 ]; then
    "$SDAS" -o "$work/gbtask.rel" lib/gb/gbtask.s
    extra_rels+=("$work/gbtask.rel")
fi
if [ "$UNIVERSAL_WINDOW_KIND" = 1 ]; then
    "$SDAS" -o "$work/gbwindow_kind.rel" "$kind_source"
    extra_rels+=("$work/gbwindow_kind.rel")
fi
if [ "$UNIVERSAL_ACCESSORY" = 1 ]; then
    "$SDAS" -o "$work/gbdefer.rel" lib/gembench/gbdefer.s
    "$SDAS" -o "$work/gbshell_accessory_register.rel" \
        lib/gembench/gbshell_accessory_register.s
    extra_rels+=("$work/gbdefer.rel" "$work/gbshell_accessory_register.rel")
fi
if [ "$UNIVERSAL_MENU" = 1 ]; then
    "$SDCC" -mz80 --std-c99 --opt-code-size "${app_frames[@]}" \
        -DGB_UNIVERSAL "${menu_flags[@]}" -I lib/gb -c lib/gb/gbuniversal_menu.c \
        -o "$work/gbuniversal_menu.rel"
    extra_rels+=("$work/gbuniversal_menu.rel")
fi
"$SDCC" -mz80 --std-c99 --opt-code-size "${app_optimization[@]}" "${app_frames[@]}" \
    -DGB_UNIVERSAL $APP_CFLAGS -I lib/gb -I include/gembench \
    -c "$APP/main.c" -o "$work/main.rel"
"$SDCC" -mz80 --std-c99 --opt-code-size "${app_frames[@]}" \
    -DGB_UNIVERSAL "${minimal_flags[@]}" -I lib/gb -c lib/gb/gbuniversal.c -o "$work/gbuniversal.rel"

"$SDCC" -mz80 --no-std-crt0 --code-loc "$CODE_LOC" --data-loc "$DATA_LOC" \
    "$work/crt0_v4.rel" "$work/main.rel" "$work/gbuniversal.rel" \
    "$work/gbsys.rel" "$work/gblib.rel" "$work/gbuniversal_draw.rel" \
    "${extra_rels[@]}" -o "$work/app.ihx"
python3 tools/check_app_layout.py "$work/app.map" --app "$APP" \
    --data-loc "$DATA_LOC" --load-limit "$LOAD_LIMIT" --task-stack-reserve 256

"$MAKEBIN" -p "$work/app.ihx" "$work/app.bin"
tail -c +16385 "$work/app.bin" > "$work/app.raw"
if [ -n "$APP_ICON16" ]; then
    python3 tools/embed_app_icon.py inject-v4 "$APP_MANIFEST" "$APP_ICON" \
        "$APP_ICON16" "$work/app.raw" "$OUT" "${secondary_args[@]}"
else
    python3 tools/embed_app_icon.py inject-v4 "$APP_MANIFEST" "$APP_ICON" \
        "$work/app.raw" "$OUT" "${secondary_args[@]}"
fi

python3 tools/check_universal_app.py --source "$APP" --asm "$work/main.asm" \
    --map "$work/app.map"
python3 tools/embed_app_icon.py check "$OUT"
echo "Built universal $OUT ($(stat -c%s "$OUT") bytes, $(sha256sum "$OUT" | cut -d' ' -f1))"
