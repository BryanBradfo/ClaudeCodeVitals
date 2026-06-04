#!/usr/bin/env bash
# ClaudeCodeVitals installer — points Claude Code's statusLine at statusline.sh.
# Merges into ~/.claude/settings.json (preserving your other keys), backing up
# any existing file first. Idempotent: re-run any time to refresh the path.
#
# Usage:  ./install.sh            install into $CLAUDE_CONFIG_DIR or ~/.claude
#         CLAUDE_CONFIG_DIR=… ./install.sh   install into a custom config dir
set -euo pipefail

# Absolute path to the script, resolved from where THIS installer lives, so the
# configured command works regardless of the cwd Claude Code launches from.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/statusline.sh"

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CONFIG_DIR/settings.json"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required — https://jqlang.github.io/jq/" >&2; exit 1; }
[ -f "$SCRIPT" ] || { echo "error: statusline.sh not found next to installer ($SCRIPT)" >&2; exit 1; }

chmod +x "$SCRIPT"
mkdir -p "$CONFIG_DIR"

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
