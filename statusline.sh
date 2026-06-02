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

# Filled-cell count for a percentage (0..BAR_WIDTH), min 1 cell for any usage > 0.
bar_fill() {
    local p=$1 w=$BAR_WIDTH f
    f=$(( (p * w + 50) / 100 ))
    [ "$p" -gt 0 ] && [ "$f" -eq 0 ] && f=1
    [ "$f" -gt "$w" ] && f=$w
    echo "$f"
}

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
    LC_TIME=C date -d "@$epoch" +"$fmt" 2>/dev/null
}

# Session label: name if set, else first 8 chars of id, else empty.
fmt_session() {
    local name=$1 id=$2
    if [ -n "$name" ]; then printf '%s' "$name"; else printf '%s' "${id:0:8}"; fi
}

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

# Classify a model display name into a color family.
accent_level() {
    case "$1" in
        *Opus*)   echo opus ;;
        *Sonnet*) echo sonnet ;;
        *Haiku*)  echo haiku ;;
        *)        echo default ;;
    esac
}

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

# Conversation reminder: »name or »shortid.
seg_session() {
    [ "$SEG_SESSION" = 1 ] || return
    local s; s=$(fmt_session "$SESSION_NAME" "$SESSION_ID")
    [ -z "$s" ] && return
    add "${C_DIM}${SESSION_MARK}${C_RESET}${C_WHITE}${s}${C_RESET}"
}

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

# ===== MAIN =====
main() {
    set -f  # disable globbing
    INPUT=$(cat)
    if [ -z "$INPUT" ]; then printf 'Claude'; exit 0; fi
    printf 'Claude'  # placeholder; replaced in Task 18
}

# Run main only when executed directly, not when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
