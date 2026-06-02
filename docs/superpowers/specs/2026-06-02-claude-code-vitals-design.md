# ClaudeCodeVitals — Design Spec

**Date:** 2026-06-02
**Status:** Approved design, pending implementation plan
**Repo:** `claude-code-vitals`

## Summary

A custom status line for Claude Code that renders model, git, context, rate
limits, effort, extra usage, and session cost as a single compact, colorful
line with progress bars. It is a fresh, Linux-only Bash rewrite **inspired by**
[daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine)
(MIT), built to fix that project's shortcomings and add developer-focused
information.

This is a **new, independent repository**. It does not modify the user's
existing `~/.claude` configuration or the original clone — it is a proposal to
test side-by-side, not a replacement of the current setup.

## Motivation (what's wrong with the original)

Found by testing the original `statusline.sh` with sample input on this machine:

1. **Locale bug.** Lines 401 & 411 call `printf "%.0f" "42.5"` without forcing
   `LC_NUMERIC=C`. On a French (`fr_FR`) locale the decimal separator is `,`, so
   C-style `printf` rejects `42.5` and emits `printf: 42.5: nombre non valable`
   to stderr on every render. The author knew the fix (`render_extra_usage` uses
   `LC_NUMERIC=C awk`) but missed these two sites.
2. **No progress bars.** The file's own header comment promises `5h bar` /
   `7d bar`, but only percentages are rendered — the visual intent was dropped.
3. **Performance.** ~20 separate `echo "$input" | jq` invocations, each spawning
   a `jq` subprocess, where a single `jq` pass would suffice.
4. **Aesthetics.** Flat, pipe-delimited, no progress bars, ambiguous lowercase
   `1m` for the context window.
5. **Maintenance.** `statusline.sh` and `statusline.ps1` are hand-synced
   duplicates that can drift.

## Goals

- A more beautiful, glanceable status line with real progress bars.
- Correct on European locales.
- Faster (single `jq` pass).
- Easy to restyle (config header).
- Developer-focused extras: context-pressure warning, model-aware accent,
  session cost.

## Non-goals (YAGNI)

- Windows / macOS support (Linux only; can be added later).
- GitHub update-check / self-update mechanism (removed — one fewer network call).
- Clock, CLI-version segment, active-toolchain (venv/node), git stash/untracked
  counts. Considered and dropped.

## Constraints

- **Platform:** Linux only.
- **Language:** single Bash script (`statusline.sh`). No PowerShell twin.
- **Dependencies:** `jq`, `curl`, `git`, GNU coreutils (`date`, `stat`) — all
  already present on the target machine.
- **No special font:** every glyph must render in a standard terminal (no Nerd
  Font / powerline glyphs).
- Must not modify the user's `~/.claude/settings.json` or the original clone.

## Visual design

### Style
Refined Unicode, no special font. Segments separated by a dim middle dot
` · `. Color applied to values and labels; thresholds drive bar/percent color.

### Segment line (left to right)
```
model · dir@branch[*][↑n ↓n][+N -M] · ctx BAR % tokens[⚠] · effort · 5h BAR % @reset · 7d BAR % @reset · extra $u/$l · $cost
```

### Segments
| Segment | Content | Notes |
|---------|---------|-------|
| **model** | e.g. `Opus 4.8 1M` | Accent color by family: Opus→purple, Sonnet→blue, Haiku→cyan. Uppercase `1M` (not `1m`). |
| **git** | `dir@branch` + `*` dirty + `↑n ↓n` ahead/behind upstream + `+N -M` line stat | Folder name = basename of cwd. Branch green, dirty marker yellow, ahead/behind cyan, additions green / deletions red. Omitted when cwd is not a git repo. |
| **ctx** | 3-cell bar + `%` + `used/total` tokens | Context window usage. Turns **red + appends `⚠`** at >90% (context-pressure warning). |
| **effort** | `low`/`med`/`high`/`xhigh`/`max` | Color-coded: low dim, med orange, high green, xhigh purple, max red. |
| **5h** | 3-cell bar + `%` + `@HH:MM` reset | 5-hour rate limit. |
| **7d** | 3-cell bar + `%` + `@Day Mon D` reset | 7-day rate limit. |
| **extra** | `$used/$limit` | Only when `extra_usage.is_enabled` is true. |
| **cost** | `$X.XX` | Session cost. Prefer `.cost.total_cost_usd` from input JSON; fall back to token×price estimate only if absent. |

### Progress bars
- **Width:** 3 cells.
- **Glyphs:** plain `▰` (filled) / `▱` (empty). Swappable via config (e.g. `█`/`░`).
- **Rounding:** nearest cell, with a **min-1-cell rule** — any usage `> 0`
  shows at least one filled cell (so low-but-nonzero never looks like zero).
- **Color by threshold:** green `<50%`, yellow `≥50%`, orange `≥70%`, red `≥90%`.

### Palette (config header, RGB truecolor)
Reuse the original's pleasant palette: blue, orange, green, cyan, red, yellow,
purple, white, dim, reset. Exact values live in the config header and are the
single source of truth for restyling.

## Architecture

Single file, structured as:

```
CONFIG header        # palette, bar glyphs, bar width, separator, per-segment
                     # on/off toggles, model-family accent map, price table
  ↓
parse_input()        # ONE jq call → emits key=value lines → eval into shell vars
  ↓
helpers              # format_tokens(), usage_color(), make_bar(),
                     # iso_to_epoch(), format_reset_time(), get_oauth_token()
  ↓
seg_model() seg_git() seg_context() seg_effort()
seg_limits() seg_extra() seg_cost()   # each appends to the line if enabled
  ↓
render()             # joins enabled segments with the separator, prints
```

- **Per-segment toggles:** config-header booleans; `render()` skips disabled
  segments. (Lightweight version of config-driven; not a full data-array loop.)
- All numeric `printf`/`awk` use `LC_NUMERIC=C` to avoid the locale bug.

## Data sourcing

Reuse the original's proven strategy (minus the GitHub update check):

1. **Rate limits:** prefer `.rate_limits.*` from stdin JSON (no auth needed).
2. **Fallback to OAuth usage API** (`api.anthropic.com/api/oauth/usage`) — needed
   anyway for `extra_usage`, which is not in stdin. Token resolved via
   `CLAUDE_CODE_OAUTH_TOKEN` env → Linux `~/.claude/.credentials.json` →
   GNOME Keyring (`secret-tool`).
3. **Cache:** 60s TTL at `/tmp/claude/`, shared across instances, stampede-locked
   via `touch` before fetch.
4. **Session cost:** prefer `.cost.total_cost_usd` from stdin; else estimate.

`curl --max-time 10`, network call only when cache is stale.

## Error handling

- Empty stdin → print `Claude`, exit 0.
- Missing JSON fields → `jq` `// default` operators, never crash.
- API failure / invalid response → fall back to cache → fall back to `-`
  placeholder for the affected segment.
- Stale stampede sentinel removed if a fetch produced no valid JSON, so retries
  aren't suppressed for a full cache window.
- The script must never break the shell prompt; always exits 0.

## Repository layout

```
claude-code-vitals/
├── statusline.sh                 # the tool
├── README.md                     # with SEO keywords: "Claude Code statusline"
├── LICENSE                       # MIT, credits daniel3303/ClaudeCodeStatusLine
├── .gitignore
├── docs/superpowers/specs/2026-06-02-claude-code-vitals-design.md
└── samples/
    ├── run.sh                    # pipes each fixture through statusline.sh
    ├── low-usage.json            # fresh session, low usage
    ├── high-usage.json           # heavy usage, dirty repo, extra enabled, >90% ctx
    ├── no-git.json               # cwd not a git repo
    └── no-limits.json            # stdin missing rate_limits (cache/API fallback)
```

## Testing / critique loop

`samples/run.sh` renders every fixture through `statusline.sh` so all visual
states can be eyeballed without live Claude data — and compared side-by-side
with the original. This doubles as the manual test harness for the rewrite.
`STATUSLINE_CHECK_UPDATES` is not needed (no update check exists).

## Installation (documented, not auto-applied)

README will document how to point `~/.claude/settings.json` at this script, but
installation is left to the user — the design explicitly does **not** modify the
current configuration.

## Attribution

MIT licensed. README and LICENSE credit
[daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine)
as the inspiration. Code is an independent rewrite, not a copy.
