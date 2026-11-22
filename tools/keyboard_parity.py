# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy==2.3.5", "pillow==11.3.0"]
# ///
"""Measures how well the เว่า keyboard lines up with Apple's, key cap by key cap, from two screenshots.

  uv run tools/keyboard_parity.py APPLE.png WAO.png [--out DIR]     one page
  uv run tools/keyboard_parity.py APPLE_DIR WAO_DIR [--out DIR]     every PNG name found in both folders
  uv run tools/keyboard_parity.py SHOT.png                          lists the caps found in one screenshot

Screenshots are full-screen captures at --scale pixels per point (agent-device `screenshot --pixel-density 3`),
taken in the same host app and text field so the screen positions are comparable. The keyboard panel is the
background-coloured region touching the bottom edge; a cap is any blob of other colours inside it that is the
size of a key. Caps pair up row by row, then by nearest centre. Positions are screen points, so a keyboard that is
taller than Apple's shows up as every cap sitting higher.

Prints, per page, each pair's offset and size difference in points, the same for its label's ink box relative
to the cap (font size, weight and baseline; reported, not gated), the panel top difference (the keyboard
height difference), the worst error with and without that difference and any cap that has no partner. Writes DIR/<page>-overlay.png: Apple's
screenshot and ours blended half and half, Apple's caps outlined green and ours magenta, cropped to the panel.
Exits 1 when any page is off by more than --tolerance points or has unpaired caps.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from collections import deque


@dataclass(frozen=True)
class Cap:
    x: float
    y: float
    w: float
    h: float

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2


@dataclass(frozen=True)
class Keyboard:
    top: float
    caps: list[Cap]
    ink: list[Cap | None]
    """Per cap, the box of its label: pixels far from the cap's own fill, in points relative to the cap."""


def label(img: np.ndarray, cap: Cap, scale: float) -> Cap | None:
    x0, y0 = int(round(cap.x * scale)) + 2, int(round(cap.y * scale)) + 2
    x1, y1 = int(round((cap.x + cap.w) * scale)) - 2, int(round((cap.y + cap.h) * scale)) - 2
    grey = img[y0:y1, x0:x1].mean(axis=2)
    ys, xs = np.nonzero(np.abs(grey - np.median(grey)) > 90)
    if len(ys) == 0:
        return None
    return Cap((xs.min() + x0) / scale - cap.x, (ys.min() + y0) / scale - cap.y,
               (xs.max() - xs.min() + 1) / scale, (ys.max() - ys.min() + 1) / scale)


def load(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def background(img: np.ndarray) -> np.ndarray:
    """The commonest colour of the bottom tenth, which is the panel behind the globe and mic."""
    strip = img[int(img.shape[0] * 0.9):].reshape(-1, 3)
    colours, counts = np.unique(strip, axis=0, return_counts=True)
    return colours[counts.argmax()]


def flood(mask: np.ndarray, seed: tuple[int, int]) -> np.ndarray:
    seen = np.zeros_like(mask)
    todo = deque([seed])
    seen[seed] = True
    h, w = mask.shape
    while todo:
        y, x = todo.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                todo.append((ny, nx))
    return seen


def components(mask: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Bounding boxes (x0, y0, x1, y1), exclusive ends, of the 4-connected blobs in `mask`, row runs merged."""
    h, w = mask.shape
    parent: list[int] = []

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    runs: list[tuple[int, int, int]] = []
    previous: list[int] = []
    for y in range(h):
        row = mask[y]
        edges = np.flatnonzero(np.diff(np.concatenate(([0], row.astype(np.int8), [0]))))
        current: list[int] = []
        for start, end in zip(edges[::2], edges[1::2]):
            i = len(runs)
            runs.append((y, start, end))
            parent.append(i)
            for j in previous:
                _, ps, pe = runs[j]
                if ps < end and start < pe:
                    a, b = find(i), find(j)
                    if a != b:
                        parent[a] = b
            current.append(i)
        previous = current
    boxes: dict[int, list[int]] = {}
    for i, (y, s, e) in enumerate(runs):
        b = boxes.setdefault(find(i), [s, y, e, y + 1])
        b[0], b[1], b[2], b[3] = min(b[0], s), min(b[1], y), max(b[2], e), max(b[3], y + 1)
    return [tuple(b) for b in boxes.values()]


def detect(path: Path, scale: float, threshold: int) -> Keyboard:
    img = load(path)
    bg = background(img)
    distance = np.abs(img - bg).sum(axis=2)
    panel = flood(distance <= threshold, (img.shape[0] - 2, img.shape[1] // 2))
    rows = np.flatnonzero(panel.any(axis=1))
    top = int(rows[0])
    inside = np.zeros_like(panel)
    inside[top:] = True
    caps = []
    for x0, y0, x1, y1 in components((distance > threshold) & inside):
        w, h = (x1 - x0) / scale, (y1 - y0) / scale
        # A blob touching the screen's edge is the panel's rounded corner around the globe or mic, not a cap.
        touches_edge = x0 == 0 or x1 == img.shape[1] or y1 == img.shape[0]
        if 18 <= w <= 330 and 30 <= h <= 70 and y0 > top and not touches_edge:
            caps.append(Cap(x0 / scale, y0 / scale, w, h))
    caps.sort(key=lambda c: (round(c.cy / 10), c.x))
    return Keyboard(top / scale, caps, [label(img, c, scale) for c in caps])


def rows(caps: list[Cap]) -> list[list[Cap]]:
    out: list[list[Cap]] = []
    for cap in sorted(caps, key=lambda c: c.cy):
        if out and abs(out[-1][-1].cy - cap.cy) < 10:
            out[-1].append(cap)
        else:
            out.append([cap])
    return [sorted(r, key=lambda c: c.x) for r in out]


def pair(apple: list[Cap], wao: list[Cap]) -> tuple[list[tuple[int, Cap, Cap]], list[Cap], list[Cap]]:
    """Row i of Apple's with row i of ours, then within a row the closest centres first."""
    pairs, lone_apple, lone_wao = [], [], []
    a_rows, w_rows = rows(apple), rows(wao)
    for r in range(max(len(a_rows), len(w_rows))):
        a_row = a_rows[r] if r < len(a_rows) else []
        w_row = w_rows[r] if r < len(w_rows) else []
        if len(a_row) == len(w_row):
            pairs += [(r, a, w) for a, w in zip(a_row, w_row)]
            continue
        free = list(w_row)
        for a in a_row:
            best = min(free, key=lambda w: abs(w.cx - a.cx), default=None)
            if best is not None and abs(best.cx - a.cx) < min(a.w, best.w) / 2:
                pairs.append((r, a, best))
                free.remove(best)
            else:
                lone_apple.append(a)
        lone_wao += free
    return pairs, lone_apple, lone_wao


def overlay(apple_path: Path, wao_path: Path, apple: Keyboard, wao: Keyboard, scale: float, out: Path) -> None:
    a = Image.open(apple_path).convert("RGB")
    w = Image.open(wao_path).convert("RGB").resize(a.size)
    img = Image.blend(a, w, 0.5)
    draw = ImageDraw.Draw(img)
    for caps, colour in ((apple.caps, (0, 170, 0)), (wao.caps, (220, 0, 200))):
        for c in caps:
            draw.rectangle([c.x * scale, c.y * scale, (c.x + c.w) * scale - 1, (c.y + c.h) * scale - 1], outline=colour, width=2)
    top = int(min(apple.top, wao.top) * scale) - 20
    img.crop((0, max(0, top), img.width, img.height)).save(out)


def fmt(c: Cap) -> str:
    return f"{c.x:6.1f} {c.y:6.1f} {c.w:5.1f} {c.h:5.1f}"


def compare(name: str, apple_path: Path, wao_path: Path, args: argparse.Namespace) -> bool:
    if apple_path.read_bytes() == wao_path.read_bytes():
        print(f"## {name}\nthe two screenshots are the same file; was the system keyboard captured twice?\n")
        return False
    apple = detect(apple_path, args.scale, args.threshold)
    wao = detect(wao_path, args.scale, args.threshold)
    pairs, lone_apple, lone_wao = pair(apple.caps, wao.caps)
    print(f"## {name}")
    print(f"panel top  apple {apple.top:.1f}  wao {wao.top:.1f}  diff {wao.top - apple.top:+.1f} pt")
    print("row  apple x      y     w     h |   wao x      y     w     h |    dx    dy    dw    dh |"
          " label dx    dy    dw    dh")
    worst = worst_label = worst_shape = 0.0
    shift = wao.top - apple.top
    a_ink = dict(zip(apple.caps, apple.ink))
    w_ink = dict(zip(wao.caps, wao.ink))
    for r, a, w in pairs:
        d = (w.x - a.x, w.y - a.y, w.w - a.w, w.h - a.h)
        worst = max(worst, *map(abs, d))
        worst_shape = max(worst_shape, abs(d[0]), abs(d[1] - shift), abs(d[2]), abs(d[3]))
        line = f"{r:3d}  {fmt(a)} | {fmt(w)} | " + " ".join(f"{v:+5.1f}" for v in d)
        ai, wi = a_ink[a], w_ink[w]
        if ai and wi:
            # Label centres relative to their caps, so a label error is not counted twice with a cap error.
            ld = (wi.cx - ai.cx, wi.cy - ai.cy, wi.w - ai.w, wi.h - ai.h)
            worst_label = max(worst_label, *map(abs, ld))
            line += " |     " + " ".join(f"{v:+5.1f}" for v in ld)
        elif ai or wi:
            line += f" |     label only in {'apple' if ai else 'wao'}"
        print(line)
    for c in lone_apple:
        print(f"only apple  {fmt(c)}")
    for c in lone_wao:
        print(f"only wao    {fmt(c)}")
    ok = worst <= args.tolerance and not lone_apple and not lone_wao and abs(wao.top - apple.top) <= args.tolerance
    print(f"worst label offset or size difference {worst_label:.1f} pt (reported, not gated)")
    print(f"worst {worst_shape:.1f} pt once the panel top difference is taken out of dy (reported, not gated)")
    print(f"worst {worst:.1f} pt over {len(pairs)} pairs, unpaired {len(lone_apple)} apple / {len(lone_wao)} wao, "
          f"{'PASS' if ok else 'FAIL'} at {args.tolerance} pt\n")
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        overlay(apple_path, wao_path, apple, wao, args.scale, args.out / f"{name}-overlay.png")
    return ok


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("apple", type=Path)
    p.add_argument("wao", type=Path, nargs="?")
    p.add_argument("--out", type=Path)
    p.add_argument("--scale", type=float, default=3)
    p.add_argument("--threshold", type=int, default=12, help="summed RGB distance from the panel colour")
    p.add_argument("--tolerance", type=float, default=1)
    args = p.parse_args()
    if args.wao is None:
        kb = detect(args.apple, args.scale, args.threshold)
        print(f"panel top {kb.top:.1f}")
        ink = dict(zip(kb.caps, kb.ink))
        for r, row in enumerate(rows(kb.caps)):
            for c in row:
                i = ink[c]
                print(f"{r} {fmt(c)}" + (f"   label {fmt(i)}" if i else ""))
        return 0
    if args.apple.is_dir():
        names = sorted(p.name for p in args.apple.glob("*.png") if (args.wao / p.name).exists())
        if not names:
            sys.exit(f"no PNG name is in both {args.apple} and {args.wao}")
        results = [compare(Path(n).stem, args.apple / n, args.wao / n, args) for n in names]
    else:
        results = [compare(args.wao.stem, args.apple, args.wao, args)]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
