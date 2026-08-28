#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror test_core.c -o "$tmp/test_core"
"$tmp/test_core"
