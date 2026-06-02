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

# ---- Task 3: usage levels ----
assert_eq "$(usage_level 0)"   "green"  "0% -> green"
assert_eq "$(usage_level 49)"  "green"  "49% -> green"
assert_eq "$(usage_level 50)"  "yellow" "50% -> yellow"
assert_eq "$(usage_level 70)"  "orange" "70% -> orange"
assert_eq "$(usage_level 90)"  "red"    "90% -> red"
assert_eq "$(level_color red)" "$C_RED" "level_color red -> C_RED"

# ---- Task 4: accent ----
assert_eq "$(accent_level 'Opus 4.8 (1M context)')" "opus"    "Opus -> opus"
assert_eq "$(accent_level 'Sonnet 4.6')"            "sonnet"  "Sonnet -> sonnet"
assert_eq "$(accent_level 'Haiku 4.5')"             "haiku"   "Haiku -> haiku"
assert_eq "$(accent_level 'Claude')"                "default" "unknown -> default"

# ---- Task 5: fmt_tokens ----
assert_eq "$(fmt_tokens 500)"     "500"  "500 -> 500"
assert_eq "$(fmt_tokens 79000)"   "79k"  "79000 -> 79k"
assert_eq "$(fmt_tokens 1000000)" "1M"   "1000000 -> 1M"
assert_eq "$(fmt_tokens 1500000)" "1.5M" "1500000 -> 1.5M"

# (more tests appended by later tasks)

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
