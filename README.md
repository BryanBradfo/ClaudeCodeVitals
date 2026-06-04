# ClaudeCodeVitals — a beautiful Claude Code statusline

A custom **Claude Code statusline** with live progress bars for context,
rate limits, and cost — plus model-aware accents, rich git, PR status, and a
session reminder. Single Bash script, Linux, no Nerd Font required.

![ClaudeCodeVitals statusline preview](docs/preview.png)

<sub>Four sample states rendered from `samples/run.sh` — context near limit, a
fresh session, no-git on Haiku, and an API key with no rate-limit data.</sub>

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
