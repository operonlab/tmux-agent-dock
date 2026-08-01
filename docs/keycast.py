#!/usr/bin/env python3
"""Overlay keystroke labels onto docs/demo.gif, KeyCastr-style.

vhs records the screen but not the keys, so the arrow-and-Enter navigation in
the demo looks like it happens by itself. This draws a small labelled box at the
moment each key is pressed, so the jump reads as a deliberate action.

The timings below are tied to docs/demo.tape: each entry is (label, start_s,
end_s) measured from the recording's first shown frame, and each label persists
until the next action. If you change the tape's Sleep durations, update these.

Usage:  python3 docs/keycast.py            # rewrites docs/demo.gif in place
        python3 docs/keycast.py in.gif out.gif
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageSequence

# (label, start_s, end_s) — see docstring; end=None means "until the end".
EVENTS = [
    ("↓", 2.0, 3.7),
    ("↓", 3.7, 5.4),
    ("↑", 5.4, 6.6),
    ("↑", 6.6, 8.0),
    ("⏎  jump", 8.0, None),
]

# The box sits centre-left: empty during the dock phase (a shell) and during the
# jump phase (the agent's output is at the bottom), so it never covers content.
BOX_X, BOX_Y, FONT_SIZE = 96, 520, 54

FONT_CANDIDATES = [
    "/Users/{u}/Library/Fonts/MesloLGSNerdFontMono-Regular.ttf",
    "/Library/Fonts/MesloLGSNerdFontMono-Regular.ttf",
]


def find_font():
    import os

    for pat in FONT_CANDIDATES:
        p = pat.format(u=os.environ.get("USER", ""))
        if Path(p).exists():
            return p
    # fall back to any Meslo Nerd Font on the system
    for base in (
        "/Users/{u}/Library/Fonts".format(u=os.environ.get("USER", "")),
        "/Library/Fonts",
    ):
        d = Path(base)
        if d.is_dir():
            for f in d.glob("*MesloLGS*NerdFontMono*.ttf"):
                return str(f)
    raise SystemExit(
        "keycast: no MesloLGS Nerd Font Mono found; install it or edit FONT_CANDIDATES"
    )


def active(t):
    for lab, s, e in EVENTS:
        if s <= t and (e is None or t < e):
            return lab
    return None


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "demo.gif"
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src
    font = ImageFont.truetype(find_font(), FONT_SIZE)

    im = Image.open(src)
    frames, durations = [], []
    t = 0.0
    for fr in ImageSequence.Iterator(im):
        d = fr.info.get("duration", 40)
        rgb = fr.convert("RGB")
        lab = active(t)
        if lab:
            dr = ImageDraw.Draw(rgb)
            bb = dr.textbbox((0, 0), lab, font=font)
            tw, th, pad = bb[2] - bb[0], bb[3] - bb[1], 26
            x1, y1 = BOX_X + tw + pad * 2, BOX_Y + th + pad * 2
            dr.rounded_rectangle(
                [BOX_X, BOX_Y, x1, y1],
                radius=16,
                fill=(24, 24, 27),
                outline=(120, 120, 130),
                width=3,
            )
            dr.text(
                (BOX_X + pad - bb[0], BOX_Y + pad - bb[1]),
                lab,
                font=font,
                fill=(255, 255, 255),
            )
        frames.append(rgb)
        durations.append(d)
        t += d / 1000.0

    pal = [f.quantize(colors=256) for f in frames]
    pal[0].save(
        dst,
        save_all=True,
        append_images=pal[1:],
        duration=durations,
        loop=0,
        disposal=2,
        optimize=False,
    )
    print(f"keycast: {len(frames)} frames, {t:.2f}s -> {dst}")


if __name__ == "__main__":
    main()
