#!/usr/bin/env bash
# Small mtime + flag-signature cache for build helper scripts.
#
# Call gb_needs_rebuild OUT STAMP KEY DEPS...
#   returns 0 when OUT should be rebuilt
#   returns 1 when OUT is up to date

gb_needs_rebuild() {
    local out="$1"
    local stamp="$2"
    local key="$3"
    shift 3

    [ -s "$out" ] || return 0
    [ -f "$stamp" ] || return 0
    [ "$(cat "$stamp" 2>/dev/null || true)" = "$key" ] || return 0

    local dep
    for dep in "$@"; do
        [ -e "$dep" ] || return 0
        [ "$dep" -nt "$out" ] && return 0
    done
    return 1
}

gb_write_stamp() {
    local stamp="$1"
    local key="$2"
    mkdir -p "$(dirname "$stamp")"
    printf '%s' "$key" > "$stamp"
}
