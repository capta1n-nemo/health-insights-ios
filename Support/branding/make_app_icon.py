#!/usr/bin/env python3
"""Generate the HealthInsights app icon.

The mark is a heart drawn as a single clean stroke — the health half — cut
through by an ECG trace whose vertices carry data nodes, the tech half. It is
rendered at 4x and downsampled so every curve stays crisp at 1024px.

    python3 Support/branding/make_app_icon.py

Writes HealthInsights/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # supersample factor
S = SIZE * SS

# Deep navy → teal, so the mark reads as clinical rather than playful.
BG_TOP = (12, 18, 38)
BG_BOTTOM = (10, 74, 84)
GLOW = (30, 214, 190)
MINT = (52, 224, 200)
WHITE = (255, 255, 255)

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "HealthInsights", "Resources", "Assets.xcassets", "AppIcon.appiconset",
    "icon-1024.png",
)


def gradient(w: int, h: int, top, bottom) -> Image.Image:
    """A vertical gradient, built small and scaled up so it stays smooth."""
    strip = Image.new("RGB", (1, 256))
    px = strip.load()
    for y in range(256):
        t = y / 255
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    return strip.resize((w, h), Image.BICUBIC)


def heart_points(cx: float, cy: float, scale: float, n: int = 720):
    """Classic parametric heart, oriented upright in image coordinates."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = (13 * math.cos(t) - 5 * math.cos(2 * t)
             - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((cx + x * scale, cy - y * scale))
    return pts


def brush(draw: ImageDraw.ImageDraw, points, width: float, fill) -> None:
    """Stroke a path by stamping a round brush along it.

    ImageDraw.line serrates tight curves and an inward polygon offset folds at
    the heart's bottom cusp; stamping keeps the width even everywhere.
    """
    r = width / 2
    for x, y in points:
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def ecg_points(cx: float, cy: float, width: float):
    """A single PQRST-ish beat with a flat lead-in and lead-out."""
    x0 = cx - width / 2
    u = width
    # (fraction across, vertical offset in units of u)
    shape = [
        (0.00, 0.00), (0.20, 0.00),
        (0.28, -0.045), (0.35, 0.02),
        (0.42, -0.255), (0.50, 0.225),
        (0.57, -0.05), (0.66, 0.00),
        (0.76, -0.10), (0.84, 0.00),
        (1.00, 0.00),
    ]
    return [(x0 + fx * u, cy + fy * u) for fx, fy in shape]


def main() -> None:
    base = gradient(S, S, BG_TOP, BG_BOTTOM).convert("RGBA")

    # A soft radial bloom behind the mark gives the flat gradient some depth.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = S * 0.40
    gd.ellipse([S / 2 - r, S / 2 - r * 0.92, S / 2 + r, S / 2 + r * 0.92],
               fill=GLOW + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.10))
    base = Image.alpha_composite(base, glow)

    mark = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(mark)

    # Heart as an outline — lighter and more precise than a filled shape.
    cx, cy = S / 2, S * 0.515
    heart = heart_points(cx, cy, S / 52.0, n=2600)
    brush(d, heart, S * 0.038, MINT + (255,))

    # Knock a channel out of the heart so the trace reads as passing through it
    # instead of sitting on top, then lay the trace into that channel. The trace
    # overhangs the heart just enough to show it entering and exiting.
    trace = ecg_points(S / 2, S * 0.545, S * 0.66)
    d.line(trace, fill=(0, 0, 0, 0), width=int(S * 0.060), joint="curve")
    d.line(trace, fill=WHITE + (255,), width=int(S * 0.030), joint="curve")

    # Data nodes on the beat's turning points — the tech cue.
    nr = S * 0.0195
    for i in (4, 5, 8):
        x, y = trace[i]
        d.ellipse([x - nr, y - nr, x + nr, y + nr], fill=WHITE + (255,))
        d.ellipse([x - nr * 0.42, y - nr * 0.42, x + nr * 0.42, y + nr * 0.42],
                  fill=BG_BOTTOM + (255,))

    icon = Image.alpha_composite(base, mark)
    icon = icon.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    icon.save(OUT, "PNG")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
