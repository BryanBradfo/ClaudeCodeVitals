#!/usr/bin/env bash
# Self-contained test runner for ClaudeCodeVitals.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL="$HERE/../statusline.sh"
T_CACHE="$(mktemp -d)"
trap 'rm -rf "$T_CACHE"' EXIT

PASS=0; FAIL=0
strip() { sed -E 's/\x1b\[[0-9;]*m//g'; }
assert_eq() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$3" "$2" "$1"; fi; }
assert_contains() { case "$1" in *"$2"*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1)); printf 'FAIL: %s\n  [%s] does not contain [%s]\n' "$3" "$1" "$2";; esac; }
assert_not_contains() { case "$1" in *"$2"*) FAIL=$((FAIL+1)); printf 'FAIL: %s\n  [%s] should not contain [%s]\n' "$3" "$1" "$2";; *) PASS=$((PASS+1));; esac; }
run_sl() { printf '%s' "$1" | CCV_NO_FETCH=1 CCV_CACHE_DIR="$T_CACHE" bash "$SL"; }

# Source the script to unit-test pure functions (main does not run when sourced).
# shellcheck disable=SC1090
source "$SL"

# ---- Task 1: empty input ----
out="$(run_sl '')"
assert_eq "$out" "Claude" "empty stdin prints Claude"

# ---- Task 2: bars ----
assert_eq "$(bar_fill 0)"   "0" "bar_fill 0 -> 0"
assert_eq "$(bar_fill 8)"   "1" "bar_fill 8 -> 1 (min-1 rule)"
assert_eq "$(bar_fill 50)"  "2" "bar_fill 50 -> 2 (rounding)"
assert_eq "$(bar_fill 76)"  "2" "bar_fill 76 -> 2"
assert_eq "$(bar_fill 93)"  "3" "bar_fill 93 -> 3"
assert_eq "$(bar_fill 100)" "3" "bar_fill 100 -> 3"
bar_out="$(make_bar 50 | strip)"
assert_eq "$bar_out" "▰▰▱" "make_bar 50 renders 2 filled, 1 empty"

# (more tests appended by later tasks)

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
