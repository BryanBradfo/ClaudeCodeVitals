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

# ===== MAIN =====
main() {
    set -f  # disable globbing
    INPUT=$(cat)
    if [ -z "$INPUT" ]; then printf 'Claude'; exit 0; fi
    printf 'Claude'  # placeholder; replaced in Task 18
}

# Run main only when executed directly, not when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
