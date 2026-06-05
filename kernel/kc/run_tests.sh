#!/usr/bin/env bash
# Host parity tests for the C config parser (kernel/kc/kcfg.c). Builds with the
# host cc and runs the test harness; pure logic, no CPC/emulator needed.
#   kernel/kc/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")"

CC="${CC:-cc}"
out="$(mktemp -d)/test_kcfg"
"$CC" -Wall -Wextra -std=c99 -o "$out" test_kcfg.c kcfg.c
"$out"
