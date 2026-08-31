#!/usr/bin/env bash
# Host parity tests for the C config parser (kernel/kc/kcfg.c). Builds with the
# host cc and runs the test harness; pure logic, no emulator needed.
#   kernel/kc/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-cc}"
tmp="$(mktemp -d)"
"$CC" -Wall -Wextra -std=c99 -o "$tmp/test_kcfg" test_kcfg.c kcfg.c
"$tmp/test_kcfg"
