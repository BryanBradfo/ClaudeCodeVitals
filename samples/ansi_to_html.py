#!/usr/bin/env python3
"""Render the statusline sample output as a styled HTML terminal card.

Reads ANSI-colored text on stdin (truecolor fg `38;2;r;g;b`, dim `2`, reset
`0`) and emits a self-contained HTML page for screenshotting.
"""
import html
import re
import sys

ESC = re.compile(r"\x1b\[([0-9;]*)m")

ROWS = [
    ("high usage", "context near limit, weekly cap hot"),
    ("low usage", "fresh session, everything green"),
    ("no git / Haiku", "outside a repo, cheap model"),
    ("no limits / Sonnet", "API key, no rate-limit data"),
]


def line_to_html(line: str) -> str:
    out, fg, dim, open_span = [], None, False, False

    def close():
        nonlocal open_span
        if open_span:
            out.append("</span>")
            open_span = False

    def opn():
        nonlocal open_span
        styles = []
        if fg:
            styles.append(f"color:{fg}")
        if dim:
            styles.append("opacity:.5")
        out.append(f'<span style="{";".join(styles)}">' if styles else "<span>")
        open_span = True

    pos = 0
    for m in ESC.finditer(line):
        if m.start() > pos:
            if not open_span:
                opn()
            out.append(html.escape(line[pos:m.start()]))
        codes = [c for c in m.group(1).split(";") if c != ""] or ["0"]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == "0":
                close(); fg, dim = None, False
            elif c == "2":
                close(); dim = True
            elif c == "38" and codes[i+1:i+2] == ["2"]:
                close(); r, g, b = codes[i+2:i+5]; fg = f"rgb({r},{g},{b})"; i += 4
            i += 1
        pos = m.end()
    if pos < len(line):
        if not open_span:
            opn()
        out.append(html.escape(line[pos:]))
    close()
    return "".join(out)


def main() -> None:
    raw = [l for l in sys.stdin.read().splitlines()
           if l.strip() and not l.startswith("─")]
    cells = []
    for idx, line in enumerate(raw):
        label, hint = ROWS[idx] if idx < len(ROWS) else (f"case {idx+1}", "")
        cells.append(
            f'<div class="row"><div class="meta"><span class="tag">{html.escape(label)}</span>'
            f'<span class="hint">{html.escape(hint)}</span></div>'
            f'<div class="bar">{line_to_html(line)}</div></div>'
        )
    body = "\n".join(cells)
    print(f"""<!doctype html><html><head><meta charset="utf-8"><style>
  *{{margin:0;box-sizing:border-box}}
  body{{background:#0d1117;padding:40px;font-family:'DejaVu Sans Mono','Cascadia Code',monospace}}
  .card{{background:#161b22;border:1px solid #30363d;border-radius:12px;
    overflow:hidden;box-shadow:0 24px 60px rgba(0,0,0,.5);width:max-content}}
  .titlebar{{display:flex;align-items:center;gap:8px;padding:12px 16px;background:#1c2128;border-bottom:1px solid #30363d}}
  .dot{{width:12px;height:12px;border-radius:50%}}
  .r{{background:#ff5f56}} .y{{background:#ffbd2e}} .g{{background:#27c93f}}
  .title{{margin-left:10px;color:#8b949e;font-size:13px;letter-spacing:.3px}}
  .rows{{padding:22px 26px;display:flex;flex-direction:column;gap:20px}}
  .meta{{display:flex;align-items:baseline;gap:10px;margin-bottom:7px}}
  .tag{{color:#58a6ff;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px}}
  .hint{{color:#6e7681;font-size:12px}}
  .bar{{color:#dcdcdc;font-size:16px;line-height:1.5;white-space:nowrap}}
</style></head><body>
  <div class="card">
    <div class="titlebar">
      <span class="dot r"></span><span class="dot y"></span><span class="dot g"></span>
      <span class="title">ClaudeCodeVitals — statusline</span>
    </div>
    <div class="rows">
{body}
    </div>
  </div>
</body></html>""")


if __name__ == "__main__":
    main()
