"""Draw work-docs figures as standalone SVG files: packet and field layouts, byte tables,
before/after grids and version matrices that GitHub shows as images.

A note's own figure script imports this module and places boxes by hand:

    import os, sys
    sys.path.insert(0, os.path.expanduser("~/.claude/skills/worklog/assets"))
    from svgfig import Figure, B, S, M

    fig = Figure(782, 300, "PARAMETER_INFO 요청과 응답", "요청은 그대로이고 응답은 ...")
    fig.text(24, 36, "요청: 바뀌지 않음", 14, "bold")
    fig.box(24, 48, 120, 72, "gray", [B("길이"), S("4바이트"), M("00 00 00 09")])
    fig.save("img/parameter-info-request-response.svg")
    Figure.report()

Colors carry a fixed meaning in every figure: gray unchanged, coral a value that changes,
green something new, red a wrong or old value or a warning, blue a repeated unit, white a
header. Figure.report() lists text that is likely wider than the room given to it.
Runs on Python 3.6 or later.
"""
import os
from xml.sax.saxutils import escape

FONT = "-apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', 'Malgun Gothic', 'Noto Sans KR', 'Segoe UI', sans-serif"
MONO = "SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"
TEXT, MUTED = "#1f2328", "#59636e"
COLORS = {
    "gray": ("#f6f8fa", "#8c959f", TEXT),
    "white": ("#ffffff", "#8c959f", TEXT),
    "blue": ("#ddf4ff", "#0969da", "#0a3069"),
    "coral": ("#fff1e5", "#bc4c00", "#762c00"),
    "green": ("#dafbe1", "#1a7f37", "#044f1e"),
    "red": ("#ffebe9", "#cf222e", "#82071e"),
}
_overflows = []


def B(s):
    """A bold line for Figure.box: the field name."""
    return (s, 13, "bold", False)


def S(s):
    """A small line for Figure.box: the size or a short note."""
    return (s, 12, "normal", False)


def M(s):
    """A monospace line for Figure.box: bytes in hex."""
    return (s, 12.5, "normal", True)


def text_width(s, size, mono=False):
    """Rough rendered width in px: Hangul is about one em, Latin about 0.6 em."""
    if mono:
        return len(s) * size * 0.61
    w = 0.0
    for ch in s:
        if ord(ch) >= 0x1100:
            w += size * 1.0
        elif ch == " ":
            w += size * 0.32
        elif ch.isupper() or ch.isdigit():
            w += size * 0.66
        else:
            w += size * 0.56
    return w


class Figure:
    def __init__(self, width, height, title, desc):
        self.width, self.height, self.title, self.desc = width, height, title, desc
        self.parts = []

    def raw(self, markup):
        self.parts.append(markup)

    def text(self, x, y, s, size=13, weight="normal", anchor="start", color=TEXT, mono=False, limit=None):
        """y is the baseline. limit is the room in px; wider text is reported by Figure.report()."""
        if limit is not None and text_width(s, size, mono) > limit:
            _overflows.append("%r is about %d px, room %d px" % (s, text_width(s, size, mono), limit))
        self.parts.append(
            '<text x="%g" y="%g" font-family="%s" font-size="%g" font-weight="%s" text-anchor="%s" fill="%s">%s</text>'
            % (x, y, MONO if mono else FONT, size, weight, anchor, color, escape(s)))

    def box(self, x, y, w, h, color, lines, rx=5):
        """A rounded box with lines (made with B, S or M) centered in it, top to bottom."""
        fill, stroke, ink = COLORS[color]
        self.parts.append('<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s" stroke="%s" stroke-width="1.2"/>'
                          % (x, y, w, h, rx, fill, stroke))
        gap = 4
        total = sum(line[1] for line in lines) + gap * (len(lines) - 1)
        top = y + (h - total) / 2.0
        for s, size, weight, mono in lines:
            tint = ink if weight == "bold" or mono else MUTED
            self.text(x + w / 2.0, top + size * 0.82, s, size, weight, "middle", tint, mono, w - 8)
            top += size + gap

    def legend(self, y, items):
        """items: (x, color, label). y is the baseline of the labels."""
        for x, color, label in items:
            fill, stroke, _ = COLORS[color]
            self.parts.append('<rect x="%g" y="%g" width="14" height="14" rx="3" fill="%s" stroke="%s"/>'
                              % (x, y - 12, fill, stroke))
            self.text(x + 20, y, label, 13)

    def bracket(self, x1, x2, y, color, label):
        """An underline bracket from x1 to x2 with a bold label below it, to group boxes."""
        stroke = COLORS[color][1]
        self.parts.append('<path d="M%g %g v8 h%g v-8" fill="none" stroke="%s" stroke-width="1.5"/>' % (x1, y, x2 - x1, stroke))
        self.text((x1 + x2) / 2.0, y + 28, label, 13, "bold", "middle", stroke, limit=x2 - x1)

    def column_heads(self, y, columns):
        """columns: (x, w, label, color), the grid that field_row uses."""
        for x, w, label, _ in columns:
            self.text(x + w / 2.0, y, label, 12, "bold", "middle", MUTED, limit=w + 6)

    def field_row(self, y, label, columns, cells, h=36, label_x=24):
        """One packet unit as a row of hex boxes on the column grid, with its label at the left."""
        self.text(label_x, y + 23, label, 13, "bold")
        for (x, w, _, color), cell in zip(columns, cells):
            self.box(x, y, w, h, color, [M(cell)])

    def save(self, path):
        folder = os.path.dirname(path)
        if folder:
            os.makedirs(folder, exist_ok=True)
        doc = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img">'
               '<title>%s</title><desc>%s</desc>'
               '<rect x="0.5" y="0.5" width="%d" height="%d" rx="10" fill="#ffffff" stroke="#d1d9e0"/>%s</svg>\n') % (
            self.width, self.height, self.width, self.height, escape(self.title), escape(self.desc),
            self.width - 1, self.height - 1, "".join(self.parts))
        with open(path, "w", encoding="utf-8") as f:
            f.write(doc)

    @staticmethod
    def report():
        """Print the text that may not fit, and return how many there were."""
        print("\n".join(_overflows) if _overflows else "no text overflow")
        return len(_overflows)
