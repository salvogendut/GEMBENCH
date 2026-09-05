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
GBLIB_SYMBOLS="${GBLIB_SYMBOLS:-$APP/gblib.symbols}"
GBLIB_UNIVERSAL="lib/gb/gblib_universal.symbols"
APP_CFLAGS="${APP_CFLAGS:-}"
UNIVERSAL_TASK="${UNIVERSAL_TASK:-0}"
UNIVERSAL_WINDOW_KIND="${UNIVERSAL_WINDOW_KIND:-0}"
UNIVERSAL_ACCESSORY="${UNIVERSAL_ACCESSORY:-0}"
UNIVERSAL_MENU="${UNIVERSAL_MENU:-0}"
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
    "$UNIVERSAL_MENU"; do
    [ "$feature" = 0 ] || [ "$feature" = 1 ] || {
        echo "ERROR: universal feature flags must be 0 or 1" >&2
        exit 2
    }
done

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"
work="build/universal-obj/$(basename "$APP")"
mkdir -p "$work" "$(dirname "$OUT")"

icon_args=("$APP_ICON")
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

python3 tools/gblib_subset.py lib/gb/gblib.s "$work/gblib.s" \
    "$GBLIB_UNIVERSAL" "$GBLIB_SYMBOLS"
"$SDAS" -o "$work/crt0_v4.rel" lib/gb/crt0_v4.s
"$SDAS" -o "$work/gbsys.rel" lib/gb/gbsys.s
"$SDAS" -o "$work/gblib.rel" "$work/gblib.s"
"$SDAS" -o "$work/gbuniversal_draw.rel" lib/gb/gbuniversal_draw.s
extra_rels=()
if [ "$UNIVERSAL_TASK" = 1 ]; then
    "$SDAS" -o "$work/gbtask.rel" lib/gb/gbtask.s
    extra_rels+=("$work/gbtask.rel")
fi
if [ "$UNIVERSAL_WINDOW_KIND" = 1 ]; then
    "$SDAS" -o "$work/gbwindow_kind.rel" lib/gb/gbwindow_kind.s
    extra_rels+=("$work/gbwindow_kind.rel")
fi
if [ "$UNIVERSAL_ACCESSORY" = 1 ]; then
    "$SDAS" -o "$work/gbdefer.rel" lib/gembench/gbdefer.s
    "$SDAS" -o "$work/gbshell_accessory_register.rel" \
        lib/gembench/gbshell_accessory_register.s
    extra_rels+=("$work/gbdefer.rel" "$work/gbshell_accessory_register.rel")
fi
if [ "$UNIVERSAL_MENU" = 1 ]; then
    "$SDCC" -mz80 --std-c99 --opt-code-size --fomit-frame-pointer \
        -DGB_UNIVERSAL -I lib/gb -c lib/gb/gbuniversal_menu.c \
        -o "$work/gbuniversal_menu.rel"
    extra_rels+=("$work/gbuniversal_menu.rel")
fi
"$SDCC" -mz80 --std-c99 --opt-code-size --fomit-frame-pointer \
    -DGB_UNIVERSAL $APP_CFLAGS -I lib/gb -I include/gembench \
    -c "$APP/main.c" -o "$work/main.rel"
"$SDCC" -mz80 --std-c99 --opt-code-size --fomit-frame-pointer \
    -DGB_UNIVERSAL -I lib/gb -c lib/gb/gbuniversal.c -o "$work/gbuniversal.rel"

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
        "$APP_ICON16" "$work/app.raw" "$OUT"
else
    python3 tools/embed_app_icon.py inject-v4 "$APP_MANIFEST" "$APP_ICON" \
        "$work/app.raw" "$OUT"
fi

python3 tools/check_universal_app.py --source "$APP" --asm "$work/main.asm" \
    --map "$work/app.map"
python3 tools/embed_app_icon.py check "$OUT"
echo "Built universal $OUT ($(stat -c%s "$OUT") bytes, $(sha256sum "$OUT" | cut -d' ' -f1))"
