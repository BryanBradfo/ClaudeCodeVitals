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

# ---- Task 6: fmt_session ----
assert_eq "$(fmt_session 'refactor-auth' 'a3f9c1e2-dead-beef')" "refactor-auth" "name wins"
assert_eq "$(fmt_session '' 'a3f9c1e2-dead-beef')"              "a3f9c1e2"      "no name -> short id"
assert_eq "$(fmt_session '' '')"                                ""              "neither -> empty"

# ---- Task 7: fmt_reset ----
assert_eq "$(TZ=UTC fmt_reset 0 time)"     "00:00"        "epoch 0 time"
assert_eq "$(TZ=UTC fmt_reset 0 date)"     "Jan 1"        "epoch 0 date"
assert_eq "$(TZ=UTC fmt_reset 0 datetime)" "Thu Jan 1, 00:00" "epoch 0 datetime"
assert_eq "$(fmt_reset '' time)"           ""             "empty -> empty"
assert_eq "$(fmt_reset null time)"         ""             "null -> empty"
assert_eq "$(TZ=UTC fmt_reset '1970-01-01T00:00:00Z' time)" "00:00" "ISO string accepted"

# ---- Task 8: parse_input ----
INPUT='{"model":{"display_name":"Opus 4.8 (1M context)"},"cwd":"/x/y","session_name":"demo","session_id":"abcd1234efgh","context_window":{"used_percentage":42.7,"context_window_size":1000000,"current_usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30}},"effort":{"level":"high"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":0},"seven_day":{"used_percentage":34,"resets_at":0}},"pr":{"number":142,"review_state":"pending"},"cost":{"total_cost_usd":1.27}}'
parse_input
assert_eq "$MODEL"    "Opus 4.8 (1M context)" "MODEL parsed"
assert_eq "$CWD"      "/x/y"                   "CWD parsed"
assert_eq "$SESSION_NAME" "demo"               "SESSION_NAME parsed"
assert_eq "$CTX_PCT"  "42"                      "CTX_PCT floored from 42.7"
assert_eq "$EFFORT"   "high"                    "EFFORT parsed"
assert_eq "$FH_PCT"   "12"                      "FH_PCT parsed"
assert_eq "$PR_NUM"   "142"                     "PR_NUM parsed"
assert_eq "$COST"     "1.27"                    "COST parsed"
# Fallback: no used_percentage -> compute from tokens (60 / 200000 -> 0)
INPUT='{"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":100000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
parse_input
assert_eq "$CTX_PCT"  "50"                      "CTX_PCT computed when used_percentage absent"

# ---- Task 9: seg_model ----
OUT=""; MODEL="Opus 4.8 (1M context)"; seg_model
assert_eq "$(printf '%s' "$OUT" | strip)" "Opus 4.8 1M" "seg_model strips (...context) and keeps 1M"
assert_contains "$OUT" "$C_PURPLE" "Opus uses purple accent"
OUT=""; MODEL="Sonnet 4.6"; seg_model
assert_contains "$OUT" "$C_BLUE" "Sonnet uses blue accent"
SEG_MODEL=0; OUT=""; MODEL="Opus"; seg_model
assert_eq "$OUT" "" "toggle off -> no output"
SEG_MODEL=1

# ---- Task 10: seg_session ----
OUT=""; SESSION_NAME="demo"; SESSION_ID="abcd1234efgh"; seg_session
assert_eq "$(printf '%s' "$OUT" | strip)" "»demo" "named session"
OUT=""; SESSION_NAME=""; SESSION_ID="abcd1234efgh"; seg_session
assert_eq "$(printf '%s' "$OUT" | strip)" "»abcd1234" "unnamed -> short id"
OUT=""; SESSION_NAME=""; SESSION_ID=""; seg_session
assert_eq "$OUT" "" "no session data -> nothing"

# ---- Task 11: seg_git ----
G="$T_CACHE/repo"; mkdir -p "$G"
( cd "$G" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'a\nb\nc\n' > f.txt && git add f.txt && git commit -qm init \
  && printf 'a\nB\nc\nd\n' > f.txt )   # 1 changed + 1 added line, working tree dirty
OUT=""; CWD="$G"; seg_git
g="$(printf '%s' "$OUT" | strip)"
assert_contains "$g" "repo@"   "shows dir@branch"
assert_contains "$g" "*"        "dirty marker present"
assert_contains "$g" "+"        "additions present"
assert_contains "$g" "-"        "deletions present"
OUT=""; CWD="$T_CACHE"; seg_git   # not a git repo (cache dir itself)
assert_eq "$OUT" "" "non-repo cwd -> git segment hidden"

# (more tests appended by later tasks)

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
