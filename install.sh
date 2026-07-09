#!/usr/bin/env bash
# ClaudeCodeVitals installer — points Claude Code's statusLine at statusline.sh.
# Merges into ~/.claude/settings.json (preserving your other keys), backing up
# any existing file first. Idempotent: re-run any time to refresh the path.
#
# By default the statusLine points at statusline.sh inside this clone, so a
# `git pull` refreshes your live status line. Pass --copy (or set CCV_COPY=1)
# to copy the script into your config dir and point there instead, so the
# status line keeps working even if you later delete this clone.
#
# Usage:  ./install.sh            install into $CLAUDE_CONFIG_DIR or ~/.claude
#         ./install.sh --copy     copy statusline.sh into the config dir first
#         CLAUDE_CONFIG_DIR=… ./install.sh   install into a custom config dir
set -euo pipefail

COPY="${CCV_COPY:-0}"
for arg in "$@"; do
    case "$arg" in
        --copy)    COPY=1 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "error: unknown argument '$arg' (try --copy or --help)" >&2; exit 1 ;;
    esac
done

# Absolute path to the script, resolved from where THIS installer lives, so the
# configured command works regardless of the cwd Claude Code launches from.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/statusline.sh"

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CONFIG_DIR/settings.json"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required — https://jqlang.github.io/jq/" >&2; exit 1; }
[ -f "$SRC" ] || { echo "error: statusline.sh not found next to installer ($SRC)" >&2; exit 1; }

mkdir -p "$CONFIG_DIR"

# Which path settings.json references. With --copy, install a standalone copy
# into the config dir so deleting this clone won't break the status line;
# otherwise point at the script in place.
if [ "$COPY" = 1 ]; then
    SCRIPT="$CONFIG_DIR/statusline.sh"
    if [ "$SRC" -ef "$SCRIPT" ]; then
        echo "note: source and destination are the same file — nothing to copy"
    else
        cp "$SRC" "$SCRIPT"
        echo "copied statusline.sh → $SCRIPT"
    fi
else
    SCRIPT="$SRC"
fi

chmod +x "$SCRIPT"

# Load existing settings (or start from an empty object); refuse to touch invalid JSON.
if [ -f "$SETTINGS" ]; then
    if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
        echo "error: $SETTINGS exists but is not valid JSON — aborting so nothing is lost" >&2
        exit 1
    fi
    backup="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$backup"
    echo "backed up existing settings → $backup"
    current="$(cat "$SETTINGS")"
else
    current='{}'
fi

# Set exactly the statusLine key; everything else in the file is preserved.
updated="$(printf '%s' "$current" | jq --arg cmd "$SCRIPT" \
    '.statusLine = {type: "command", command: $cmd}')"

# Atomic write: temp beside the target (same filesystem) then rename.
tmp="$(mktemp "$SETTINGS.XXXXXX")"
printf '%s\n' "$updated" > "$tmp"
mv "$tmp" "$SETTINGS"

echo "✓ statusLine configured → $SCRIPT"
echo "  Restart Claude Code (or start a new session) to see it."
