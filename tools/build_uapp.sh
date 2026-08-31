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

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"
work="build/universal-obj/$(basename "$APP")"
mkdir -p "$work" "$(dirname "$OUT")"

icon_args=("$APP_ICON")
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
"$SDCC" -mz80 --std-c99 --opt-code-size --fomit-frame-pointer \
    -DGB_UNIVERSAL $APP_CFLAGS -I lib/gb -c "$APP/main.c" -o "$work/main.rel"
"$SDCC" -mz80 --std-c99 --opt-code-size --fomit-frame-pointer \
    -DGB_UNIVERSAL -I lib/gb -c lib/gb/gbuniversal.c -o "$work/gbuniversal.rel"

"$SDCC" -mz80 --no-std-crt0 --code-loc "$CODE_LOC" --data-loc "$DATA_LOC" \
    "$work/crt0_v4.rel" "$work/main.rel" "$work/gbuniversal.rel" \
    "$work/gbsys.rel" "$work/gblib.rel" -o "$work/app.ihx"
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
