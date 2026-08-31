#!/usr/bin/env bash
# Build a GEOBENCH C app with SDCC into a raw #4000 image - the same format as
# the RASM .RAW app binaries, so the kernel can incbin/package it identically.
#
# The C app is just apps/<name>/main.c; it reaches the kernel through the shared
# libgb (lib/gb/gblib.s + gb.h) and shared crt0 (lib/gb/crt0.s, the #4000 entry).
# Linked: crt0 FIRST (so _start is at #4000), then main, then the libgb trampolines.
# APP_ICON=<canonical 32x32 icon.asm> reserves a GBAP v1 preamble. Adding
# APP_ICON16=<native Screen-7 icon.asm> emits a GBAP v2 dual-icon preamble.
# APP_MANIFEST=<manifest.json> upgrades an MSX2 build to a guarded GBAP v3
# package. Its JP keeps the kernel's #4000 entry ABI unchanged in every format.
#
#   tools/build_capp.sh [app_dir] [out.RAW]
#   tools/build_capp.sh apps/chello build/CHELLO.RAW   (defaults)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-apps/clock}"
OUT="${2:-build/CLOCK.RAW}"
GB="lib/gb"                                 # shared libgb (gb.h, gblib.s, crt0.s)
GBR_LIB="lib/gembench"
GBR_INCLUDE="include/gembench"
GBLIB_SRC="${GBLIB_SRC:-$GB/gblib.s}"
APP_CFLAGS="${APP_CFLAGS:-}"
HELPER_CFLAGS="${HELPER_CFLAGS:-}"
GLOBAL_APPDEFS="${GLOBAL_APPDEFS:-}"
ALL_APPDEFS="$GLOBAL_APPDEFS ${APPDEFS:-}"
APP_ICON="${APP_ICON:-}"
APP_ICON16="${APP_ICON16:-}"
APP_MANIFEST="${APP_MANIFEST:-}"
APP_SECONDARY="${APP_SECONDARY:-}"
LOAD_LIMIT="${LOAD_LIMIT:-0x7F00}"
TASK_STACK_RESERVE="${TASK_STACK_RESERVE:-0}"
TASK_FLAG="${TASK:-0}"
TASK_ROOT_FLAG="${TASK_ROOT:-0}"
TASK_RUNTIME_RAW="${TASK_RUNTIME_RAW:-}"
# DATA_LOC: where this app's data starts (code is #4000.. below it, data ..#7FFF
# above). The default 0x6200 is a 50/50 split; a code-heavy/data-light app (NOTEPAD)
# can pass a higher value to trade its spare data room for code room. Per-app so a
# data-heavy app (VIEWER) keeps the low split. (#97)
DATA_LOC="${DATA_LOC:-0x6200}"

case " $ALL_APPDEFS " in
    *" -DGB_MSX2 "*) ;;
    *) echo "ERROR: GEOBENCH applications only build for MSX2 (-DGB_MSX2 required)" >&2; exit 2 ;;
esac
case " $ALL_APPDEFS " in
    *" -DGB_PCW "*) echo "ERROR: the PCW target is retired; see archive/cpc-pcw-targets" >&2; exit 2 ;;
esac

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"   # sdasz80 / makebin sit beside sdcc
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"
CODE_LOC="0x4000"
CRT0_SRC="$GB/crt0.s"
# Adding icon16.asm beside an app-owned icon.asm automatically upgrades the
# MSX2 build to a dual-resource GBAP v2 header.
case " $ALL_APPDEFS " in
    *" -DGB_MSX2 "*)
        if [ -n "$APP_ICON" ] && [ -z "$APP_ICON16" ]; then
            icon16_candidate="$(dirname "$APP_ICON")/icon16.asm"
            [ ! -f "$icon16_candidate" ] || APP_ICON16="$icon16_candidate"
        fi
        ;;
esac
if [ -n "$APP_ICON16" ] && [ -z "$APP_ICON" ]; then
    echo "ERROR: APP_ICON16 requires the portable APP_ICON fallback" >&2
    exit 1
fi
if [ -n "$APP_MANIFEST" ]; then
    if [ -z "$APP_ICON" ]; then
        echo "ERROR: APP_MANIFEST requires the portable APP_ICON fallback" >&2
        exit 1
    fi
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: GBAP v3 guarded startup is currently MSX2-only" >&2; exit 1 ;;
    esac
    CRT0_SRC="$GB/crt0_v3_msx.s"
fi
if [ -n "$APP_SECONDARY" ]; then
    if [ -z "$APP_MANIFEST" ]; then
        echo "ERROR: APP_SECONDARY requires APP_MANIFEST" >&2
        exit 1
    fi
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: APP_SECONDARY is currently MSX2-only" >&2; exit 1 ;;
    esac
fi
if [ -n "$APP_ICON" ]; then
    icon_args=("$APP_ICON")
    if [ -n "$APP_ICON16" ]; then icon_args+=("$APP_ICON16"); fi
    if [ -n "$APP_MANIFEST" ]; then
        APP_PREAMBLE_SIZE=$(python3 tools/embed_app_icon.py size-v3 \
            "$APP_MANIFEST" "${icon_args[@]}")
    else
        APP_PREAMBLE_SIZE=$(python3 tools/embed_app_icon.py size "${icon_args[@]}")
    fi
    CODE_LOC=$(printf '0x%X' $((0x4000 + APP_PREAMBLE_SIZE)))
fi

work="build/msx-obj/$(basename "$APP")"
mkdir -p "$work"
mkdir -p "$(dirname "$OUT")"
. tools/build_cache.sh

DIALOGS_FLAG="${DIALOGS:-0}"
PROMPT_FLAG="${PROMPT:-0}"
PICKER_FLAG="${PICKER:-0}"
DOC_FLAG="${DOC:-0}"
DOCRO_FLAG="${DOCRO:-0}"
NET_FLAG="${NET:-0}"
GBWIN_FLAG="${GBWIN:-1}"
GBWIN_DRAG_ONLY_FLAG="${GBWIN_DRAG_ONLY:-0}"
WINDOW_KIND_FLAG="${WINDOW_KIND:-0}"
WIDGETS_FLAG="${WIDGETS:-0}"
BUTTON_FLAG="${BUTTON:-0}"
ACTIONS_FLAG="${ACTIONS:-0}"
SCROLL_FLAG="${SCROLL:-0}"
SCROLL16_FLAG="${SCROLL16:-0}"
TOGGLE_FLAG="${TOGGLE:-0}"
STEPPER_FLAG="${STEPPER:-0}"
SELECTOR_FLAG="${SELECTOR:-0}"
SLIDER_FLAG="${SLIDER:-0}"
FORM_FLAG="${FORM:-0}"
FORM_MODAL_ONLY_FLAG="${FORM_MODAL_ONLY:-0}"
FORM_SELECT_FLAG="${FORM_SELECT:-0}"
TIMESET_FLAG="${TIMESET:-0}"
SOUND_FLAG="${SOUND:-0}"
TITLEBAR_FLAG="${TITLEBAR:-0}"
SIZEPROMPT_FLAG="${SIZEPROMPT:-0}"
APP_PROBE_FLAG="${APP_PROBE:-0}"
if [ "$APP_PROBE_FLAG" != "0" ]; then
    echo "ERROR: APP_PROBE belonged to the retired CPC target" >&2
    exit 2
fi
REPAINTTOP_FLAG="${REPAINTTOP:-0}"
BASELINE_FLAG="${BASELINE:-0}"
SYS_FLAG="${SYS:-0}"
GB_SECONDARY_FLAG="${GB_SECONDARY:-0}"
if [ -n "$APP_SECONDARY" ]; then GB_SECONDARY_FLAG=1; fi
if [ "$GB_SECONDARY_FLAG" != "0" ] && [ "$GB_SECONDARY_FLAG" != "1" ]; then
    echo "ERROR: GB_SECONDARY must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_SECONDARY_FLAG" = "1" ] && [ -z "$APP_SECONDARY" ]; then
    echo "ERROR: GB_SECONDARY=1 requires APP_SECONDARY" >&2
    exit 1
fi
if [ "$GB_SECONDARY_FLAG" = "1" ]; then
    ALL_APPDEFS="$ALL_APPDEFS -DGB_SECONDARY_RUNTIME"
fi
GBR_READER_FLAG="${GBR_READER:-0}"
GBR_FIXED_TREE_FLAG="${GBR_FIXED_TREE:-0}"
GBR_EMBEDDED_FLAG="${GBR_EMBEDDED:-0}"
GBR_BANKED_FLAG="${GBR_BANKED:-0}"
GBR_OBJECT_FLAG="${GBR_OBJECTS:-0}"
if [ "$GBR_BANKED_FLAG" = "1" ]; then GBR_READER_FLAG=1; fi
if [ "$GBR_EMBEDDED_FLAG" = "1" ]; then GBR_READER_FLAG=1; fi
GBR_FORM_FLAG="${GBR_FORMS:-0}"
if [ "$GBR_FORM_FLAG" = "1" ]; then GBR_OBJECT_FLAG=1; fi
GBR_FORM_ENGINE_FLAG="${GBR_FORM_ENGINE:-0}"
if [ "$GBR_FORM_ENGINE_FLAG" = "1" ]; then
    GBR_FORM_FLAG=1
    GBR_OBJECT_FLAG=1
    ALL_APPDEFS="$ALL_APPDEFS -DGBR_FORM_ENGINE"
fi
if [ "$GBR_OBJECT_FLAG" = "1" ]; then GBR_READER_FLAG=1; fi
GBR_GRAPHICS_FLAG="${GBR_GRAPHICS:-0}"
if [ "$GBR_GRAPHICS_FLAG" = "1" ]; then
    GBR_OBJECT_FLAG=1
    GBR_READER_FLAG=1
    ALL_APPDEFS="$ALL_APPDEFS -DGBR_GRAPHICS_RUNTIME"
fi
GBR_MENU_FLAG="${GBR_MENUS:-0}"
GB_VDI_FLAG="${GB_VDI:-0}"
GB_VDI_BASE_FLAG="${GB_VDI_BASE:-0}"
GB_VDI_RASTER_FLAG="${GB_VDI_RASTER:-0}"
GB_VDI_TEXT_FLAG="${GB_VDI_TEXT:-0}"
if [ "$GBR_GRAPHICS_FLAG" = "1" ]; then GB_VDI_RASTER_FLAG=1; fi
if [ "$GB_VDI_RASTER_FLAG" = "1" ] || [ "$GB_VDI_TEXT_FLAG" = "1" ]; then
    GB_VDI_FLAG=1
fi
if [ "$GB_VDI_BASE_FLAG" = "1" ]; then
    ALL_APPDEFS="$ALL_APPDEFS -DGB_VDI_BASE_PROFILE"
fi
GB_EVENT_FLAG="${GB_EVENTS:-0}"
GB_REGION_FLAG="${GB_REGIONS:-0}"
GB_SCRAP_FLAG="${GB_SCRAP:-0}"
GB_SCRAP_TEXT_ONLY_FLAG="${GB_SCRAP_TEXT_ONLY:-0}"
GB_SHELL_CLIENT_FLAG="${GB_SHELL_CLIENT:-0}"
GB_SHELL_TARGET_FLAG="${GB_SHELL_TARGET:-0}"
GB_SHELL_ACCESSORY_CLIENT_FLAG="${GB_SHELL_ACCESSORY_CLIENT:-0}"
GB_SHELL_ACCESSORY_TARGET_FLAG="${GB_SHELL_ACCESSORY_TARGET:-0}"
GB_DEFER_FLAG="${GB_DEFER:-0}"
GB_FSCTX_FLAG="${GB_FSCTX:-0}"
GB_SERVICE_CLIENT_FLAG="${GB_SERVICE_CLIENT:-0}"
GB_SERVICE_PROVIDER_FLAG="${GB_SERVICE_PROVIDER:-0}"
GB_SERVICE_COLLECTOR_FLAG="${GB_SERVICE_COLLECTOR:-0}"
GB_TIMER_FLAG="${GB_TIMER:-0}"
GB_TIMER_COLLECTOR_FLAG="${GB_TIMER_COLLECTOR:-0}"
if [ "$GB_SERVICE_CLIENT_FLAG" = "1" ] ||
   [ "$GB_SERVICE_PROVIDER_FLAG" = "1" ] ||
   [ "$GB_SERVICE_COLLECTOR_FLAG" = "1" ]; then
    SYS_FLAG=1
    GB_DEFER_FLAG=1
    ALL_APPDEFS="$ALL_APPDEFS -DGB_SERVICE_MANAGER"
fi
if [ "$GB_TIMER_FLAG" = "1" ] || [ "$GB_TIMER_COLLECTOR_FLAG" = "1" ]; then
    ALL_APPDEFS="$ALL_APPDEFS -DGB_APP_TIMERS"
    if [ "$GB_TIMER_COLLECTOR_FLAG" = "1" ]; then
        ALL_APPDEFS="$ALL_APPDEFS -DGB_APP_TIMER_COLLECTOR"
    fi
fi
GBR_INCLUDE_FLAGS=""
if [ "$GBR_READER_FLAG" = "1" ] || [ "$GBR_MENU_FLAG" = "1" ] || [ "$GB_VDI_FLAG" = "1" ] || [ "$GB_VDI_BASE_FLAG" = "1" ] || [ "$GB_EVENT_FLAG" = "1" ] || [ "$GB_REGION_FLAG" = "1" ] || [ "$GB_SCRAP_FLAG" = "1" ] || [ "$GB_SHELL_CLIENT_FLAG" = "1" ] || [ "$GB_SHELL_TARGET_FLAG" = "1" ] || [ "$GB_SHELL_ACCESSORY_CLIENT_FLAG" = "1" ] || [ "$GB_SHELL_ACCESSORY_TARGET_FLAG" = "1" ] || [ "$GB_DEFER_FLAG" = "1" ] || [ "$GB_FSCTX_FLAG" = "1" ] || [ "$GB_SECONDARY_FLAG" = "1" ] || [ "$GB_SERVICE_CLIENT_FLAG" = "1" ] || [ "$GB_SERVICE_PROVIDER_FLAG" = "1" ] || [ "$GB_SERVICE_COLLECTOR_FLAG" = "1" ] || [ "$GB_TIMER_FLAG" = "1" ] || [ "$GB_TIMER_COLLECTOR_FLAG" = "1" ]; then
    GBR_INCLUDE_FLAGS="-I $GBR_INCLUDE"
fi
NET_SRC="$GB/gbnet_unapi_stub.c"

if [ "$FORM_FLAG" = "1" ] && [ "$WIDGETS_FLAG" != "1" ]; then
    echo "ERROR: FORM=1 requires WIDGETS=1" >&2
    exit 1
fi
if [ "$FORM_MODAL_ONLY_FLAG" = "1" ] && [ "$FORM_FLAG" != "1" ]; then
    echo "ERROR: FORM_MODAL_ONLY=1 requires FORM=1" >&2
    exit 1
fi
if [ "$GBWIN_DRAG_ONLY_FLAG" = "1" ] && [ "$GBWIN_FLAG" != "1" ]; then
    echo "ERROR: GBWIN_DRAG_ONLY=1 requires GBWIN=1" >&2
    exit 1
fi
if [ "$WINDOW_KIND_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: WINDOW_KIND=1 is MSX2-only" >&2; exit 1 ;;
    esac
fi
if [ "$FORM_SELECT_FLAG" = "1" ] &&
   { [ "$FORM_FLAG" != "1" ] || [ "$SELECTOR_FLAG" != "1" ]; }; then
    echo "ERROR: FORM_SELECT=1 requires FORM=1 and SELECTOR=1" >&2
    exit 1
fi
if [ "$GBR_OBJECT_FLAG" = "1" ] &&
   { [ "$BUTTON_FLAG" != "1" ] && [ "$WIDGETS_FLAG" != "1" ]; }; then
    echo "ERROR: GBR_OBJECTS=1 requires BUTTON=1 or WIDGETS=1" >&2
    exit 1
fi
if [ "$GBR_FORM_FLAG" = "1" ] && [ "$WIDGETS_FLAG" != "1" ]; then
    echo "ERROR: GBR_FORMS=1 requires WIDGETS=1" >&2
    exit 1
fi
for value in "$GBR_GRAPHICS_FLAG" "$GB_VDI_FLAG" "$GB_VDI_BASE_FLAG" "$GB_VDI_RASTER_FLAG" "$GB_VDI_TEXT_FLAG"; do
    if [ "$value" != "0" ] && [ "$value" != "1" ]; then
        echo "ERROR: GBR_GRAPHICS and GB_VDI profile flags must be 0 or 1" >&2
        exit 1
    fi
done
if [ "$GB_VDI_BASE_FLAG" = "1" ] && [ "$GB_VDI_FLAG" = "1" ]; then
    echo "ERROR: GB_VDI_BASE=1 and the full GB_VDI profile are mutually exclusive" >&2
    exit 1
fi
if [ "$GBR_FORM_ENGINE_FLAG" != "0" ] && [ "$GBR_FORM_ENGINE_FLAG" != "1" ]; then
    echo "ERROR: GBR_FORM_ENGINE must be 0 or 1" >&2
    exit 1
fi
if [ "$GBR_MENU_FLAG" != "0" ] && [ "$GBR_MENU_FLAG" != "1" ]; then
    echo "ERROR: GBR_MENUS must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_EVENT_FLAG" != "0" ] && [ "$GB_EVENT_FLAG" != "1" ]; then
    echo "ERROR: GB_EVENTS must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_REGION_FLAG" != "0" ] && [ "$GB_REGION_FLAG" != "1" ]; then
    echo "ERROR: GB_REGIONS must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_REGION_FLAG" = "1" ]; then
    ALL_APPDEFS="$ALL_APPDEFS -DGB_VISIBLE_REGIONS"
fi
if [ "$GB_SCRAP_FLAG" != "0" ] && [ "$GB_SCRAP_FLAG" != "1" ]; then
    echo "ERROR: GB_SCRAP must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_SCRAP_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: GB_SCRAP=1 is MSX2-only" >&2; exit 1 ;;
    esac
    ALL_APPDEFS="$ALL_APPDEFS -DGB_TYPED_SCRAP"
fi
if [ "$GB_SCRAP_TEXT_ONLY_FLAG" != "0" ] && [ "$GB_SCRAP_TEXT_ONLY_FLAG" != "1" ]; then
    echo "ERROR: GB_SCRAP_TEXT_ONLY must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_SCRAP_TEXT_ONLY_FLAG" = "1" ] && [ "$GB_SCRAP_FLAG" != "1" ]; then
    echo "ERROR: GB_SCRAP_TEXT_ONLY=1 requires GB_SCRAP=1" >&2
    exit 1
fi
if [ "$GB_SHELL_CLIENT_FLAG" != "0" ] && [ "$GB_SHELL_CLIENT_FLAG" != "1" ]; then
    echo "ERROR: GB_SHELL_CLIENT must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_SHELL_TARGET_FLAG" != "0" ] && [ "$GB_SHELL_TARGET_FLAG" != "1" ]; then
    echo "ERROR: GB_SHELL_TARGET must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_SHELL_ACCESSORY_CLIENT_FLAG" != "0" ] && [ "$GB_SHELL_ACCESSORY_CLIENT_FLAG" != "1" ]; then
    echo "ERROR: GB_SHELL_ACCESSORY_CLIENT must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_SHELL_ACCESSORY_TARGET_FLAG" != "0" ] && [ "$GB_SHELL_ACCESSORY_TARGET_FLAG" != "1" ]; then
    echo "ERROR: GB_SHELL_ACCESSORY_TARGET must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_SHELL_ACCESSORY_CLIENT_FLAG" = "1" ] && [ "$GB_SHELL_CLIENT_FLAG" != "1" ]; then
    echo "ERROR: GB_SHELL_ACCESSORY_CLIENT=1 requires GB_SHELL_CLIENT=1" >&2
    exit 1
fi
if [ "$GB_SHELL_CLIENT_FLAG" = "1" ] || [ "$GB_SHELL_TARGET_FLAG" = "1" ] || [ "$GB_SHELL_ACCESSORY_CLIENT_FLAG" = "1" ] || [ "$GB_SHELL_ACCESSORY_TARGET_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: GEOBENCH shell services are MSX2-only" >&2; exit 1 ;;
    esac
    ALL_APPDEFS="$ALL_APPDEFS -DGB_SHELL_SERVICES"
fi
if [ "$GB_DEFER_FLAG" != "0" ] && [ "$GB_DEFER_FLAG" != "1" ]; then
    echo "ERROR: GB_DEFER must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_DEFER_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: GB_DEFER=1 is currently MSX2-only" >&2; exit 1 ;;
    esac
    ALL_APPDEFS="$ALL_APPDEFS -DGB_DEFER_MESSAGES"
fi
if [ "$GB_FSCTX_FLAG" != "0" ] && [ "$GB_FSCTX_FLAG" != "1" ]; then
    echo "ERROR: GB_FSCTX must be 0 or 1" >&2
    exit 1
fi
if [ "$GB_FSCTX_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: GB_FSCTX=1 is currently MSX2-only" >&2; exit 1 ;;
    esac
    ALL_APPDEFS="$ALL_APPDEFS -DGB_FILESYSTEM_CONTEXTS"
fi
for service_flag in "$GB_SERVICE_CLIENT_FLAG" "$GB_SERVICE_PROVIDER_FLAG" \
                    "$GB_SERVICE_COLLECTOR_FLAG"; do
    if [ "$service_flag" != "0" ] && [ "$service_flag" != "1" ]; then
        echo "ERROR: GB_SERVICE_* flags must be 0 or 1" >&2
        exit 1
    fi
done
if [ "$GB_SERVICE_CLIENT_FLAG" = "1" ] ||
   [ "$GB_SERVICE_PROVIDER_FLAG" = "1" ] ||
   [ "$GB_SERVICE_COLLECTOR_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: the shared-service manager is currently MSX2-only" >&2; exit 1 ;;
    esac
fi
for timer_flag in "$GB_TIMER_FLAG" "$GB_TIMER_COLLECTOR_FLAG"; do
    if [ "$timer_flag" != "0" ] && [ "$timer_flag" != "1" ]; then
        echo "ERROR: GB_TIMER flags must be 0 or 1" >&2
        exit 1
    fi
done
if [ "$GB_TIMER_FLAG" = "1" ] || [ "$GB_TIMER_COLLECTOR_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: background application timers are currently MSX2-only" >&2; exit 1 ;;
    esac
fi
if [ "$GB_TIMER_FLAG" = "1" ] && [ "$TASK_FLAG" != "1" ]; then
    echo "ERROR: GB_TIMER=1 requires TASK=1" >&2
    exit 1
fi
if [ "$GB_TIMER_COLLECTOR_FLAG" = "1" ] && [ "$TASK_ROOT_FLAG" != "1" ]; then
    echo "ERROR: GB_TIMER_COLLECTOR=1 requires TASK_ROOT=1" >&2
    exit 1
fi
if [ "$GBR_BANKED_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: GBR_BANKED=1 is MSX2-only" >&2; exit 1 ;;
    esac
    if [ "$GBR_EMBEDDED_FLAG" = "1" ]; then
        echo "ERROR: GBR_BANKED=1 cannot use the embedded access-only reader" >&2
        exit 1
    fi
fi
if [ "$TASK_FLAG" = "1" ] && (( TASK_STACK_RESERVE < 256 )); then
    echo "ERROR: TASK=1 requires TASK_STACK_RESERVE=256 (or larger)" >&2
    exit 1
fi
if [ "$TASK_ROOT_FLAG" = "1" ] && (( TASK_STACK_RESERVE < 256 )); then
    echo "ERROR: TASK_ROOT=1 requires TASK_STACK_RESERVE=256 (or larger)" >&2
    exit 1
fi
if [ "$TASK_FLAG" = "1" ] && [ "$TASK_ROOT_FLAG" = "1" ]; then
    echo "ERROR: TASK and TASK_ROOT are mutually exclusive" >&2
    exit 1
fi
if [ "$TASK_ROOT_FLAG" = "1" ] && [ ! -s "$TASK_RUNTIME_RAW" ]; then
    echo "ERROR: TASK_ROOT=1 requires a non-empty TASK_RUNTIME_RAW" >&2
    exit 1
fi
if [ "$BASELINE_FLAG" != "0" ] && [ "$BASELINE_FLAG" != "1" ]; then
    echo "ERROR: BASELINE must be 0 or 1" >&2
    exit 1
fi
if [ "$SYS_FLAG" != "0" ] && [ "$SYS_FLAG" != "1" ]; then
    echo "ERROR: SYS must be 0 or 1" >&2
    exit 1
fi
if [ "$SYS_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) ;;
        *) echo "ERROR: SYS=1 is currently MSX2-only" >&2; exit 1 ;;
    esac
fi

deps=("$0" "tools/build_cache.sh" "tools/check_app_layout.py" "$CRT0_SRC" "$GBLIB_SRC" "$GB/gb.h")
if [ "$WINDOW_KIND_FLAG" = "1" ]; then
    deps+=("$GB/gbwindow_kind.s")
fi
if [ -n "$APP_ICON" ]; then
    deps+=("tools/embed_app_icon.py" "$APP_ICON")
fi
if [ -n "$APP_ICON16" ]; then
    deps+=("$APP_ICON16")
fi
if [ -n "$APP_MANIFEST" ]; then
    deps+=("$APP_MANIFEST")
fi
if [ "$GBWIN_FLAG" = "1" ]; then
    deps+=("$GB/gbwin.c")
fi
if [ "$WIDGETS_FLAG" = "1" ] || [ "$BUTTON_FLAG" = "1" ]; then
    deps+=("$GB/gbwidgets.c")
fi
if [ "$ACTIONS_FLAG" = "1" ]; then
    deps+=("$GB/gbactions.c")
fi
if [ "$SCROLL_FLAG" = "1" ]; then
    deps+=("$GB/gbscroll.c")
fi
if [ "$SCROLL16_FLAG" = "1" ]; then
    deps+=("$GB/gbscroll16.c")
fi
if [ "$TOGGLE_FLAG" = "1" ]; then
    deps+=("$GB/gbtoggle.c")
fi
if [ "$STEPPER_FLAG" = "1" ]; then
    deps+=("$GB/gbstepper.c")
fi
if [ "$SELECTOR_FLAG" = "1" ]; then
    deps+=("$GB/gbselect.c")
fi
if [ "$SLIDER_FLAG" = "1" ]; then
    deps+=("$GB/gbslider.c")
fi
if [ "$FORM_FLAG" = "1" ]; then
    deps+=("$GB/gbform.c")
fi
if [ "$FORM_SELECT_FLAG" = "1" ]; then
    deps+=("$GB/gbform_select.c")
fi
if [ "$TIMESET_FLAG" = "1" ]; then
    deps+=("$GB/gbsettime.c")
fi
if [ "$SOUND_FLAG" = "1" ]; then
    deps+=("$GB/gbsound.c")
fi
if [ "$SIZEPROMPT_FLAG" = "1" ]; then
    deps+=("$GB/gbsizedlg.c")
fi
if [ "$REPAINTTOP_FLAG" = "1" ]; then
    deps+=("$GB/gbrepaint.s")
fi
if [ "$BASELINE_FLAG" = "1" ]; then
    deps+=("$GB/gbbaseline.s")
fi
if [ "$SYS_FLAG" = "1" ]; then
    deps+=("$GB/gbsys.s")
fi
if [ "$GB_SECONDARY_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbsecondary.h" "$GBR_LIB/gbsecondary.c" \
           "$GBR_LIB/gbsecondary.s" "$GBR_LIB/gbsecondary_sys.s" \
           "$APP_SECONDARY")
fi
if [ "$GB_DEFER_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbdefer.h" "$GBR_LIB/gbdefer.s")
fi
if [ "$GB_FSCTX_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbfsctx.h" "$GBR_LIB/gbfsctx.c" "$GBR_LIB/gbfsctx.s")
fi
if [ "$GBR_READER_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbr.h" "$GBR_LIB/gbr_reader.c")
fi
if [ "$GBR_BANKED_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbr_bank.h" "$GBR_LIB/gbr_bank.c" "$GBR_LIB/gbr_bank.s")
fi
if [ "$GBR_OBJECT_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbr_object.h" "$GBR_LIB/gbr_object.c")
fi
if [ "$GB_VDI_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbvdi.h" "$GBR_LIB/gbvdi.c")
fi
if [ "$GB_VDI_BASE_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbvdi.h" "$GBR_LIB/gbvdi_base.c")
fi
if [ "$GB_VDI_RASTER_FLAG" = "1" ]; then
    deps+=("$GBR_LIB/gbvdi_raster.c")
fi
if [ "$GB_VDI_TEXT_FLAG" = "1" ]; then
    deps+=("$GBR_LIB/gbvdi_text.c" "$GBR_LIB/gbvdi_text.s")
fi
if [ "$GBR_FORM_ENGINE_FLAG" = "1" ]; then
    deps+=("$GBR_LIB/gbr_form.c")
fi
if [ "$GBR_MENU_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbr_menu.h" "$GBR_LIB/gbr_menu.c")
fi
if [ "$GB_EVENT_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbevent.h" "$GBR_LIB/gbevent.c")
fi
if [ "$GB_REGION_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbregion.h" "$GBR_LIB/gbregion.c")
fi
if [ "$GB_SCRAP_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbscrap.h")
    if [ "$GB_SCRAP_TEXT_ONLY_FLAG" = "1" ]; then
        deps+=("$GBR_LIB/gbscrap_text.s")
    else
        deps+=("$GBR_LIB/gbscrap.c")
    fi
fi
if [ "$GB_SHELL_CLIENT_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbshell.h" "$GBR_LIB/gbshell.c" "$GBR_LIB/gbshell_client.s")
fi
if [ "$GB_SHELL_TARGET_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbshell.h" "$GBR_LIB/gbshell_register.s")
fi
if [ "$GB_SHELL_ACCESSORY_CLIENT_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbshell.h" "$GBR_LIB/gbaccessory.c" "$GBR_LIB/gbshell_accessory_client.s")
fi
if [ "$GB_SHELL_ACCESSORY_TARGET_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbshell.h" "$GBR_LIB/gbshell_accessory_register.s")
fi
if [ "$TASK_FLAG" = "1" ]; then
    deps+=("$GB/gbtask.s")
fi
if [ "$TASK_ROOT_FLAG" = "1" ]; then
    deps+=("tools/embed_scheduler.py" "$TASK_RUNTIME_RAW")
fi
if [ "$TITLEBAR_FLAG" = "1" ]; then
    deps+=("$GB/gbtitle.c" "$GB/gbtitle.h")
fi
while IFS= read -r dep; do
    deps+=("$dep")
done < <(find "$APP" -type f | sort)
if grep -Rqs 'gbhttp\.h' "$APP"; then
    deps+=("$GB/gbhttp.h")
fi
if grep -Rqs 'gbhtml\.h' "$APP"; then
    deps+=("$GB/gbhtml.h")
fi
if grep -Rqs 'gbdesk_catalog\.h' "$APP"; then
    deps+=("$GBR_INCLUDE/gbdesk_catalog.h")
fi
if [ "$DIALOGS_FLAG" = "1" ] || [ "$PROMPT_FLAG" = "1" ] || [ "$PICKER_FLAG" = "1" ] || [ "$DOC_FLAG" = "1" ] || [ "$DOCRO_FLAG" = "1" ] || [ "$GBR_MENU_FLAG" = "1" ]; then
    deps+=("$GB/gbui_stub.c")
fi
if [ "$DOC_FLAG" = "1" ] || [ "$DOCRO_FLAG" = "1" ]; then
    deps+=("$GB/gbdoc.c")
fi
if [ "$NET_FLAG" = "1" ]; then
    deps+=("$NET_SRC")
fi
if [ "$GB_SERVICE_CLIENT_FLAG" = "1" ]; then
    deps+=("$GBR_LIB/gbservice_client.c" "$GBR_LIB/gbservice_internal.h"
           "$GBR_INCLUDE/gbservice.h")
fi
if [ "$GB_SERVICE_PROVIDER_FLAG" = "1" ]; then
    deps+=("$GBR_LIB/gbservice_provider.c" "$GBR_LIB/gbservice_internal.h"
           "$GBR_INCLUDE/gbservice.h")
fi
if [ "$GB_SERVICE_COLLECTOR_FLAG" = "1" ]; then
    deps+=("$GBR_LIB/gbservice_collect.c" "$GBR_LIB/gbservice_internal.h"
           "$GBR_INCLUDE/gbservice.h")
fi
if [ "$GB_TIMER_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbtimer.h" "$GBR_LIB/gbtimer_damage.s")
fi
if [ "$GB_TIMER_COLLECTOR_FLAG" = "1" ]; then
    deps+=("$GBR_INCLUDE/gbtimer.h" "$GBR_LIB/gbtimer_collect.s")
fi

stamp="$OUT.stamp"
cache_key=$(printf '%s\n' \
    "build_capp.v3" \
    "APP=$APP" \
    "APP_ICON=$APP_ICON" \
    "APP_ICON16=$APP_ICON16" \
    "APP_MANIFEST=$APP_MANIFEST" \
    "APP_SECONDARY=$APP_SECONDARY" \
    "CRT0_SRC=$CRT0_SRC" \
    "CODE_LOC=$CODE_LOC" \
    "DATA_LOC=$DATA_LOC" \
    "APPDEFS=$ALL_APPDEFS" \
    "DIALOGS=$DIALOGS_FLAG" \
    "PROMPT=$PROMPT_FLAG" \
    "PICKER=$PICKER_FLAG" \
    "DOC=$DOC_FLAG" \
    "DOCRO=$DOCRO_FLAG" \
    "NET=$NET_FLAG" \
    "NET_SRC=$NET_SRC" \
    "GBWIN=$GBWIN_FLAG" \
    "GBWIN_DRAG_ONLY=$GBWIN_DRAG_ONLY_FLAG" \
    "WINDOW_KIND=$WINDOW_KIND_FLAG" \
    "WIDGETS=$WIDGETS_FLAG" \
    "BUTTON=$BUTTON_FLAG" \
    "ACTIONS=$ACTIONS_FLAG" \
    "SCROLL=$SCROLL_FLAG" \
    "SCROLL16=$SCROLL16_FLAG" \
    "TOGGLE=$TOGGLE_FLAG" \
    "STEPPER=$STEPPER_FLAG" \
    "SELECTOR=$SELECTOR_FLAG" \
    "SLIDER=$SLIDER_FLAG" \
    "FORM=$FORM_FLAG" \
    "FORM_MODAL_ONLY=$FORM_MODAL_ONLY_FLAG" \
    "FORM_SELECT=$FORM_SELECT_FLAG" \
    "TIMESET=$TIMESET_FLAG" \
    "SOUND=$SOUND_FLAG" \
    "TITLEBAR=$TITLEBAR_FLAG" \
    "SIZEPROMPT=$SIZEPROMPT_FLAG" \
    "APP_PROBE=$APP_PROBE_FLAG" \
    "REPAINTTOP=$REPAINTTOP_FLAG" \
    "BASELINE=$BASELINE_FLAG" \
    "GBR_READER=$GBR_READER_FLAG" \
    "GBR_FIXED_TREE=$GBR_FIXED_TREE_FLAG" \
    "GBR_EMBEDDED=$GBR_EMBEDDED_FLAG" \
    "GBR_BANKED=$GBR_BANKED_FLAG" \
    "GBR_OBJECTS=$GBR_OBJECT_FLAG" \
    "GBR_FORMS=$GBR_FORM_FLAG" \
    "GBR_FORM_ENGINE=$GBR_FORM_ENGINE_FLAG" \
    "GBR_GRAPHICS=$GBR_GRAPHICS_FLAG" \
    "GBR_MENUS=$GBR_MENU_FLAG" \
    "GB_VDI=$GB_VDI_FLAG" \
    "GB_VDI_BASE=$GB_VDI_BASE_FLAG" \
    "GB_VDI_RASTER=$GB_VDI_RASTER_FLAG" \
    "GB_VDI_TEXT=$GB_VDI_TEXT_FLAG" \
    "GB_EVENTS=$GB_EVENT_FLAG" \
    "GB_REGIONS=$GB_REGION_FLAG" \
    "GB_SCRAP=$GB_SCRAP_FLAG" \
    "GB_SCRAP_TEXT_ONLY=$GB_SCRAP_TEXT_ONLY_FLAG" \
    "GB_SHELL_CLIENT=$GB_SHELL_CLIENT_FLAG" \
    "GB_SHELL_TARGET=$GB_SHELL_TARGET_FLAG" \
    "GB_SHELL_ACCESSORY_CLIENT=$GB_SHELL_ACCESSORY_CLIENT_FLAG" \
    "GB_SHELL_ACCESSORY_TARGET=$GB_SHELL_ACCESSORY_TARGET_FLAG" \
    "GB_DEFER=$GB_DEFER_FLAG" \
    "GB_FSCTX=$GB_FSCTX_FLAG" \
    "GB_SERVICE_CLIENT=$GB_SERVICE_CLIENT_FLAG" \
    "GB_SERVICE_PROVIDER=$GB_SERVICE_PROVIDER_FLAG" \
    "GB_SERVICE_COLLECTOR=$GB_SERVICE_COLLECTOR_FLAG" \
    "GB_TIMER=$GB_TIMER_FLAG" \
    "GB_TIMER_COLLECTOR=$GB_TIMER_COLLECTOR_FLAG" \
    "TASK=$TASK_FLAG" \
    "TASK_ROOT=$TASK_ROOT_FLAG" \
    "TASK_RUNTIME_RAW=$TASK_RUNTIME_RAW" \
    "SYS=$SYS_FLAG" \
    "GB_SECONDARY=$GB_SECONDARY_FLAG" \
    "GBLIB_SRC=$GBLIB_SRC" \
    "APP_CFLAGS=$APP_CFLAGS" \
    "HELPER_CFLAGS=$HELPER_CFLAGS" \
    "LOAD_LIMIT=$LOAD_LIMIT" \
    "TASK_STACK_RESERVE=$TASK_STACK_RESERVE" \
    "SDCC=$SDCC" \
    "SDAS=$SDAS" \
    "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes) from $APP"
    exit 0
fi

"$SDAS" -o "$work/crt0.rel"  "$CRT0_SRC"
"$SDAS" -o "$work/gblib.rel" "$GBLIB_SRC"
WINDOW_KIND_REL=""
if [ "$WINDOW_KIND_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbwindow_kind.rel" "$GB/gbwindow_kind.s"
    WINDOW_KIND_REL="$work/gbwindow_kind.rel"
fi
APP_PROBE_REL=""
REPAINTTOP_REL=""
if [ "$REPAINTTOP_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbrepaint.rel" "$GB/gbrepaint.s"
    REPAINTTOP_REL="$work/gbrepaint.rel"
fi
BASELINE_REL=""
if [ "$BASELINE_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbbaseline.rel" "$GB/gbbaseline.s"
    BASELINE_REL="$work/gbbaseline.rel"
fi
SYS_REL=""
if [ "$SYS_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbsys.rel" "$GB/gbsys.s"
    SYS_REL="$work/gbsys.rel"
fi
SECONDARY_REL=""
if [ "$GB_SECONDARY_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbsecondary.c" \
        -o "$work/gbsecondary.rel"
    "$SDAS" -o "$work/gbsecondary_gate.rel" "$GBR_LIB/gbsecondary.s"
    SECONDARY_SYS_REL=""
    if [ "$SYS_FLAG" = "0" ]; then
        "$SDAS" -o "$work/gbsecondary_sys.rel" "$GBR_LIB/gbsecondary_sys.s"
        SECONDARY_SYS_REL="$work/gbsecondary_sys.rel"
    fi
    SECONDARY_REL="$work/gbsecondary.rel $work/gbsecondary_gate.rel $SECONDARY_SYS_REL"
fi
DEFER_REL=""
if [ "$GB_DEFER_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbdefer.rel" "$GBR_LIB/gbdefer.s"
    DEFER_REL="$work/gbdefer.rel"
fi
FSCTX_REL=""
if [ "$GB_FSCTX_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbfsctx_call.rel" "$GBR_LIB/gbfsctx.s"
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbfsctx.c" -o "$work/gbfsctx.rel"
    FSCTX_REL="$work/gbfsctx.rel $work/gbfsctx_call.rel"
fi
SERVICE_REL=""
if [ "$GB_SERVICE_CLIENT_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $HELPER_CFLAGS $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbservice_client.c" \
        -o "$work/gbservice_client.rel"
    SERVICE_REL="$SERVICE_REL $work/gbservice_client.rel"
fi
TIMER_REL=""
if [ "$GB_TIMER_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbtimer_damage.rel" "$GBR_LIB/gbtimer_damage.s"
    TIMER_REL="$TIMER_REL $work/gbtimer_damage.rel"
fi
if [ "$GB_TIMER_COLLECTOR_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbtimer_collect.rel" "$GBR_LIB/gbtimer_collect.s"
    TIMER_REL="$TIMER_REL $work/gbtimer_collect.rel"
fi
if [ "$GB_SERVICE_PROVIDER_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $HELPER_CFLAGS $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbservice_provider.c" \
        -o "$work/gbservice_provider.rel"
    SERVICE_REL="$SERVICE_REL $work/gbservice_provider.rel"
fi
if [ "$GB_SERVICE_COLLECTOR_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $HELPER_CFLAGS $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbservice_collect.c" \
        -o "$work/gbservice_collect.rel"
    SERVICE_REL="$SERVICE_REL $work/gbservice_collect.rel"
fi
TASK_REL=""
if [ "$TASK_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbtask.rel" "$GB/gbtask.s"
    TASK_REL="$work/gbtask.rel"
fi
TASK_ROOT_REL=""
if [ "$TASK_ROOT_FLAG" = "1" ]; then
    case " $ALL_APPDEFS " in
        *" -DGB_MSX2 "*) TASK_RUNTIME_BASE=0xC900 ;;
        *)               TASK_RUNTIME_BASE=0x3C00 ;;
    esac
    python3 tools/embed_scheduler.py "$TASK_RUNTIME_RAW" "$work/gbtaskroot.s" \
        --base "$TASK_RUNTIME_BASE"
    "$SDAS" -o "$work/gbtaskroot.rel" "$work/gbtaskroot.s"
    TASK_ROOT_REL="$work/gbtaskroot.rel"
fi
# --fomit-frame-pointer: frame on IY, not IX. The kernel/fs code uses IX as a
# scratch (it never touches IY) and firmware calls preserve the caller's IY, so
# this stops a kernel call from wrecking an app's frame pointer (which crashed
# the notepad's return - SDCC's epilogue is `ld sp,<fp>`).
# APPDEFS (e.g. -DGB_MSX2) MUST reach every libgb C unit, not just main.c: gb.h
# derives GB_COLS/GB_LINES/GB_XPIX from it, and gbwin.c/gbdoc.c clamp window
# drag/resize + fullscreen to those extents. Omitting it built libgb with the
# legacy 320x200 extents, so on MSX windows would not drag past x=320 (#287).
"$SDCC" -mz80 --fomit-frame-pointer $APP_CFLAGS $ALL_APPDEFS -I "$GB" $GBR_INCLUDE_FLAGS -c "$APP/main.c" -o "$work/main.rel"
GBR_REL=""
if [ "$GB_VDI_BASE_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer \
        --max-allocs-per-node 100000 $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbvdi_base.c" \
        -o "$work/gbvdi_base.rel"
    GBR_REL="$GBR_REL $work/gbvdi_base.rel"
fi
if [ "$GB_VDI_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbvdi.c" -o "$work/gbvdi.rel"
    GBR_REL="$GBR_REL $work/gbvdi.rel"
fi
if [ "$GB_VDI_RASTER_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbvdi_raster.c" -o "$work/gbvdi_raster.rel"
    GBR_REL="$GBR_REL $work/gbvdi_raster.rel"
fi
if [ "$GB_VDI_TEXT_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbvdi_text.c" -o "$work/gbvdi_text.rel"
    "$SDAS" -o "$work/gbvdi_text_call.rel" "$GBR_LIB/gbvdi_text.s"
    GBR_REL="$GBR_REL $work/gbvdi_text.rel $work/gbvdi_text_call.rel"
fi
if [ "$GBR_READER_FLAG" = "1" ]; then
    GBR_READER_DEFS=""
    [ "$GBR_FIXED_TREE_FLAG" != "1" ] || GBR_READER_DEFS="$GBR_READER_DEFS -DGBR_READER_NO_FIND_TREE"
    [ "$GBR_EMBEDDED_FLAG" != "1" ] || GBR_READER_DEFS="$GBR_READER_DEFS -DGBR_READER_ACCESS_ONLY"
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $GBR_READER_DEFS $ALL_APPDEFS \
        -I "$GBR_INCLUDE" -c "$GBR_LIB/gbr_reader.c" -o "$work/gbr_reader.rel"
    GBR_REL="$GBR_REL $work/gbr_reader.rel"
fi
if [ "$GBR_BANKED_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GBR_INCLUDE" -c "$GBR_LIB/gbr_bank.c" -o "$work/gbr_bank.rel"
    "$SDAS" -o "$work/gbr_bank_call.rel" "$GBR_LIB/gbr_bank.s"
    GBR_REL="$GBR_REL $work/gbr_bank.rel $work/gbr_bank_call.rel"
fi
if [ "$GBR_OBJECT_FLAG" = "1" ]; then
    GBR_FORM_DEFS=""
    [ "$GBR_FORM_FLAG" != "1" ] || GBR_FORM_DEFS="-DGBR_FORM_RUNTIME"
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $GBR_FORM_DEFS $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbr_object.c" -o "$work/gbr_object.rel"
    GBR_REL="$GBR_REL $work/gbr_object.rel"
fi
if [ "$GBR_FORM_ENGINE_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GBR_INCLUDE" -c "$GBR_LIB/gbr_form.c" -o "$work/gbr_form.rel"
    GBR_REL="$GBR_REL $work/gbr_form.rel"
fi
if [ "$GBR_MENU_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbr_menu.c" -o "$work/gbr_menu.rel"
    GBR_REL="$GBR_REL $work/gbr_menu.rel"
fi
if [ "$GB_EVENT_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbevent.c" -o "$work/gbevent.rel"
    GBR_REL="$GBR_REL $work/gbevent.rel"
fi
if [ "$GB_REGION_FLAG" = "1" ]; then
    # This leaf runtime never calls the kernel, so keeping SDCC's frame pointer
    # is safe and currently saves more than 500 bytes on Z80.
    "$SDCC" -mz80 --opt-code-size $ALL_APPDEFS \
        -I "$GBR_INCLUDE" -c "$GBR_LIB/gbregion.c" -o "$work/gbregion.rel"
    GBR_REL="$GBR_REL $work/gbregion.rel"
fi
if [ "$GB_SCRAP_FLAG" = "1" ]; then
    if [ "$GB_SCRAP_TEXT_ONLY_FLAG" = "1" ]; then
        "$SDAS" -o "$work/gbscrap.rel" "$GBR_LIB/gbscrap_text.s"
    else
        "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
            -I "$GB" -I "$GBR_INCLUDE" -c "$GBR_LIB/gbscrap.c" -o "$work/gbscrap.rel"
    fi
    GBR_REL="$GBR_REL $work/gbscrap.rel"
fi
if [ "$GB_SHELL_CLIENT_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GBR_INCLUDE" -c "$GBR_LIB/gbshell.c" -o "$work/gbshell.rel"
    "$SDAS" -o "$work/gbshell_client.rel" "$GBR_LIB/gbshell_client.s"
    GBR_REL="$GBR_REL $work/gbshell.rel $work/gbshell_client.rel"
fi
if [ "$GB_SHELL_TARGET_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbshell_register.rel" "$GBR_LIB/gbshell_register.s"
    GBR_REL="$GBR_REL $work/gbshell_register.rel"
fi
if [ "$GB_SHELL_ACCESSORY_CLIENT_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS \
        -I "$GBR_INCLUDE" -c "$GBR_LIB/gbaccessory.c" -o "$work/gbaccessory.rel"
    "$SDAS" -o "$work/gbshell_accessory_client.rel" "$GBR_LIB/gbshell_accessory_client.s"
    GBR_REL="$GBR_REL $work/gbaccessory.rel $work/gbshell_accessory_client.rel"
fi
if [ "$GB_SHELL_ACCESSORY_TARGET_FLAG" = "1" ]; then
    "$SDAS" -o "$work/gbshell_accessory_register.rel" "$GBR_LIB/gbshell_accessory_register.s"
    GBR_REL="$GBR_REL $work/gbshell_accessory_register.rel"
fi
GBWIN_REL=""
if [ "$GBWIN_FLAG" = "1" ]; then
    GBWIN_DEFS=""
    [ "$GBWIN_DRAG_ONLY_FLAG" != "1" ] || GBWIN_DEFS="-DGBWIN_DRAG_ONLY"
    "$SDCC" -mz80 --fomit-frame-pointer $GBWIN_DEFS $ALL_APPDEFS -I "$GB" -c "$GB/gbwin.c" -o "$work/gbwin.rel"
    GBWIN_REL="$work/gbwin.rel"
fi
WIDGETS_REL=""
if [ "$WIDGETS_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbwidgets.c" -o "$work/gbwidgets.rel"
    WIDGETS_REL="$work/gbwidgets.rel"
elif [ "$BUTTON_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer -DGB_BUTTON_ONLY $ALL_APPDEFS -I "$GB" -c "$GB/gbwidgets.c" -o "$work/gbwidgets.rel"
    WIDGETS_REL="$work/gbwidgets.rel"
fi
ACTIONS_REL=""
if [ "$ACTIONS_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbactions.c" -o "$work/gbactions.rel"
    ACTIONS_REL="$work/gbactions.rel"
fi
SCROLL_REL=""
if [ "$SCROLL_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbscroll.c" -o "$work/gbscroll.rel"
    SCROLL_REL="$work/gbscroll.rel"
fi
SCROLL16_REL=""
if [ "$SCROLL16_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbscroll16.c" -o "$work/gbscroll16.rel"
    SCROLL16_REL="$work/gbscroll16.rel"
fi
TOGGLE_REL=""
if [ "$TOGGLE_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbtoggle.c" -o "$work/gbtoggle.rel"
    TOGGLE_REL="$work/gbtoggle.rel"
fi
STEPPER_REL=""
if [ "$STEPPER_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbstepper.c" -o "$work/gbstepper.rel"
    STEPPER_REL="$work/gbstepper.rel"
fi
SELECTOR_REL=""
if [ "$SELECTOR_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbselect.c" -o "$work/gbselect.rel"
    SELECTOR_REL="$work/gbselect.rel"
fi
SLIDER_REL=""
if [ "$SLIDER_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbslider.c" -o "$work/gbslider.rel"
    SLIDER_REL="$work/gbslider.rel"
fi
FORM_REL=""
if [ "$FORM_FLAG" = "1" ]; then
    FORM_DEFS=""
    [ "$FORM_MODAL_ONLY_FLAG" != "1" ] || FORM_DEFS="-DGB_FORM_MODAL_ONLY"
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $FORM_DEFS $ALL_APPDEFS -I "$GB" -c "$GB/gbform.c" -o "$work/gbform.rel"
    FORM_REL="$work/gbform.rel"
fi
FORM_SELECT_REL=""
if [ "$FORM_SELECT_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbform_select.c" -o "$work/gbform_select.rel"
    FORM_SELECT_REL="$work/gbform_select.rel"
fi
TIMESET_REL=""
if [ "$TIMESET_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$GB/gbsettime.c" -o "$work/gbsettime.rel"
    TIMESET_REL="$work/gbsettime.rel"
fi
SOUND_REL=""
if [ "$SOUND_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $HELPER_CFLAGS $ALL_APPDEFS -I "$GB" \
        -c "$GB/gbsound.c" -o "$work/gbsound.rel"
    SOUND_REL="$work/gbsound.rel"
fi
SIZEPROMPT_REL=""
if [ "$SIZEPROMPT_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $HELPER_CFLAGS $ALL_APPDEFS -I "$GB" \
        -c "$GB/gbsizedlg.c" -o "$work/gbsizedlg.rel"
    SIZEPROMPT_REL="$work/gbsizedlg.rel"
fi
TITLEBAR_REL=""
if [ "$TITLEBAR_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer $HELPER_CFLAGS $ALL_APPDEFS -I "$GB" \
        -c "$GB/gbtitle.c" -o "$work/gbtitle.rel"
    TITLEBAR_REL="$work/gbtitle.rel"
fi
# Opt-in dialogs (#114, #142). The heavy render (popup/prompt/file-picker) now lives in
# the paged GBUI kernel module (#142 step 1b); an app that needs ANY dialog links only
# the tiny marshalling stub gbui_stub.c (gb_popup/gb_prompt/gb_pickfile/gb_pickdir ->
# GB_UI). That ~800-byte/app saving is what lets the data-heavy apps fit gb_doc.
#   DIALOGS / PROMPT / PICKER  -> gbui_stub.c (the general stubs)
#   SIZEPROMPT=1               -> gbsizedlg.c (opt-in two-field dimensions stub)
#   DOC=1                      -> gbdoc.c too (the document/File-menu framework)
DLG_REL=""
if [ "$DIALOGS_FLAG" = "1" ] || [ "$PROMPT_FLAG" = "1" ] || [ "$PICKER_FLAG" = "1" ] || [ "$DOC_FLAG" = "1" ] || [ "$DOCRO_FLAG" = "1" ] || [ "$GBR_MENU_FLAG" = "1" ]; then
    DLG_DEFS=""
    [ "$GBR_MENU_FLAG" != "1" ] || DLG_DEFS="-DGBR_MENU_RUNTIME"
    "$SDCC" -mz80 --fomit-frame-pointer $HELPER_CFLAGS $DLG_DEFS $ALL_APPDEFS -I "$GB" -c "$GB/gbui_stub.c" -o "$work/gbui_stub.rel"
    DLG_REL="$work/gbui_stub.rel"
fi
# DOC=1 = the full document framework; DOCRO=1 = a READ-ONLY variant (-DGBDOC_RO) that
# omits the Save/Save As path, so a viewer-style app saves that code room (#144).
if [ "$DOC_FLAG" = "1" ] || [ "$DOCRO_FLAG" = "1" ]; then
    RO=""; [ "$DOCRO_FLAG" = "1" ] && RO="-DGBDOC_RO"
    "$SDCC" -mz80 --fomit-frame-pointer $RO $ALL_APPDEFS -I "$GB" -I "$GBR_INCLUDE" -c "$GB/gbdoc.c" -o "$work/gbdoc.rel"
    DLG_REL="$DLG_REL $work/gbdoc.rel"
fi
# NET=1 calls a discovered TCP/IP UNAPI implementation directly.
if [ "$NET_FLAG" = "1" ]; then
    "$SDCC" -mz80 --fomit-frame-pointer $ALL_APPDEFS -I "$GB" -c "$NET_SRC" -o "$work/gbnet_stub.rel"
    DLG_REL="$DLG_REL $work/gbnet_stub.rel"
fi
"$SDCC" -mz80 --no-std-crt0 --code-loc "$CODE_LOC" --data-loc "$DATA_LOC" \
    "$work/crt0.rel" "$work/main.rel" $GBWIN_REL $WIDGETS_REL $ACTIONS_REL $SCROLL_REL $SCROLL16_REL \
    $TOGGLE_REL $STEPPER_REL $SELECTOR_REL $SLIDER_REL $FORM_REL \
    $FORM_SELECT_REL $TIMESET_REL $SOUND_REL $SIZEPROMPT_REL $TITLEBAR_REL $DLG_REL $GBR_REL $APP_PROBE_REL $REPAINTTOP_REL $BASELINE_REL $SYS_REL $TASK_REL $TASK_ROOT_REL \
    $WINDOW_KIND_REL $DEFER_REL $FSCTX_REL $SERVICE_REL $TIMER_REL $SECONDARY_REL "$work/gblib.rel" -o "$work/app.ihx"
# STABILITY GUARD: the app must fit its 16K page. The whole LOADED IMAGE
# (_CODE + the startup tails _GSINIT/_GSFINAL/_INITIALIZER, which the linker places
# AFTER the code) must end below data-loc - otherwise the RAM data area starts inside
# it and gsinit zeroes its own code as it runs -> instant reboot (bit NOTEPAD: a
# _CODE-only check passed while _GSINIT overlapped _DATA). And data+bss must end below
# the kernel (#8000). LOAD_LIMIT mirrors the target's app loader ceiling; it is
# #7F00 by default.
python3 tools/check_app_layout.py "$work/app.map" \
    --app "$APP" --data-loc "$DATA_LOC" --load-limit "$LOAD_LIMIT" \
    --task-stack-reserve "$TASK_STACK_RESERVE"

"$MAKEBIN" -p "$work/app.ihx" "$work/app.bin"

# makebin emits a flat image from #0000; the app lives at #4000 -> strip low 16K.
tail -c +16385 "$work/app.bin" > "$work/app.raw"
if [ -n "$APP_ICON" ]; then
    if [ -n "$APP_MANIFEST" ] && [ -n "$APP_ICON16" ]; then
        v3_args=("$APP_MANIFEST" "$APP_ICON" "$APP_ICON16" "$work/app.raw" "$OUT")
        if [ -n "$APP_SECONDARY" ]; then
            v3_args+=(--secondary "$APP_SECONDARY")
        fi
        python3 tools/embed_app_icon.py inject-v3 "${v3_args[@]}"
    elif [ -n "$APP_MANIFEST" ]; then
        v3_args=("$APP_MANIFEST" "$APP_ICON" "$work/app.raw" "$OUT")
        if [ -n "$APP_SECONDARY" ]; then
            v3_args+=(--secondary "$APP_SECONDARY")
        fi
        python3 tools/embed_app_icon.py inject-v3 "${v3_args[@]}"
    elif [ -n "$APP_ICON16" ]; then
        python3 tools/embed_app_icon.py inject \
            "$APP_ICON" "$APP_ICON16" "$work/app.raw" "$OUT"
    else
        python3 tools/embed_app_icon.py inject "$APP_ICON" "$work/app.raw" "$OUT"
    fi
else
    cp "$work/app.raw" "$OUT"
fi
if [ -n "$APP_SECONDARY" ] && (( $(stat -c%s "$OUT") > 0x3F00 )); then
    echo "ERROR: GBAP v3 package $(stat -c%s "$OUT") bytes exceeds the MSX loader ceiling" >&2
    exit 1
fi
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes) from $APP"
