# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy==2.3.5", "pillow==11.3.0"]
# ///
"""Measures an emoji keyboard page, Apple's or เว่า's, from a full-screen screenshot.

  uv run tools/emoji_metrics.py SHOT.png [SHOT.png ...] [--scale 3]

Screenshots as for keyboard_parity.py (agent-device `screenshot --pixel-density 3`), showing a page whose first
column is plain round faces (Smileys & People), so every glyph in it has the same ink box. Prints, in points:
the panel's top and its height above the screen's bottom edge; any band between the panel top and the section
header (Apple's search field); the header's ink; the glyph rows and columns (ink boxes, centre pitch); and the
category bar's ink. Positions are screen points, so two screenshots compare directly.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from keyboard_parity import background, flood, load


def runs(flags: np.ndarray, offset: int, min_len: int) -> list[tuple[int, int]]:
    edges = np.flatnonzero(np.diff(np.concatenate(([0], flags.astype(np.int8), [0]))))
    return [(s + offset, e + offset) for s, e in zip(edges[::2], edges[1::2]) if e - s >= min_len]


def measure(path: Path, scale: float, threshold: int) -> None:
    img = load(path)
    h, w = img.shape[:2]
    bg = background(img)
    distance = np.abs(img - bg).sum(axis=2)
    panel = flood(distance <= threshold, (h - 2, w // 2))
    top = int(np.flatnonzero(panel.any(axis=1))[0])
    pt = lambda v: v / scale  # noqa: E731
    print(f"{path.name}: {pt(w):.0f} x {pt(h):.0f} pt")
    print(f"  panel top {pt(top):.2f}, {pt(h - top):.2f} above the screen bottom")

    colour = (img.max(axis=2) - img.min(axis=2)) > 100
    colour[:top] = False
    colour[int(h - 70 * scale):] = False
    last = runs(colour.sum(axis=1) > 2, 0, int(20 * scale))[-1]
    col_runs = runs(colour[last[0]:last[1]].sum(axis=0) > 2, 0, int(20 * scale))
    c0 = col_runs[0]
    rows = runs(colour[:, c0[0]:c0[1]].sum(axis=1) > 2, 0, int(20 * scale))[-5:]
    cols = col_runs
    centre = lambda r: pt((r[0] + r[1]) / 2)  # noqa: E731
    print("  glyph rows   " + "  ".join(f"{pt(a):.2f}-{pt(b):.2f}" for a, b in rows))
    print(f"    centres {[round(float(centre(r)), 2) for r in rows]}, pitch {np.diff([centre(r) for r in rows]).round(2).tolist()}")
    print(f"    glyph ink {pt(rows[0][1] - rows[0][0]):.2f} tall, {pt(c0[1] - c0[0]):.2f} wide")
    print(f"  glyph columns, centres {[round(float(centre(c)), 2) for c in cols]}")
    print(f"    pitch {np.diff([centre(c) for c in cols]).round(2).tolist()}")

    # Grey ink above the grid, left half: the header; anything between it and the panel top is a band.
    above = distance[top:rows[0][0], : w // 2] > 60
    ink = runs(above.sum(axis=1) > 2, top, int(4 * scale))
    header = ink[-1] if ink else None
    if header:
        print(f"  header ink {pt(header[0]):.2f}-{pt(header[1]):.2f} ({pt(header[1] - header[0]):.2f} tall), "
              f"{pt(rows[0][0] - header[1]):.2f} above the first glyph row")
        mid = distance[top:header[0], w // 2]
        band = runs(mid > threshold, top, int(10 * scale))
        for a, b in band:
            print(f"  band {pt(a):.2f}-{pt(b):.2f} ({pt(b - a):.2f} tall), {pt(a - top):.2f} below the panel top")
        if not band:
            print(f"  no band; header ink starts {pt(header[0] - top):.2f} below the panel top")

    bar_zone = distance[rows[-1][1] + int(2 * scale): int(h - 70 * scale)] > 150
    bar = runs(bar_zone.sum(axis=1) > 2, rows[-1][1] + int(2 * scale), 1)
    if bar:
        a, b = bar[0][0], bar[-1][1]
        print(f"  bar ink {pt(a):.2f}-{pt(b):.2f}, centre {pt((a + b) / 2):.2f}, "
              f"{pt(h - (a + b) / 2):.2f} above the screen bottom, {pt(a - rows[-1][1]):.2f} below the last glyph row")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("shots", type=Path, nargs="+")
    p.add_argument("--scale", type=float, default=3)
    p.add_argument("--threshold", type=int, default=12, help="summed RGB distance from the panel colour")
    args = p.parse_args()
    for shot in args.shots:
        measure(shot, args.scale, args.threshold)


if __name__ == "__main__":
    main()
