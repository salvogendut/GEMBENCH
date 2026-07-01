#!/usr/bin/env python3
"""Compose the boot splash PNG with the build commit under the progress bar."""
from __future__ import annotations

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


BLUE = (0x00, 0x00, 0x80)
WHITE = (0xFF, 0xFF, 0xFF)


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: make_bootsplash.py <src.png> <out.png> <commit>", file=sys.stderr)
        return 2

    src = Path(sys.argv[1])
    out = Path(sys.argv[2])
    commit = sys.argv[3]

    canvas = Image.new("RGB", (96, 184), BLUE)
    logo = Image.open(src).convert("RGB").resize((96, 144), Image.LANCZOS)
    canvas.paste(logo, (0, 0))

    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    dirty = commit.endswith("-dirty")
    base = commit[:-6] if dirty else commit
    labels = [f"GB {commit}", f"GB {base[:12]}{'+' if dirty else ''}", f"GB {base[:8]}{'+' if dirty else ''}"]
    label = labels[-1]
    for candidate in labels:
        bbox = draw.textbbox((0, 0), candidate, font=font)
        if bbox[2] - bbox[0] <= 96:
            label = candidate
            break
    bbox = draw.textbbox((0, 0), label, font=font)
    tw = bbox[2] - bbox[0]
    x = max(0, (96 - tw) // 2)
    draw.text((x, 172), label, fill=WHITE, font=font)

    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
