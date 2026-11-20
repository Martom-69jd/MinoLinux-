#!/usr/bin/env python3
"""png2ansi.py: turn a picture into a colour terminal logo for fastfetch, neofetch and screenfetch.

  python3 tools/png2ansi.py my.png overlay/airootfs/usr/share/mino/logo.ansi \\
      --screenfetch overlay/airootfs/usr/share/mino/logo.screenfetch

One terminal cell shows two vertically stacked pixels (half blocks, 24-bit colour), so a 40x40 pixel
picture becomes 40 columns x 20 rows. Needs Pillow and numpy (pip install pillow numpy).

Options:
  --width N        logo width in columns (default 40)
  --frame N        pixels of a border to cut off all four sides first (default 0)
  --bg auto|R,G,B|none
                   background to make transparent by flood fill from the corners (default auto = the most
                   common corner colour after --frame; 'none' keeps the picture as is)
  --colors N       reduce to the N most common distinct colours (default 7; 0 = no reduction)
  --screenfetch P  also write a screenfetch art script to P
  --name TEXT      OS name shown by screenfetch (default "MinoLinux (Arch-based)")

Downscaling takes the most common colour of each block (thin dark outlines are given extra weight),
which keeps flat illustrations crisp instead of blurring them.
"""
import argparse
from collections import Counter, deque

import numpy as np
from PIL import Image


def flood_background(a, bg, tol=24):
    h, w = a.shape[:2]
    close = np.abs(a.astype(int) - np.array(bg)).sum(2) <= tol
    mask = np.zeros((h, w), bool)
    dq = deque()
    for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if close[p[1], p[0]]:
            mask[p[1], p[0]] = True
            dq.append(p)
    while dq:
        x, y = dq.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not mask[ny, nx] and close[ny, nx]:
                mask[ny, nx] = True
                dq.append((nx, ny))
    return mask


def top_colors(rgb, alpha, n, min_dist=30):
    cnt = Counter(map(tuple, rgb[alpha > 127].reshape(-1, 3).tolist()))
    pal = []
    for col, _ in cnt.most_common():
        if all(sum((a - b) ** 2 for a, b in zip(col, p)) ** 0.5 > min_dist for p in pal):
            pal.append(col)
        if len(pal) == n:
            break
    return np.array(pal, float)


def main():
    ap = argparse.ArgumentParser(description="picture -> terminal logo")
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--width", type=int, default=40)
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--bg", default="auto")
    ap.add_argument("--colors", type=int, default=7)
    ap.add_argument("--screenfetch")
    ap.add_argument("--name", default="MinoLinux (Arch-based)")
    a = ap.parse_args()

    im = Image.open(a.src).convert("RGBA")
    if a.frame:
        im = im.crop((a.frame, a.frame, im.width - a.frame, im.height - a.frame))
    arr = np.array(im)
    rgb, alpha = arr[..., :3].copy(), arr[..., 3].copy()
    if a.bg != "none":
        if a.bg == "auto":
            corners = [tuple(rgb[y, x]) for y in (0, -1) for x in (0, -1)]
            bg = Counter(corners).most_common(1)[0][0]
        else:
            bg = tuple(int(v) for v in a.bg.split(","))
        alpha[flood_background(rgb, bg)] = 0
    ys, xs = np.where(alpha > 127)
    if len(xs) == 0:
        raise SystemExit("nothing left after background removal")
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    rgb, alpha = rgb[y0:y1, x0:x1], alpha[y0:y1, x0:x1]

    src_h, src_w = alpha.shape
    n_w = a.width
    n_h = max(2, round(src_h * n_w / src_w))
    n_h += n_h % 2                                   # even number of pixel rows
    pal = top_colors(rgb, alpha, a.colors) if a.colors else None
    darkest = tuple(int(v) for v in pal[np.argmin(pal.sum(1))]) if pal is not None else None

    def snap(c):
        if pal is None:
            return tuple(int(v) for v in c)
        return tuple(int(v) for v in pal[np.argmin(((pal - c) ** 2).sum(1))])

    ex = np.linspace(0, src_w, n_w + 1).round().astype(int)
    ey = np.linspace(0, src_h, n_h + 1).round().astype(int)
    grid = [[None] * n_w for _ in range(n_h)]
    for j in range(n_h):
        for i in range(n_w):
            bl_a = alpha[ey[j]:max(ey[j + 1], ey[j] + 1), ex[i]:max(ex[i + 1], ex[i] + 1)]
            if (bl_a > 127).mean() < 0.5:
                continue
            bl_c = rgb[ey[j]:ey[j] + bl_a.shape[0], ex[i]:ex[i] + bl_a.shape[1]]
            votes = Counter()
            for p, al in zip(bl_c.reshape(-1, 3), bl_a.reshape(-1)):
                if al > 127:
                    c = snap(p)
                    votes[c] += 1.6 if c == darkest else 1
            grid[j][i] = max(votes, key=votes.get)

    rows = []
    for y in range(0, n_h, 2):
        st, line = (None, None), ""
        for x in range(n_w):
            t, b = grid[y][x], grid[y + 1][x]
            if t and b:
                ch, fg, bg_ = "\u2580", t, b
            elif t:
                ch, fg, bg_ = "\u2580", t, None
            elif b:
                ch, fg, bg_ = "\u2584", b, None
            else:
                ch, fg, bg_ = " ", st[0], None
            params = []
            if fg != st[0]:
                params.append("38;2;%d;%d;%d" % fg)
            if bg_ != st[1]:
                params.append("49" if bg_ is None else "48;2;%d;%d;%d" % bg_)
            if params:
                line += "\x1b[" + ";".join(params) + "m"
            line += ch
            st = (fg, bg_)
        rows.append(line + "\x1b[0m")
    with open(a.dst, "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")

    if a.screenfetch:
        gap = 2
        out = [
            "# MinoLinux logo for screenfetch:  screenfetch -a /usr/share/mino/logo.screenfetch",
            "# Generated by tools/png2ansi.py; each line = one logo row + \"%s\" (the info column).",
            'startline="0"',
            f'distro_more="{a.name}"',
            f'logowidth="{n_w + gap}"',
            "fulloutput=(",
        ]
        for i, r in enumerate(rows):
            out.append('"' + r + " " * gap + '%s"' + (")" if i == len(rows) - 1 else ""))
        with open(a.screenfetch, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")

    ncol = len(pal) if pal is not None else "all"
    print(f"done: {n_w} columns x {len(rows)} rows, {ncol} colours")
    print(f"neofetch: set _mino_w={n_w} in ~/.config/neofetch/config.conf")


if __name__ == "__main__":
    main()
