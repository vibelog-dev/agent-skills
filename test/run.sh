#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0
assert_eq() { # msg expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
assert_true()  { local m="$1"; shift; if "$@"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL(true): %s\n' "$m"; fi; }
assert_false() { local m="$1"; shift; if "$@"; then FAIL=$((FAIL+1)); printf 'FAIL(false): %s\n' "$m"; else PASS=$((PASS+1)); fi; }

# shellcheck disable=SC1091
source "$ROOT/install.sh"

# Task 1: help + guard
help_out="$(bash "$ROOT/install.sh" --help)"
assert_true "help mentions usage" grep -qi 'usage' <<<"$help_out"
assert_true "sourcing did not run main (no install output)" test -z "${MAIN_RAN:-}"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
