# ClaudeCodeVitals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Linux-only Bash Claude Code status line that renders model, session, git, PR, context, effort, rate limits, extra usage, and cost as one compact colored line with progress bars.

**Architecture:** A single `statusline.sh` with a CONFIG header (palette, glyphs, toggles), pure helper functions, one `parse_input()` jq pass that sets globals, one `seg_*()` function per segment that appends to a global `OUT`, and a `main()` guarded so the file can be `source`d by tests without executing. Pure helpers are unit-tested by sourcing; segments are integration-tested by piping JSON fixtures through the executed script.

**Tech Stack:** Bash, `jq`, `curl`, `git`, GNU coreutils. No test framework dependency — a self-contained `tests/run_tests.sh` provides assert helpers. No Nerd Font; all glyphs are standard Unicode.

---

## Conventions used by every task

These are defined in Task 1 and referenced everywhere. Do not redefine them.

**Global variables** (set by `parse_input`, consumed by segments):
`MODEL CWD SESSION_NAME SESSION_ID CTX_PCT CTX_SIZE CTX_INPUT CTX_CC CTX_CR EFFORT FH_PCT FH_RESET SD_PCT SD_RESET PR_NUM PR_STATE COST` plus `INPUT` (raw stdin), `OUT` (accumulating line), and `EXTRA_LINE` (set by `load_usage`).

**Config header names:** palette `C_BLUE C_ORANGE C_GREEN C_CYAN C_RED C_YELLOW C_PURPLE C_WHITE C_DIM C_RESET`; bars `BAR_WIDTH BAR_FILLED BAR_EMPTY`; `SEP SESSION_MARK CTX_WARN_THRESHOLD CTX_WARN_GLYPH`; toggles `SEG_MODEL SEG_SESSION SEG_GIT SEG_PR SEG_CONTEXT SEG_EFFORT SEG_LIMITS SEG_EXTRA SEG_COST`; `CCV_CACHE_DIR CACHE_MAX_AGE`.

**Function inventory** (defined across tasks, names are final):
`add` (T1), `usage_level`/`level_color` (T3), `bar_fill`/`make_bar` (T2), `accent_level` (T4), `fmt_tokens` (T5), `fmt_session` (T6), `fmt_reset` (T7), `parse_input` (T8), `seg_model` (T9), `seg_session` (T10), `seg_git` (T11), `seg_pr` (T12), `seg_context` (T13), `seg_effort` (T14), `seg_limits` (T15), `get_oauth_token`/`load_usage`/`seg_extra` (T16), `seg_cost` (T17), `main` (T18).

**Test helpers** (defined in Task 1, in `tests/run_tests.sh`):
- `strip` — pipe filter removing ANSI codes: `sed -E 's/\x1b\[[0-9;]*m//g'`
- `assert_eq <actual> <expected> <msg>`
- `assert_contains <haystack> <needle> <msg>`
- `assert_not_contains <haystack> <needle> <msg>`
- `run_sl <json>` — runs the script with network disabled and an isolated cache dir: `printf '%s' "$1" | CCV_NO_FETCH=1 CCV_CACHE_DIR="$T_CACHE" bash "$SL"`

**Determinism:** reset-time tests use `TZ=UTC` and epoch `0` so output is fixed. Network is disabled in tests via `CCV_NO_FETCH=1`.

---

## File Structure

- Create: `statusline.sh` — the tool (config header + helpers + segments + main, source-guarded)
- Create: `tests/run_tests.sh` — assert helpers + all unit & integration tests
- Create: `samples/run.sh` — renders fixtures for visual review (network off, temp cache)
- Create: `samples/low-usage.json`, `samples/high-usage.json`, `samples/no-git.json`, `samples/no-limits.json`
- Create: `README.md`, `LICENSE`, `.gitignore`

---

### Task 1: Scaffolding, config header, test harness, empty-input behavior

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
*.swp
.DS_Store
/tmp/
```

- [ ] **Step 2: Create `LICENSE` (MIT, with attribution)**

```text
MIT License

Copyright (c) 2026 Bryan

Inspired by daniel3303/ClaudeCodeStatusLine (MIT). This is an independent
rewrite, not a copy.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Create `statusline.sh` skeleton (config header, `add`, source-guarded `main`)**

```bash
#!/usr/bin/env bash
# ClaudeCodeVitals — a Claude Code status line.
# Source: (your repo URL)  | Inspired by daniel3303/ClaudeCodeStatusLine (MIT)

# ===== CONFIG =====
# Palette (truecolor). $'...' embeds real ESC bytes so no printf %b is needed.
C_BLUE=$'\033[38;2;0;153;255m';   C_ORANGE=$'\033[38;2;255;176;85m'
C_GREEN=$'\033[38;2;0;160;0m';    C_CYAN=$'\033[38;2;46;149;153m'
C_RED=$'\033[38;2;255;85;85m';    C_YELLOW=$'\033[38;2;230;200;0m'
C_PURPLE=$'\033[38;2;167;139;250m'; C_WHITE=$'\033[38;2;220;220;220m'
C_DIM=$'\033[2m';                 C_RESET=$'\033[0m'

# Bars
BAR_WIDTH=3
BAR_FILLED='▰'
BAR_EMPTY='▱'

# Misc
SEP=" ${C_DIM}·${C_RESET} "
SESSION_MARK='»'
CTX_WARN_THRESHOLD=90
CTX_WARN_GLYPH='⚠'

# Segment toggles (1=on, 0=off). All on by default.
SEG_MODEL=1; SEG_SESSION=1; SEG_GIT=1; SEG_PR=1; SEG_CONTEXT=1
SEG_EFFORT=1; SEG_LIMITS=1; SEG_EXTRA=1; SEG_COST=1

# Cache (overridable for tests)
CCV_CACHE_DIR="${CCV_CACHE_DIR:-/tmp/claude}"
CACHE_MAX_AGE=60

# ===== HELPERS =====
# Append a segment to OUT, inserting SEP when OUT is non-empty.
add() { [ -n "$OUT" ] && OUT+="$SEP"; OUT+="$1"; }

# ===== MAIN =====
main() {
    set -f  # disable globbing
    INPUT=$(cat)
    if [ -z "$INPUT" ]; then printf 'Claude'; exit 0; fi
    printf 'Claude'  # placeholder; replaced in Task 18
}

# Run main only when executed directly, not when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
```

- [ ] **Step 4: Create `tests/run_tests.sh` with helpers and the first test**

```bash
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

# (more tests appended by later tasks)

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 5: Run the tests, expect PASS**

Run: `bash tests/run_tests.sh`
Expected: ends with `1 passed, 0 failed` and exit 0.

- [ ] **Step 6: Commit**

```bash
git add .gitignore LICENSE statusline.sh tests/run_tests.sh
git commit -m "feat: scaffold statusline.sh, config header, test harness"
```

---

### Task 2: Progress bars (`bar_fill`, `make_bar`)

**Files:**
- Modify: `statusline.sh` (add functions after `add`)
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests** (insert before the final `printf '\n%d passed...'` line)

```bash
# ---- Task 2: bars ----
assert_eq "$(bar_fill 0)"   "0" "bar_fill 0 -> 0"
assert_eq "$(bar_fill 8)"   "1" "bar_fill 8 -> 1 (min-1 rule)"
assert_eq "$(bar_fill 50)"  "2" "bar_fill 50 -> 2 (rounding)"
assert_eq "$(bar_fill 76)"  "2" "bar_fill 76 -> 2"
assert_eq "$(bar_fill 93)"  "3" "bar_fill 93 -> 3"
assert_eq "$(bar_fill 100)" "3" "bar_fill 100 -> 3"
bar_out="$(make_bar 50 | strip)"
assert_eq "$bar_out" "▰▰▱" "make_bar 50 renders 2 filled, 1 empty"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL lines for `bar_fill`/`make_bar` ("command not found" output and failed asserts).

- [ ] **Step 3: Implement `bar_fill` and `make_bar`** (add to `statusline.sh` after `add`; `make_bar` calls `usage_level`/`level_color` from Task 3 — keep this order, Task 3 follows immediately and the integration is only exercised once both exist)

```bash
# Filled-cell count for a percentage (0..BAR_WIDTH), min 1 cell for any usage > 0.
bar_fill() {
    local p=$1 w=$BAR_WIDTH f
    f=$(( (p * w + 50) / 100 ))
    [ "$p" -gt 0 ] && [ "$f" -eq 0 ] && f=1
    [ "$f" -gt "$w" ] && f=$w
    echo "$f"
}

# Render a colored bar for a percentage.
make_bar() {
    local p=$1 f i col
    f=$(bar_fill "$p")
    col=$(level_color "$(usage_level "$p")")
    printf '%s' "$col"
    for ((i=0; i<f; i++)); do printf '%s' "$BAR_FILLED"; done
    printf '%s' "$C_DIM"
    for ((i=f; i<BAR_WIDTH; i++)); do printf '%s' "$BAR_EMPTY"; done
    printf '%s' "$C_RESET"
}
```

- [ ] **Step 4: Run tests** — note `make_bar` test will still fail until Task 3 defines `usage_level`/`level_color`; the six `bar_fill` asserts must PASS now.

Run: `bash tests/run_tests.sh`
Expected: all `bar_fill` asserts PASS; `make_bar` assert may FAIL (pending Task 3).

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add bar_fill and make_bar progress bars"
```

---

### Task 3: Usage color levels (`usage_level`, `level_color`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 3: usage levels ----
assert_eq "$(usage_level 0)"   "green"  "0% -> green"
assert_eq "$(usage_level 49)"  "green"  "49% -> green"
assert_eq "$(usage_level 50)"  "yellow" "50% -> yellow"
assert_eq "$(usage_level 70)"  "orange" "70% -> orange"
assert_eq "$(usage_level 90)"  "red"    "90% -> red"
assert_eq "$(level_color red)" "$C_RED" "level_color red -> C_RED"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `usage_level`/`level_color` (and the Task 2 `make_bar` test still failing).

- [ ] **Step 3: Implement**

```bash
# Map a percentage to a color level name.
usage_level() {
    local p=$1
    if   [ "$p" -ge 90 ]; then echo red
    elif [ "$p" -ge 70 ]; then echo orange
    elif [ "$p" -ge 50 ]; then echo yellow
    else echo green
    fi
}

# Map a level name to a palette escape.
level_color() {
    case "$1" in
        red)    printf '%s' "$C_RED" ;;
        orange) printf '%s' "$C_ORANGE" ;;
        yellow) printf '%s' "$C_YELLOW" ;;
        *)      printf '%s' "$C_GREEN" ;;
    esac
}
```

- [ ] **Step 4: Run tests** — Task 2 `make_bar` test now passes too.

Run: `bash tests/run_tests.sh`
Expected: all asserts so far PASS, ends `N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add usage_level and level_color"
```

---

### Task 4: Model-family accent (`accent_level`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 4: accent ----
assert_eq "$(accent_level 'Opus 4.8 (1M context)')" "opus"    "Opus -> opus"
assert_eq "$(accent_level 'Sonnet 4.6')"            "sonnet"  "Sonnet -> sonnet"
assert_eq "$(accent_level 'Haiku 4.5')"             "haiku"   "Haiku -> haiku"
assert_eq "$(accent_level 'Claude')"                "default" "unknown -> default"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `accent_level`.

- [ ] **Step 3: Implement**

```bash
# Classify a model display name into a color family.
accent_level() {
    case "$1" in
        *Opus*)   echo opus ;;
        *Sonnet*) echo sonnet ;;
        *Haiku*)  echo haiku ;;
        *)        echo default ;;
    esac
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add accent_level model classifier"
```

---

### Task 5: Token formatting (`fmt_tokens`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 5: fmt_tokens ----
assert_eq "$(fmt_tokens 500)"     "500"  "500 -> 500"
assert_eq "$(fmt_tokens 79000)"   "79k"  "79000 -> 79k"
assert_eq "$(fmt_tokens 1000000)" "1M"   "1000000 -> 1M"
assert_eq "$(fmt_tokens 1500000)" "1.5M" "1500000 -> 1.5M"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `fmt_tokens`.

- [ ] **Step 3: Implement** (note `LC_NUMERIC=C` — this is the locale-bug fix applied preventively)

```bash
# Format a token count: 500, 79k, 1M, 1.5M. Uppercase M, lowercase k.
fmt_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        LC_NUMERIC=C awk "BEGIN{v=$n/1000000; if(v==int(v)) printf \"%dM\", v; else printf \"%.1fM\", v}"
    elif [ "$n" -ge 1000 ]; then
        LC_NUMERIC=C awk "BEGIN{printf \"%.0fk\", $n/1000}"
    else
        printf '%d' "$n"
    fi
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add fmt_tokens with locale-safe formatting"
```

---

### Task 6: Session label (`fmt_session`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 6: fmt_session ----
assert_eq "$(fmt_session 'refactor-auth' 'a3f9c1e2-dead-beef')" "refactor-auth" "name wins"
assert_eq "$(fmt_session '' 'a3f9c1e2-dead-beef')"              "a3f9c1e2"      "no name -> short id"
assert_eq "$(fmt_session '' '')"                                ""              "neither -> empty"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `fmt_session`.

- [ ] **Step 3: Implement**

```bash
# Session label: name if set, else first 8 chars of id, else empty.
fmt_session() {
    local name=$1 id=$2
    if [ -n "$name" ]; then printf '%s' "$name"; else printf '%s' "${id:0:8}"; fi
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add fmt_session"
```

---

### Task 7: Reset-time formatting (`fmt_reset`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests** (deterministic via `TZ=UTC` and epoch 0)

```bash
# ---- Task 7: fmt_reset ----
assert_eq "$(TZ=UTC fmt_reset 0 time)"     "00:00"        "epoch 0 time"
assert_eq "$(TZ=UTC fmt_reset 0 date)"     "Jan 1"        "epoch 0 date"
assert_eq "$(TZ=UTC fmt_reset 0 datetime)" "Thu Jan 1, 00:00" "epoch 0 datetime"
assert_eq "$(fmt_reset '' time)"           ""             "empty -> empty"
assert_eq "$(fmt_reset null time)"         ""             "null -> empty"
assert_eq "$(TZ=UTC fmt_reset '1970-01-01T00:00:00Z' time)" "00:00" "ISO string accepted"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `fmt_reset`.

- [ ] **Step 3: Implement** (Linux GNU `date`; accepts epoch int or ISO string)

```bash
# Format a reset time (epoch int OR ISO string) to local time. style: time|datetime|date.
fmt_reset() {
    local v=$1 style=$2 epoch fmt
    { [ -z "$v" ] || [ "$v" = null ]; } && return
    if [[ "$v" =~ ^[0-9]+$ ]]; then epoch=$v; else epoch=$(date -d "$v" +%s 2>/dev/null); fi
    [ -z "$epoch" ] && return
    case "$style" in
        time)     fmt='%H:%M' ;;
        datetime) fmt='%a %b %-d, %H:%M' ;;
        *)        fmt='%b %-d' ;;
    esac
    date -d "@$epoch" +"$fmt" 2>/dev/null
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add fmt_reset time formatter"
```

---

### Task 8: Input parsing (`parse_input`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests** (set `INPUT`, call `parse_input`, check globals; prefers pre-calc `used_percentage`, else computes)

```bash
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
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `parse_input` globals.

- [ ] **Step 3: Implement** (single jq pass, `@sh` for safe quoting)

```bash
# One jq pass: emit `KEY=value` shell assignments, then eval them into globals.
parse_input() {
    local assigns
    assigns=$(printf '%s' "$INPUT" | jq -r '
        "MODEL=\(.model.display_name // "Claude" | @sh)",
        "CWD=\(.cwd // "" | @sh)",
        "SESSION_NAME=\(.session_name // "" | @sh)",
        "SESSION_ID=\(.session_id // "" | @sh)",
        "CTX_PCT=\(((.context_window.used_percentage) // (((.context_window.current_usage.input_tokens // 0) + (.context_window.current_usage.cache_creation_input_tokens // 0) + (.context_window.current_usage.cache_read_input_tokens // 0)) * 100 / (.context_window.context_window_size // 200000))) | floor | @sh)",
        "CTX_SIZE=\(.context_window.context_window_size // 200000 | @sh)",
        "CTX_INPUT=\(.context_window.current_usage.input_tokens // 0 | @sh)",
        "CTX_CC=\(.context_window.current_usage.cache_creation_input_tokens // 0 | @sh)",
        "CTX_CR=\(.context_window.current_usage.cache_read_input_tokens // 0 | @sh)",
        "EFFORT=\(.effort.level // "" | @sh)",
        "FH_PCT=\(.rate_limits.five_hour.used_percentage // "" | @sh)",
        "FH_RESET=\(.rate_limits.five_hour.resets_at // "" | @sh)",
        "SD_PCT=\(.rate_limits.seven_day.used_percentage // "" | @sh)",
        "SD_RESET=\(.rate_limits.seven_day.resets_at // "" | @sh)",
        "PR_NUM=\(.pr.number // "" | @sh)",
        "PR_STATE=\(.pr.review_state // "" | @sh)",
        "COST=\(.cost.total_cost_usd // "" | @sh)"
    ' 2>/dev/null)
    eval "$assigns"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add parse_input single-jq-pass parser"
```

---

### Task 9: Model segment (`seg_model`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 9: seg_model ----
OUT=""; MODEL="Opus 4.8 (1M context)"; seg_model
assert_eq "$(printf '%s' "$OUT" | strip)" "Opus 4.8 1M" "seg_model strips (...context) and keeps 1M"
assert_contains "$OUT" "$C_PURPLE" "Opus uses purple accent"
OUT=""; MODEL="Sonnet 4.6"; seg_model
assert_contains "$OUT" "$C_BLUE" "Sonnet uses blue accent"
SEG_MODEL=0; OUT=""; MODEL="Opus"; seg_model
assert_eq "$OUT" "" "toggle off -> no output"
SEG_MODEL=1
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `seg_model`.

- [ ] **Step 3: Implement**

```bash
# Model name with family accent; "(1M context)" suffix collapsed to "1M".
seg_model() {
    [ "$SEG_MODEL" = 1 ] || return
    local name col
    name=$(printf '%s' "$MODEL" | sed 's/ *(\([0-9.]*[kKmM]*\) context)/ \1/')
    case "$(accent_level "$MODEL")" in
        opus)   col=$C_PURPLE ;;
        sonnet) col=$C_BLUE ;;
        haiku)  col=$C_CYAN ;;
        *)      col=$C_BLUE ;;
    esac
    add "${col}${name}${C_RESET}"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add seg_model with family accent"
```

---

### Task 10: Session segment (`seg_session`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 10: seg_session ----
OUT=""; SESSION_NAME="demo"; SESSION_ID="abcd1234efgh"; seg_session
assert_eq "$(printf '%s' "$OUT" | strip)" "»demo" "named session"
OUT=""; SESSION_NAME=""; SESSION_ID="abcd1234efgh"; seg_session
assert_eq "$(printf '%s' "$OUT" | strip)" "»abcd1234" "unnamed -> short id"
OUT=""; SESSION_NAME=""; SESSION_ID=""; seg_session
assert_eq "$OUT" "" "no session data -> nothing"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `seg_session`.

- [ ] **Step 3: Implement**

```bash
# Conversation reminder: »name or »shortid.
seg_session() {
    [ "$SEG_SESSION" = 1 ] || return
    local s; s=$(fmt_session "$SESSION_NAME" "$SESSION_ID")
    [ -z "$s" ] && return
    add "${C_DIM}${SESSION_MARK}${C_RESET}${C_WHITE}${s}${C_RESET}"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add seg_session"
```

---

### Task 11: Git segment (`seg_git`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests** (build a throwaway git repo in the test cache dir)

```bash
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
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `seg_git`.

- [ ] **Step 3: Implement**

```bash
# dir@branch [*dirty] [↑ahead ↓behind] [+add -del]. Hidden when cwd is not a repo.
seg_git() {
    [ "$SEG_GIT" = 1 ] || return
    [ -n "$CWD" ] || return
    local branch; branch=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null) || return
    [ -n "$branch" ] || return
    local dir="${CWD##*/}"
    local s="${C_CYAN}${dir}${C_RESET}${C_DIM}@${C_RESET}${C_GREEN}${branch}${C_RESET}"
    [ -n "$(git -C "$CWD" status --porcelain 2>/dev/null)" ] && s+="${C_YELLOW}*${C_RESET}"
    local counts behind ahead
    counts=$(git -C "$CWD" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    if [ -n "$counts" ]; then
        behind=$(printf '%s' "$counts" | awk '{print $1}')
        ahead=$(printf '%s' "$counts" | awk '{print $2}')
        [ "${ahead:-0}" -gt 0 ] 2>/dev/null && s+=" ${C_CYAN}↑${ahead}${C_RESET}"
        [ "${behind:-0}" -gt 0 ] 2>/dev/null && s+="${C_CYAN}↓${behind}${C_RESET}"
    fi
    local stat; stat=$(git -C "$CWD" diff --numstat 2>/dev/null | awk '{a+=$1; d+=$2} END{if (a+d>0) printf "%d %d", a, d}')
    if [ -n "$stat" ]; then
        s+=" ${C_GREEN}+$(printf '%s' "$stat" | awk '{print $1}')${C_RESET} ${C_RED}-$(printf '%s' "$stat" | awk '{print $2}')${C_RESET}"
    fi
    add "$s"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add seg_git with dirty/ahead-behind/diffstat"
```

---

### Task 12: PR segment (`seg_pr`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 12: seg_pr ----
OUT=""; PR_NUM="142"; PR_STATE="pending"; seg_pr
assert_eq "$(printf '%s' "$OUT" | strip)" "PR #142 pending" "pending PR"
assert_contains "$OUT" "$C_YELLOW" "pending uses yellow"
OUT=""; PR_NUM="142"; PR_STATE="changes_requested"; seg_pr
assert_eq "$(printf '%s' "$OUT" | strip)" "PR #142 changes" "changes_requested -> changes label"
assert_contains "$OUT" "$C_RED" "changes uses red"
OUT=""; PR_NUM=""; PR_STATE=""; seg_pr
assert_eq "$OUT" "" "no PR -> hidden"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `seg_pr`.

- [ ] **Step 3: Implement**

```bash
# PR #<n> <state>. Hidden when no PR. changes_requested shown as "changes".
seg_pr() {
    [ "$SEG_PR" = 1 ] || return
    [ -n "$PR_NUM" ] || return
    local col label="$PR_STATE"
    case "$PR_STATE" in
        approved)          col=$C_GREEN ;;
        pending)           col=$C_YELLOW ;;
        changes_requested) col=$C_RED; label=changes ;;
        draft)             col=$C_DIM ;;
        *)                 col=$C_WHITE ;;
    esac
    add "${C_WHITE}PR${C_RESET} ${C_DIM}#${C_RESET}${col}${PR_NUM}${PR_STATE:+ $label}${C_RESET}"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add seg_pr"
```

---

### Task 13: Context segment (`seg_context`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 13: seg_context ----
OUT=""; CTX_PCT=8; CTX_SIZE=1000000; CTX_INPUT=40000; CTX_CC=20000; CTX_CR=19000; seg_context
c="$(printf '%s' "$OUT" | strip)"
assert_contains "$c" "ctx" "has ctx label"
assert_contains "$c" "8%"  "shows percent"
assert_contains "$c" "79k/1M" "shows used/total tokens"
assert_not_contains "$c" "$CTX_WARN_GLYPH" "no warning below threshold"
OUT=""; CTX_PCT=93; CTX_SIZE=1000000; CTX_INPUT=930000; CTX_CC=0; CTX_CR=0; seg_context
c="$(printf '%s' "$OUT" | strip)"
assert_contains "$c" "$CTX_WARN_GLYPH" "warning at >90%"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `seg_context`.

- [ ] **Step 3: Implement**

```bash
# Context bar + percent + used/total tokens; warns at the threshold.
seg_context() {
    [ "$SEG_CONTEXT" = 1 ] || return
    local cur=$(( CTX_INPUT + CTX_CC + CTX_CR )) used total col
    used=$(fmt_tokens "$cur"); total=$(fmt_tokens "$CTX_SIZE")
    col=$(level_color "$(usage_level "$CTX_PCT")")
    local s="${C_WHITE}ctx${C_RESET} $(make_bar "$CTX_PCT") ${col}${CTX_PCT}%${C_RESET} ${C_DIM}${used}/${total}${C_RESET}"
    [ "$CTX_PCT" -ge "$CTX_WARN_THRESHOLD" ] && s+=" ${C_RED}${CTX_WARN_GLYPH}${C_RESET}"
    add "$s"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add seg_context with bar and pressure warning"
```

---

### Task 14: Effort segment (`seg_effort`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 14: seg_effort ----
OUT=""; EFFORT="high"; seg_effort
assert_eq "$(printf '%s' "$OUT" | strip)" "effort high" "high effort"
OUT=""; EFFORT="medium"; seg_effort
assert_eq "$(printf '%s' "$OUT" | strip)" "effort med" "medium -> med"
OUT=""; EFFORT=""; seg_effort
assert_eq "$(printf '%s' "$OUT" | strip)" "effort med" "empty -> default med"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `seg_effort`.

- [ ] **Step 3: Implement**

```bash
# Reasoning effort, color-coded. medium displays as "med". Defaults to medium.
seg_effort() {
    [ "$SEG_EFFORT" = 1 ] || return
    local e="${EFFORT:-medium}" label col
    label="$e"
    case "$e" in
        low)    col=$C_DIM ;;
        medium) col=$C_ORANGE; label=med ;;
        high)   col=$C_GREEN ;;
        xhigh)  col=$C_PURPLE ;;
        max)    col=$C_RED ;;
        *)      col=$C_GREEN ;;
    esac
    add "${C_WHITE}effort${C_RESET} ${col}${label}${C_RESET}"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add seg_effort"
```

---

### Task 15: Rate-limit segment (`seg_limits`) — builtin path

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests** (fractional percentages exercise the locale-safe `printf`)

```bash
# ---- Task 15: seg_limits ----
OUT=""; FH_PCT="42.5"; FH_RESET=0; SD_PCT="71.2"; SD_RESET=0; seg_limits
l="$(printf '%s' "$OUT" | strip)"
assert_contains "$l" "5h" "has 5h"
assert_contains "$l" "43%" "5h rounds 42.5 -> 43"
assert_contains "$l" "7d" "has 7d"
assert_contains "$l" "71%" "7d rounds 71.2 -> 71"
OUT=""; FH_PCT=""; SD_PCT=""; seg_limits
assert_eq "$OUT" "" "no limit data -> nothing"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `seg_limits`.

- [ ] **Step 3: Implement** (`LC_NUMERIC=C printf` is the explicit fix for the original's locale bug)

```bash
# 5h and 7d rate-limit bars with reset times. Renders from builtin stdin values.
seg_limits() {
    [ "$SEG_LIMITS" = 1 ] || return
    local p col r
    if [ -n "$FH_PCT" ]; then
        p=$(LC_NUMERIC=C printf '%.0f' "$FH_PCT")
        col=$(level_color "$(usage_level "$p")")
        local s="${C_WHITE}5h${C_RESET} $(make_bar "$p") ${col}${p}%${C_RESET}"
        r=$(fmt_reset "$FH_RESET" time); [ -n "$r" ] && s+=" ${C_DIM}@${r}${C_RESET}"
        add "$s"
    fi
    if [ -n "$SD_PCT" ]; then
        p=$(LC_NUMERIC=C printf '%.0f' "$SD_PCT")
        col=$(level_color "$(usage_level "$p")")
        local s="${C_WHITE}7d${C_RESET} $(make_bar "$p") ${col}${p}%${C_RESET}"
        r=$(fmt_reset "$SD_RESET" datetime); [ -n "$r" ] && s+=" ${C_DIM}@${r}${C_RESET}"
        add "$s"
    fi
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS (no `printf: ... nombre non valable` errors even under a comma locale).

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add seg_limits (builtin path), locale-safe"
```

---

### Task 16: Usage API + cache + extra usage (`get_oauth_token`, `load_usage`, `seg_extra`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

**Design:** `load_usage` sets `EXTRA_LINE` (the rendered extra segment string, or empty) and provides a fallback for `FH_PCT`/`SD_PCT` from cache when builtin values are absent. Network fetch is skipped entirely when `CCV_NO_FETCH=1` (tests) or when builtin rate-limit values are already present and the cache is fresh. `seg_extra` just appends `EXTRA_LINE`.

- [ ] **Step 1: Add failing tests** (pre-seed a cache file so no network is needed; verify extra rendering and cache fallback)

```bash
# ---- Task 16: load_usage + seg_extra ----
mkdir -p "$T_CACHE"
# cache hash uses sha256 of the config dir; load_usage computes the same path.
cfg_hash=$(printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sha256sum | cut -c1-8)
printf '%s' '{"five_hour":{"utilization":5,"resets_at":0},"seven_day":{"utilization":9,"resets_at":0},"extra_usage":{"is_enabled":true,"utilization":34,"used_credits":340,"monthly_limit":1000}}' \
  > "$T_CACHE/statusline-usage-cache-${cfg_hash}.json"
# Builtin present: extra still comes from cache; limits stay builtin.
OUT=""; EXTRA_LINE=""; FH_PCT="12"; SD_PCT="34"; CCV_NO_FETCH=1; load_usage; seg_extra
e="$(printf '%s' "$OUT" | strip)"
assert_contains "$e" "extra" "extra label present"
assert_contains "$e" "\$3.40/\$10.00" "extra credits formatted from cents"
# Builtin absent: load_usage backfills FH_PCT/SD_PCT from cache utilization.
OUT=""; EXTRA_LINE=""; FH_PCT=""; SD_PCT=""; FH_RESET=""; SD_RESET=""; CCV_NO_FETCH=1; load_usage
assert_eq "$FH_PCT" "5" "FH_PCT backfilled from cache"
assert_eq "$SD_PCT" "9" "SD_PCT backfilled from cache"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `load_usage`/`seg_extra`.

- [ ] **Step 3: Implement**

```bash
# Resolve an OAuth token: env override, then Linux credentials file, then GNOME keyring.
get_oauth_token() {
    [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && { printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN"; return 0; }
    local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" creds="$cfg/.credentials.json" t=""
    if [ -f "$creds" ]; then
        t=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null)
        [ -n "$t" ] && [ "$t" != null ] && { printf '%s' "$t"; return 0; }
    fi
    if command -v secret-tool >/dev/null 2>&1; then
        local blob; blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        [ -n "$blob" ] && t=$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        [ -n "$t" ] && [ "$t" != null ] && { printf '%s' "$t"; return 0; }
    fi
    printf ''
}

# Populate EXTRA_LINE and backfill FH/SD from cache or a fresh API fetch.
load_usage() {
    EXTRA_LINE=""
    mkdir -p "$CCV_CACHE_DIR" 2>/dev/null
    local cfg_hash; cfg_hash=$(printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sha256sum | cut -c1-8)
    local cache="$CCV_CACHE_DIR/statusline-usage-cache-${cfg_hash}.json"
    local data="" fresh=0
    if [ -s "$cache" ]; then
        local mtime age; mtime=$(stat -c %Y "$cache" 2>/dev/null); age=$(( $(date +%s) - mtime ))
        [ "$age" -lt "$CACHE_MAX_AGE" ] && fresh=1
        data=$(cat "$cache" 2>/dev/null)
    fi
    # Fetch only when cache is stale, builtin limits are absent, and fetching is allowed.
    if [ "$fresh" -ne 1 ] && [ -z "$FH_PCT" ] && [ "${CCV_NO_FETCH:-0}" != 1 ]; then
        touch "$cache"  # stampede lock
        local token; token=$(get_oauth_token)
        if [ -n "$token" ]; then
            local resp; resp=$(curl -s --max-time 10 \
                -H "Accept: application/json" -H "Content-Type: application/json" \
                -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$resp" ] && printf '%s' "$resp" | jq -e '.five_hour' >/dev/null 2>&1; then
                data="$resp"; printf '%s' "$resp" > "$cache"
            fi
        fi
        [ -f "$cache" ] && [ ! -s "$cache" ] && rm -f "$cache"
    fi
    [ -z "$data" ] && return
    # Backfill rate limits from cache/API when builtin values are absent.
    if [ -z "$FH_PCT" ]; then
        FH_PCT=$(printf '%s' "$data" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
        FH_RESET=$(printf '%s' "$data" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
        SD_PCT=$(printf '%s' "$data" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
        SD_RESET=$(printf '%s' "$data" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
    fi
    # Build the extra-usage segment if enabled.
    local enabled; enabled=$(printf '%s' "$data" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
    [ "$enabled" != true ] && return
    local pct used limit
    pct=$(printf '%s' "$data" | jq -r '.extra_usage.utilization // 0' | LC_NUMERIC=C awk '{printf "%.0f", $1}')
    used=$(printf '%s' "$data" | jq -r '.extra_usage.used_credits // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
    limit=$(printf '%s' "$data" | jq -r '.extra_usage.monthly_limit // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
    EXTRA_LINE="${C_WHITE}extra${C_RESET} $(level_color "$(usage_level "$pct")")\$${used}/\$${limit}${C_RESET}"
}

# Append the extra-usage segment computed by load_usage.
seg_extra() {
    [ "$SEG_EXTRA" = 1 ] || return
    [ -n "$EXTRA_LINE" ] || return
    add "$EXTRA_LINE"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add usage API/cache loading and seg_extra"
```

---

### Task 17: Cost segment (`seg_cost`)

**Files:**
- Modify: `statusline.sh`
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing tests**

```bash
# ---- Task 17: seg_cost ----
OUT=""; COST="1.2699"; seg_cost
assert_eq "$(printf '%s' "$OUT" | strip)" "\$1.27" "cost rounded to 2 dp"
OUT=""; COST=""; seg_cost
assert_eq "$OUT" "" "no cost -> hidden"
```

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL for `seg_cost`.

- [ ] **Step 3: Implement**

```bash
# Session cost from .cost.total_cost_usd. Hidden when absent.
seg_cost() {
    [ "$SEG_COST" = 1 ] || return
    [ -n "$COST" ] || return
    local c; c=$(LC_NUMERIC=C printf '%.2f' "$COST" 2>/dev/null) || return
    add "${C_WHITE}\$${C_RESET}${C_GREEN}${c}${C_RESET}"
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: add seg_cost"
```

---

### Task 18: Wire `main`, full integration tests

**Files:**
- Modify: `statusline.sh` (replace the Task 1 placeholder `main` body)
- Test: `tests/run_tests.sh`

- [ ] **Step 1: Add failing end-to-end tests**

```bash
# ---- Task 18: full render ----
full='{"model":{"display_name":"Opus 4.8 (1M context)"},"cwd":"'"$T_CACHE"'","session_name":"demo","session_id":"abcd1234","context_window":{"used_percentage":76,"context_window_size":1000000,"current_usage":{"input_tokens":760000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"effort":{"level":"xhigh"},"rate_limits":{"five_hour":{"used_percentage":54,"resets_at":0},"seven_day":{"used_percentage":93,"resets_at":0}},"pr":{"number":142,"review_state":"pending"},"cost":{"total_cost_usd":8.91}}'
o="$(run_sl "$full" | strip)"
assert_contains "$o" "Opus 4.8 1M" "model in full render"
assert_contains "$o" "»demo"       "session in full render"
assert_contains "$o" "PR #142 pending" "pr in full render"
assert_contains "$o" "76%"         "context in full render"
assert_contains "$o" "effort xhigh" "effort in full render"
assert_contains "$o" "5h"          "5h in full render"
assert_contains "$o" "7d"          "7d in full render"
assert_contains "$o" " · "         "segments joined by separator"
# Toggle: disabling a segment via env removes it.
o="$(printf '%s' "$full" | SEG_PR=0 CCV_NO_FETCH=1 CCV_CACHE_DIR="$T_CACHE" bash "$SL" | strip)"
assert_not_contains "$o" "PR #142" "SEG_PR=0 hides the PR segment"
```

Note: for the toggle test to work, the config-header toggles must honor pre-set environment values. Update the toggle lines in `statusline.sh` to `SEG_MODEL="${SEG_MODEL:-1}"` form in this task.

- [ ] **Step 2: Run tests, verify failure**

Run: `bash tests/run_tests.sh`
Expected: FAIL (placeholder `main` still prints only "Claude").

- [ ] **Step 3: Make toggles env-overridable** — replace the toggle block in the CONFIG header with:

```bash
SEG_MODEL="${SEG_MODEL:-1}"; SEG_SESSION="${SEG_SESSION:-1}"; SEG_GIT="${SEG_GIT:-1}"
SEG_PR="${SEG_PR:-1}"; SEG_CONTEXT="${SEG_CONTEXT:-1}"; SEG_EFFORT="${SEG_EFFORT:-1}"
SEG_LIMITS="${SEG_LIMITS:-1}"; SEG_EXTRA="${SEG_EXTRA:-1}"; SEG_COST="${SEG_COST:-1}"
```

- [ ] **Step 4: Replace the `main` body** (the placeholder from Task 1)

```bash
main() {
    set -f
    INPUT=$(cat)
    if [ -z "$INPUT" ]; then printf 'Claude'; exit 0; fi
    parse_input
    load_usage
    OUT=""
    seg_model
    seg_session
    seg_git
    seg_pr
    seg_context
    seg_effort
    seg_limits
    seg_extra
    seg_cost
    printf '%s' "$OUT"
}
```

- [ ] **Step 5: Run tests, verify pass**

Run: `bash tests/run_tests.sh`
Expected: all PASS, ends `N passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add statusline.sh tests/run_tests.sh
git commit -m "feat: wire main and full segment pipeline"
```

---

### Task 19: Sample fixtures, visual harness, README

**Files:**
- Create: `samples/run.sh`, `samples/low-usage.json`, `samples/high-usage.json`, `samples/no-git.json`, `samples/no-limits.json`
- Create: `README.md`

- [ ] **Step 1: Create the four fixtures**

`samples/low-usage.json`:
```json
{"model":{"display_name":"Opus 4.8 (1M context)"},"cwd":"/tmp","session_name":"review-statusline","session_id":"abcd1234efgh","context_window":{"used_percentage":8,"context_window_size":1000000,"current_usage":{"input_tokens":40000,"cache_creation_input_tokens":20000,"cache_read_input_tokens":19000}},"effort":{"level":"high"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":0},"seven_day":{"used_percentage":23,"resets_at":0}},"cost":{"total_cost_usd":0.04}}
```

`samples/high-usage.json`:
```json
{"model":{"display_name":"Opus 4.8 (1M context)"},"cwd":"/tmp","session_name":"ship-v2","session_id":"ffff0000","context_window":{"used_percentage":93,"context_window_size":1000000,"current_usage":{"input_tokens":930000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"effort":{"level":"xhigh"},"rate_limits":{"five_hour":{"used_percentage":78.4,"resets_at":0},"seven_day":{"used_percentage":96.1,"resets_at":0}},"pr":{"number":142,"review_state":"pending"},"cost":{"total_cost_usd":8.91}}
```

`samples/no-git.json`:
```json
{"model":{"display_name":"Haiku 4.5"},"cwd":"/tmp","session_id":"a3f9c1e2dead","context_window":{"used_percentage":31,"context_window_size":200000,"current_usage":{"input_tokens":62000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"effort":{"level":"low"},"cost":{"total_cost_usd":0.02}}
```

`samples/no-limits.json`:
```json
{"model":{"display_name":"Sonnet 4.6"},"cwd":"/tmp","session_name":"offline","session_id":"0011223344","context_window":{"used_percentage":47,"context_window_size":200000,"current_usage":{"input_tokens":94000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"effort":{"level":"medium"},"cost":{"total_cost_usd":1.27}}
```

- [ ] **Step 2: Create `samples/run.sh`** (network off, isolated temp cache → reproducible)

```bash
#!/usr/bin/env bash
# Render every sample fixture through statusline.sh for visual review.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL="$HERE/../statusline.sh"
CACHE="$(mktemp -d)"; trap 'rm -rf "$CACHE"' EXIT
for f in "$HERE"/*.json; do
    printf '── %s ──\n' "$(basename "$f" .json)"
    CCV_NO_FETCH=1 CCV_CACHE_DIR="$CACHE" bash "$SL" < "$f"
    printf '\n\n'
done
```

- [ ] **Step 3: Run the harness and eyeball output**

Run: `bash samples/run.sh`
Expected: four labeled, colored status lines; no `printf`/locale errors on any line (re-run under `LC_ALL=fr_FR.UTF-8 bash samples/run.sh` if the locale is installed, to confirm the locale fix).

- [ ] **Step 4: Create `README.md`** (SEO keywords in title and description)

```markdown
# ClaudeCodeVitals — a beautiful Claude Code statusline

A custom **Claude Code statusline** with live progress bars for context,
rate limits, and cost — plus model-aware accents, rich git, PR status, and a
session reminder. Single Bash script, Linux, no Nerd Font required.

![preview](#)  <!-- add a screenshot -->

## Segments

`model · session · git · pr · ctx · effort · 5h · 7d · extra · cost`

- **model** — accent-colored by family (Opus/Sonnet/Haiku)
- **session** — your `/rename`d session name, else a short id
- **git** — `dir@branch`, dirty `*`, `↑/↓` vs upstream, `+/-` diffstat
- **pr** — PR number + review state (auto-hidden off a PR)
- **ctx** — context bar + %, turns red with ⚠ above 90%
- **effort** — reasoning effort
- **5h / 7d** — rate-limit bars with reset times
- **extra** — overage credits ($used/$limit) when enabled
- **cost** — session cost from Claude Code's reported usage

## Requirements

Linux, `jq`, `curl`, `git`, GNU coreutils. Claude Code with OAuth
(Pro/Max) for rate-limit and extra-usage data.

## Install

Point your `~/.claude/settings.json` at the script:

```json
{ "statusLine": { "type": "command", "command": "/absolute/path/to/statusline.sh" } }
```

Restart Claude Code.

## Configuration

Edit the CONFIG header in `statusline.sh`: palette, bar glyphs/width,
separator, and per-segment on/off toggles (also overridable via env, e.g.
`SEG_PR=0`).

## Testing

`bash tests/run_tests.sh` runs unit + integration tests.
`bash samples/run.sh` renders sample fixtures for visual review.

## Credits

Inspired by [daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine) (MIT). Independent rewrite. MIT licensed.
```

- [ ] **Step 5: Make scripts executable and commit**

```bash
chmod +x statusline.sh samples/run.sh tests/run_tests.sh
git add samples README.md statusline.sh tests/run_tests.sh
git commit -m "feat: add sample fixtures, visual harness, and README"
```

---

## Self-Review

**Spec coverage:**
- Motivation/locale bug → Tasks 5, 15, 17 use `LC_NUMERIC=C`; Step 3 of Task 19 re-runs under `fr_FR` to confirm. ✓
- One jq pass → Task 8. ✓
- Segments model/session/git/pr/ctx/effort/5h/7d/extra/cost → Tasks 9–17. ✓
- 3-cell plain bars, min-1-cell, threshold color → Tasks 2, 3. ✓
- Pre-calculated `used_percentage` with fallback → Task 8. ✓
- Model-aware accent → Tasks 4, 9. ✓
- Context-pressure warning → Task 13. ✓
- Session cost from `.cost.total_cost_usd` → Task 17. ✓
- Conversation reminder (name→id) → Tasks 6, 10. ✓
- PR status → Task 12. ✓
- Permission mode omitted → no task (correct; documented non-goal). ✓
- Config header + per-segment toggles (env-overridable) → Tasks 1, 18. ✓
- Data sourcing: stdin→cache→API, 60s, stampede lock, OAuth resolution → Task 16. ✓
- Error handling: empty stdin→"Claude", jq defaults, API failure→cache→hidden → Tasks 1, 8, 16. ✓
- Repo layout, samples harness, README, MIT+attribution → Tasks 1, 19. ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to" — every code/test step contains real content. The README screenshot is intentionally a stub (`![preview](#)`) to be filled after first run; not a logic placeholder.

**Type/name consistency:** Global and function names match the inventory in "Conventions"; `make_bar`→`bar_fill`/`usage_level`/`level_color`, `seg_context` uses `make_bar`, `load_usage` sets `EXTRA_LINE` consumed by `seg_extra`, toggles consistently `SEG_*`. ✓
