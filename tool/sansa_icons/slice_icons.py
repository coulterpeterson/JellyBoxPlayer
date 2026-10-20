"""Slices the Sansa theme's home screen icons out of atlas.png.

Usage (needs Pillow and NumPy):
  python3 tool/sansa_icons/slice_icons.py tool/sansa_icons/atlas.png out/

The atlas has a transparent background with the icons in two rows: music,
now playing and shuffle on top; settings, games, video and radio below.
Each icon is found from its opaque pixels, cropped, and saved as a
256x256 transparent PNG. The app ships music, now_playing, shuffle,
settings and games (assets/images/sansa/).
"""

import sys

import numpy as np
from PIL import Image

NAMES = [
    ["music", "now_playing", "shuffle"],
    ["settings", "games", "video", "radio"],
]


def spans(mask):
    """Runs of True in a 1-D mask, as (start, end) pairs."""
    out, i = [], 0
    while i < len(mask):
        if mask[i]:
            start = i
            while i < len(mask) and mask[i]:
                i += 1
            out.append((start, i))
        i += 1
    return out


def split_widest(runs, count, weights):
    """Splits touching icons at their thinnest column until there are
    [count] runs."""
    runs = list(runs)
    while len(runs) < count:
        widest = max(range(len(runs)), key=lambda i: runs[i][1] - runs[i][0])
        start, end = runs[widest]
        margin = (end - start) // 4
        cut = start + margin + int(np.argmin(weights[start + margin:end - margin]))
        runs[widest:widest + 1] = [(start, cut), (cut, end)]
    return runs


def main(src, out):
    image = Image.open(src).convert("RGBA")
    alpha = np.asarray(image)[:, :, 3]
    solid = alpha > 128
    rows = spans(solid.any(axis=1))
    rows = [r for r in rows if r[1] - r[0] > 100]
    assert len(rows) == len(NAMES), f"expected {len(NAMES)} rows, got {rows}"
    for (y0, y1), names in zip(rows, NAMES):
        band = solid[y0:y1]
        columns = split_widest(
            [c for c in spans(band.any(axis=0)) if c[1] - c[0] > 100],
            len(names),
            band.sum(axis=0),
        )
        for (x0, x1), name in zip(columns, names):
            icon = image.crop((x0, y0, x1, y1))
            box = Image.fromarray(np.asarray(icon)[:, :, 3]).point(
                lambda v: 255 if v > 40 else 0
            ).getbbox()
            icon = icon.crop(box)
            side = max(icon.size)
            pad = int(side * 0.04)
            canvas = Image.new("RGBA", (side + 2 * pad,) * 2, (0, 0, 0, 0))
            canvas.paste(
                icon,
                ((canvas.width - icon.width) // 2, (canvas.height - icon.height) // 2),
            )
            canvas.resize((256, 256), Image.LANCZOS).save(
                f"{out}/{name}.png", optimize=True
            )
            print(name, (x0 + box[0], y0 + box[1], x0 + box[2], y0 + box[3]))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
