#!/usr/bin/env python3
"""Generate theme-aware bar icons from the transparent source PNGs (requires Pillow)."""

from pathlib import Path

from PIL import Image, ImageFilter

ASSETS = Path(__file__).resolve().parents[1] / "nodus/assets"

for stem in ("nodus-icon", "nodus-icon-grayscale"):
    source = Image.open(ASSETS / f"{stem}.png").convert("RGBA")
    # Seven source pixels give a roughly 0.8px outline at the 22px bar size.
    outline = source.getchannel("A").filter(ImageFilter.MaxFilter(15))
    for theme, color in (("dark", "#eeeeee"), ("light", "#252525")):
        background = Image.new("RGBA", source.size, color)
        background.putalpha(outline)
        image = Image.alpha_composite(background, source)
        image.save(ASSETS / f"{stem}-{theme}.png", optimize=True)
