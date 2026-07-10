#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-cc}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_gbhttp" test_gbhttp.c
"$tmp/test_gbhttp"
