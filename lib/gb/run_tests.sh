#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-cc}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_gbhttp" test_gbhttp.c
"$tmp/test_gbhttp"
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_gbhtml" test_gbhtml.c
"$tmp/test_gbhtml"
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_gbform" test_gbform.c
"$tmp/test_gbform"
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_gburl" test_gburl.c
"$tmp/test_gburl"
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_gbcfg" test_gbcfg.c
"$tmp/test_gbcfg"
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_gbwidgets" \
    test_gbwidgets.c gbwidgets.c gbactions.c gbscroll.c gbscroll16.c gbtoggle.c \
    gbstepper.c gbselect.c gbslider.c
"$tmp/test_gbwidgets"
"$CC" -Wall -Wextra -std=c99 -DGB_HOST_TEST -o "$tmp/test_gbform_ui" \
    test_gbform_ui.c gbform.c gbform_select.c gbwidgets.c gbselect.c
"$tmp/test_gbform_ui"
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_gbwindow_kinds" test_gbwindow_kinds.c
"$tmp/test_gbwindow_kinds"
if command -v sdcc >/dev/null 2>&1; then
    sdcc -mz80 --std-c99 -c test_gbwindow_kind_layout.c -o "$tmp/test_gbwindow_kind_layout.rel"
    echo "gbwindow target layout: 12-byte legacy prefix preserved"
fi
