"""Render house-style charts and flow diagrams to PNG for the report .docx.

Used by build_report.py for {"t":"chart"} and {"t":"diagram"} blocks.
Design matches the team's hand-made charts: bold navy titles + value labels,
no axes/grid, a rich semantic palette, gently rounded bars, optional pill
badge / note / footer. Korean via a bold-capable CJK font (Apple SD Gothic Neo).
"""
import collections
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

for _c in ("Apple SD Gothic Neo", "NanumGothic", "Malgun Gothic", "Noto Sans KR",
           "Noto Sans CJK KR", "AppleGothic"):
    if _c in {f.name for f in fm.fontManager.ttflist}:
        plt.rcParams["font.family"] = _c
        break
plt.rcParams["axes.unicode_minus"] = False

NAVY = "#1F3864"
SUB = "#8C8C8C"
DARK = "#3A3A3A"
GRAY = "#595959"
PAL = {"base": "#95A3A8", "gray": "#95A3A8", "blue": "#2E6DA4",
       "good": "#2EA84F", "green": "#2EA84F", "lightgreen": "#A9D5A9",
       "warn": "#E8862E", "orange": "#E8862E", "bad": "#C0392B", "red": "#C0392B"}
PALETTE = ["#2E6DA4", "#E8862E", "#2EA84F", "#0F9ED5", "#A02B93", "#95A3A8"]


def _fmt(v, signed):
    if signed:
        return f"+{v:,}" if v >= 0 else f"{v:,}"
    return f"{v:,}"


def _text_w_in(s, size_pt):
    """Rough rendered width of a string in inches (CJK ~1em, Latin ~0.58em)."""
    return sum((1.0 if ord(c) > 0x2000 else 0.58) * size_pt for c in str(s)) / 72.0


def _titles(fig, b):
    """Title + subtitle, centered over the whole figure; inch-based offsets (height-independent)."""
    fh = fig.get_size_inches()[1]
    title, sub = b.get("title"), b.get("subtitle")
    if title:
        fig.text(0.5, 1 - 0.30 / fh, title, ha="center", va="top", fontsize=16, color=NAVY, fontweight="bold")
    if sub:
        fig.text(0.5, 1 - (0.62 if title else 0.30) / fh, sub, ha="center", va="top", fontsize=11.5, color=SUB)


def _footer(fig, b):
    if b.get("note"):
        fh = fig.get_size_inches()[1]
        fig.text(0.5, 0.16 / fh, b["note"], ha="center", va="bottom", fontsize=9.5, color=SUB)


def _round_bars(ax, fig, radius_in=0.05):
    """Replace rectangular bars with very slightly rounded ones (uniform corner
    radius in inches, regardless of axis scale)."""
    x0, x1 = ax.get_xlim(); y0, y1 = ax.get_ylim()
    box = ax.get_position()
    fw, fh = fig.get_size_inches()
    x_per_in = (x1 - x0) / (box.width * fw)
    y_per_in = (y1 - y0) / (box.height * fh)
    if x_per_in <= 0 or y_per_in <= 0:
        return
    rs = radius_in * x_per_in            # rounding_size in x-data units
    mut = y_per_in / x_per_in            # circular corners despite scale
    for p in list(ax.patches):
        bb = p.get_bbox()
        fc = p.get_facecolor()
        p.set_visible(False)
        ax.add_patch(FancyBboxPatch((bb.x0, bb.y0), bb.width, bb.height,
                     boxstyle=f"round,pad=0,rounding_size={rs}", mutation_aspect=mut,
                     fc=fc, ec="none", zorder=3, clip_on=False))


def render_clean_bars(b, path):
    """Vertical bars: per-bar color, bold navy value labels, pill `badge`/`note`,
    subtle baseline, gently rounded. bars:[{label,value,color,badge,note}]"""
    bars = b.get("bars", [])
    labels = [x["label"] for x in bars]
    values = [x["value"] for x in bars]
    colors = [PAL.get(x.get("color", "base"), PAL["base"]) for x in bars]
    xs = list(range(len(bars)))
    signed = b.get("signed", False)
    fig, ax = plt.subplots(figsize=(b.get("width_in", 6.8), b.get("height_in", 4.6)), dpi=150)
    fig.subplots_adjust(left=0.07, right=0.95, top=0.84, bottom=0.13)
    ax.bar(xs, values, width=0.6, color=colors, zorder=3)
    vmax = max(values) if values else 1
    ax.set_xlim(-0.6, len(bars) - 0.4)
    ax.set_ylim(0, vmax * 1.5)
    _round_bars(ax, fig)
    annot_y = vmax * 1.14
    for xi, v in zip(xs, values):
        ax.text(xi, v + vmax * 0.02, _fmt(v, signed), ha="center", va="bottom",
                fontsize=19, color=NAVY, fontweight="bold")
    for xi, bar in zip(xs, bars):
        if bar.get("badge"):
            ax.annotate(bar["badge"], xy=(xi, annot_y), ha="center", va="center",
                        fontsize=11.5, color="white", fontweight="bold", linespacing=1.5,
                        bbox=dict(boxstyle="round,pad=0.6",
                                  fc=PAL.get(bar.get("color", "good"), PAL["good"]), ec="none"))
        elif bar.get("note"):
            ax.text(xi, annot_y, bar["note"], ha="center", va="center", fontsize=10,
                    color=PAL.get(bar.get("color", "warn"), PAL["warn"]), fontweight="bold")
    ax.set_xticks(xs)
    ax.set_xticklabels(labels, fontsize=12, color=DARK)
    ax.set_yticks([])
    ax.tick_params(length=0)
    for k, sp in ax.spines.items():
        sp.set_visible(k == "bottom")
    ax.spines["bottom"].set_color("#E3E3E3")
    ax.spines["bottom"].set_linewidth(1.0)
    _titles(fig, b)
    _footer(fig, b)
    fig.savefig(path, facecolor="white")
    plt.close(fig)


def render_hbar(b, path):
    """Horizontal ranked bars: left label (+ optional colored `tag`), proportional
    rounded bar, bold navy value at the end. bars:[{label,value,color,tag,tag_color}]"""
    items = b.get("bars", [])
    n = len(items)
    values = [x["value"] for x in items]
    vmax = max(values + [1])
    colors = [PAL.get(x.get("color", "good"), PAL["good"]) for x in items]
    signed = b.get("signed", True)
    label_w = max([_text_w_in(it.get("label", ""), 13) for it in items] + [0.6])
    tag_w = max([_text_w_in(it.get("tag", ""), 10) for it in items] + [0.0])
    left_in = max(label_w, tag_w) + 0.3                 # left margin auto-sized to the longest label
    plot_in = b.get("plot_in", 5.2)
    fig_w = left_in + plot_in
    fig_h = b.get("height_in", 0.95 * n + 1.9)
    fig, ax = plt.subplots(figsize=(fig_w, fig_h), dpi=150)
    fig.subplots_adjust(left=left_in / fig_w, right=0.97,
                        top=1 - 0.80 / fig_h, bottom=(0.5 if b.get("note") else 0.2) / fig_h)
    ys = list(range(n))[::-1]
    ax.barh(ys, values, height=0.5, color=colors, zorder=3)
    ax.set_xlim(0, vmax * 1.16)
    ax.set_ylim(-0.6, n - 0.4)
    _round_bars(ax, fig)
    for y, it in zip(ys, items):
        v = it["value"]
        ax.text(v + vmax * 0.02, y, _fmt(v, signed), va="center", ha="left",
                fontsize=18, color=NAVY, fontweight="bold")
        tag = it.get("tag")
        ax.text(-vmax * 0.03, y + (0.16 if tag else 0), it["label"], va="center", ha="right",
                fontsize=13, color=DARK, clip_on=False)
        if tag:
            ax.text(-vmax * 0.03, y - 0.22, tag, va="center", ha="right", fontsize=10,
                    color=PAL.get(it.get("tag_color", "good"), PAL["good"]),
                    fontweight="bold", clip_on=False)
    ax.set_yticks([])
    ax.set_xticks([])
    ax.tick_params(length=0)
    for sp in ax.spines.values():
        sp.set_visible(False)
    _titles(fig, b)
    _footer(fig, b)
    fig.savefig(path, facecolor="white")
    plt.close(fig)


def render_chart(b, path):
    """Route by kind. `bars` → vertical (bar) or horizontal (hbar). `series` → line/pie."""
    kind = b.get("kind", "bar")
    if "bars" in b:
        return render_hbar(b, path) if kind == "hbar" else render_clean_bars(b, path)
    labels = b.get("labels", [])
    series = b.get("series", [])
    fig, ax = plt.subplots(figsize=(b.get("width_in", 6.5), b.get("height_in", 3.6)), dpi=150)
    fig.subplots_adjust(left=0.1, right=0.95, top=0.84, bottom=0.14)
    if kind == "pie":
        data = series[0]["data"] if series else []
        ax.pie(data, labels=labels, autopct="%1.0f%%", colors=PALETTE, startangle=90,
               textprops={"fontsize": 10})
        ax.axis("equal")
    else:
        for i, s in enumerate(series):
            ax.plot(labels, s["data"], marker="o", linewidth=2,
                    color=PALETTE[i % len(PALETTE)], label=s.get("name"))
        ax.grid(axis="y", alpha=0.25)
        for sp in ("top", "right"):
            ax.spines[sp].set_visible(False)
        if any(s.get("name") for s in series):
            ax.legend()
    _titles(fig, b)
    _footer(fig, b)
    fig.savefig(path, facecolor="white")
    plt.close(fig)


def render_diagram(b, path):
    """Layered flow diagram (nodes + edges); longest-path layering, boxes + arrows."""
    nodes = b.get("nodes", [])
    edges = b.get("edges", [])
    direction = b.get("direction", "LR")
    ids = [n["id"] for n in nodes]
    label = {n["id"]: n.get("label", n["id"]) for n in nodes}
    adj = {i: [] for i in ids}
    indeg = {i: 0 for i in ids}
    for e in edges:
        if e["from"] in adj and e["to"] in indeg:
            adj[e["from"]].append(e["to"]); indeg[e["to"]] += 1
    depth = {i: 0 for i in ids}
    q = collections.deque([i for i in ids if indeg[i] == 0])
    ind = dict(indeg)
    while q:
        u = q.popleft()
        for v in adj[u]:
            depth[v] = max(depth[v], depth[u] + 1)
            ind[v] -= 1
            if ind[v] == 0:
                q.append(v)
    layers = collections.defaultdict(list)
    for i in ids:
        layers[depth[i]].append(i)
    STEPX, STEPY = 3.6, 1.8
    bw, bh = 2.8, 1.0
    pos = {}
    for d, members in layers.items():
        for j, nid in enumerate(members):
            off = j - (len(members) - 1) / 2
            pos[nid] = (off * STEPX, -d * STEPY) if direction == "TB" else (d * STEPX, -off * STEPY)
    xs = [p[0] for p in pos.values()] or [0]
    ys = [p[1] for p in pos.values()] or [0]
    x0, x1 = min(xs) - bw / 2 - 0.5, max(xs) + bw / 2 + 0.5
    y0, y1 = min(ys) - bh / 2 - 0.5, max(ys) + bh / 2 + 0.5
    DATA_PER_IN = 1.8                              # equal aspect: box fits its text regardless of node count
    fig, ax = plt.subplots(figsize=((x1 - x0) / DATA_PER_IN, (y1 - y0) / DATA_PER_IN), dpi=150)
    ax.set_xlim(x0, x1); ax.set_ylim(y0, y1); ax.set_aspect("equal"); ax.axis("off")

    def edge_pt(c, t):                             # point where the c→t line exits c's box (clean arrows)
        cx, cy = c; tx, ty = t
        dx, dy = tx - cx, ty - cy
        if not dx and not dy:
            return c
        s = min((bw / 2) / abs(dx) if dx else 1e9, (bh / 2) / abs(dy) if dy else 1e9)
        return (cx + dx * s, cy + dy * s)

    for e in edges:
        if e["from"] not in pos or e["to"] not in pos:
            continue
        p1 = edge_pt(pos[e["from"]], pos[e["to"]])
        p2 = edge_pt(pos[e["to"]], pos[e["from"]])
        ax.add_patch(FancyArrowPatch(p1, p2, arrowstyle="-|>", mutation_scale=13, color=GRAY, lw=1.4))
        if e.get("label"):
            ax.text((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2, e["label"], fontsize=8, color=GRAY,
                    ha="center", va="center", bbox=dict(fc="white", ec="none", pad=0.3))
    for nid, (x, y) in pos.items():
        ax.add_patch(FancyBboxPatch((x - bw / 2, y - bh / 2), bw, bh,
                     boxstyle="round,pad=0.02,rounding_size=0.10", fc="#D5E8F0", ec="#156082", lw=1.3, zorder=3))
        ax.text(x, y, label[nid], ha="center", va="center", fontsize=9.5, color=NAVY, zorder=4)
    fig.savefig(path, bbox_inches="tight", facecolor="white")
    plt.close(fig)


if __name__ == "__main__":          # CLI for the docx-js generator: figures.py <block.json> <out.png>
    import sys
    import json as _json
    with open(sys.argv[1], encoding="utf-8") as _f:
        _spec = _json.load(_f)
    _out = sys.argv[2]
    (render_diagram if _spec.get("t") == "diagram" else render_chart)(_spec, _out)
    print("ok")
