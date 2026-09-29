#!/usr/bin/env python3
"""Render the README polyglot example as a syntax-highlighted SVG.

Reads the first ```t block from README.md so the image always matches the
copy-paste code. Regex tokenizers per runtime (T/Julia/Python/R), GitHub
dark palette. Output: demo-polyglot.svg next to demo.gif.

Re-run after editing the README example:
  nix develop --command python3 scripts/render_polyglot_svg.py
"""
import re
import sys
import xml.etree.ElementTree as ET

REPO = "/home/brodrigues/Documents/repos/tlang"
FG = "#e6edf3"
KW = "#ff7b72"
STR = "#a5d6ff"
NUM = "#79c0ff"
COM = "#8b949e"
FN = "#d2a8ff"
SYM = "#ffa657"
BG = "#0d1117"

KEYWORDS = {
    "t": {"pipeline", "node", "build_pipeline"},
    "julia": {"using", "import", "function", "end", "for", "if", "else",
              "elseif", "return", "let", "struct", "const", "true", "false",
              "nothing", "missing", "while", "try", "catch", "do", "macro"},
    "python": {"from", "import", "as", "def", "return", "for", "in", "if",
               "else", "elif", "while", "with", "None", "True", "False",
               "lambda", "class", "pass", "raise"},
    "r": {"function", "if", "else", "for", "in", "while", "TRUE", "FALSE",
          "NULL", "NA", "next", "break"},
}
CALL = re.compile(r"[A-Za-z_][\w.!?]*")
TOKEN = re.compile(
    r"(?P<str>\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')"
    r"|(?P<num>\b\d[\d_]*(\.\d+)?\b)"
    r"|(?P<word>[A-Za-z_][\w.!?]*)"
    r"|(?P<sym>\^[\w]+|<\{|\}>)"
    r"|(?P<other>.)",
    re.DOTALL,
)


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def colorize(line, lang):
    comment_mark = "--" if lang == "t" else "#"
    # split off trailing comment (first mark outside a string)
    code, comment = line, None
    in_str, q, i = False, "", 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                i += 1
            elif c == q:
                in_str = False
        elif c in "\"'":
            in_str, q = True, c
        elif line.startswith(comment_mark, i):
            code, comment = line[:i], line[i:]
            break
        i += 1
    spans = []
    for m in TOKEN.finditer(code):
        tok = m.group(0)
        kind = m.lastgroup
        if kind == "str":
            cls = STR
        elif kind == "num":
            cls = NUM
        elif kind == "sym":
            cls = SYM
        elif kind == "word":
            rest = code[m.end():]
            if tok in KEYWORDS[lang]:
                cls = KW
            elif re.match(r"\s*\(", rest):
                cls = FN
            else:
                cls = FG
        else:
            cls = FG
        spans.append((tok, cls))
    if comment is not None:
        spans.append((comment, COM))
    return spans


def main():
    text = open(REPO + "/README.md").read()
    m = re.search(r"```t\n(.*?)\n```", text, re.DOTALL)
    lines = m.group(1).split("\n")
    lang, rows, chips = "t", [], {}
    node_lang = {"jln": "julia", "pyn": "python", "rn": "r"}
    pending = None
    for idx, line in enumerate(lines):
        mm = re.search(r"\b(jln|pyn|rn)\(", line)
        if mm:
            pending = node_lang[mm.group(1)]
        if "<{" in line and pending:
            lang = pending
            chips[idx] = pending
        rows.append(colorize(line, lang))
        if "}>" in line and lang != "t":
            lang, pending = "t", None

    fs, lh, pad, adv = 13, 19, 16, 7.9
    width_chars = max(len(l) for l in lines)
    width = int(width_chars * adv + pad * 2 + 90)
    height = len(lines) * lh + pad * 2
    chip_fill = {"julia": "#a371f7", "python": "#79c0ff", "r": "#7ee787"}
    # Background bands around foreign blocks, drawn under the text.
    bands = []
    i = 0
    while i < len(lines):
        if i in chips:
            j = i
            while j < len(lines) and "}>" not in lines[j]:
                j += 1
            end = min(j, len(lines) - 1)
            bands.append((i, end, chips[i]))
            i = end + 1
        else:
            i += 1
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
        f'height="{height}" viewBox="0 0 {width} {height}" role="img">',
        f"<rect width=\"100%\" height=\"100%\" fill=\"{BG}\" rx=\"6\"/>",
    ]
    for start, end, lang in bands:
        y = pad + start * lh - 4
        h = (end - start + 1) * lh + 2
        c = chip_fill[lang]
        out.append(
            f'<rect x="{pad - 8}" y="{y}" width="{width - 2 * (pad - 8)}" '
            f'height="{h}" rx="6" fill="{c}" fill-opacity="0.07" '
            f'stroke="{c}" stroke-opacity="0.45"/>'
        )
    out.append(
        f"<g font-family=\"ui-monospace,SFMono-Regular,Menlo,Consolas,monospace\" "
        f"font-size=\"{fs}\">"
    )
    for idx, (line, spans) in enumerate(zip(lines, rows)):
        y = pad + idx * lh + 14
        parts = "".join(
            f'<tspan fill="{c}">{esc(t)}</tspan>' for t, c in spans
        )
        out.append(f'<text x="{pad}" y="{y}">{parts}</text>')
        if idx in chips:
            label = chips[idx].upper()
            cx = width - pad - 70
            cy = pad + idx * lh + 1
            out.append(
                f'<rect x="{cx}" y="{cy}" width="62" height="15" rx="7.5" '
                f'fill="{chip_fill[chips[idx]]}"/>'
                f'<text x="{cx + 31}" y="{cy + 11.5}" text-anchor="middle" '
                f'font-size="9.5" font-weight="bold" fill="{BG}">{label}</text>'
            )
    out.append("</g></svg>")
    svg = "\n".join(out) + "\n"
    ET.fromstring(svg)  # fail loudly on malformed XML
    open(REPO + "/demo-polyglot.svg", "w").write(svg)
    print(f"wrote {len(lines)} lines, {width}x{height}")


main()
