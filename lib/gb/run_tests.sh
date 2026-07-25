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
    test_gbwidgets.c gbwidgets.c gbscroll.c gbtoggle.c gbstepper.c \
    gbselect.c gbslider.c
"$tmp/test_gbwidgets"
