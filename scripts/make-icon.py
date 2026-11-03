#!/usr/bin/env python3
"""Draws the btw app icon: a green Sierpinski triangle on black.

The triangle is the ▲ in the btw logo, drawn as a fractal (btw's identity).
Writes assets/AppIcon.svg (no dependencies) and assets/AppIcon.png at
1024x1024 (needs Pillow: pip install pillow). scripts/package.sh turns the PNG
into the macOS .icns.

  scripts/make-icon.py [depth, default 3]
"""
import math
import os
import sys

SIZE = 1024
BLACK = "#07080a"   # the theme's background (desktop/theme.css)
GREEN = "#3ddc97"   # the theme's accent
# macOS icon grid: an 824px rounded square centered on the 1024px canvas.
TILE = 824
RADIUS = 185
# The triangle: 60% of the canvas wide, nudged down a little so it looks
# centered (a triangle's visual center sits below its bounding-box center).
WIDTH = 0.6 * SIZE
NUDGE = 0.035 * SIZE

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")


def outer_triangle():
    h = WIDTH * math.sqrt(3) / 2
    cx, cy = SIZE / 2, SIZE / 2 + NUDGE
    return [(cx, cy - h / 2), (cx + WIDTH / 2, cy + h / 2), (cx - WIDTH / 2, cy + h / 2)]


def sierpinski(tri, depth):
    """The filled triangles of a Sierpinski triangle of the given depth."""
    if depth == 0:
        return [tri]
    a, b, c = tri
    ab = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    bc = ((b[0] + c[0]) / 2, (b[1] + c[1]) / 2)
    ca = ((c[0] + a[0]) / 2, (c[1] + a[1]) / 2)
    return (sierpinski((a, ab, ca), depth - 1)
            + sierpinski((ab, b, bc), depth - 1)
            + sierpinski((ca, bc, c), depth - 1))


def write_svg(tris, path):
    off = (SIZE - TILE) / 2
    polys = "\n".join(
        '  <polygon points="%s"/>' % " ".join("%.2f,%.2f" % p for p in t) for t in tris)
    with open(path, "w") as f:
        f.write(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
<rect x="{off}" y="{off}" width="{TILE}" height="{TILE}" rx="{RADIUS}" fill="{BLACK}"/>
<g fill="{GREEN}">
{polys}
</g>
</svg>
''')


def write_png(tris, path):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("Pillow isn't installed (pip install pillow); skipped", path)
        return
    ss = 4  # draw 4x larger and scale down, for smooth edges
    img = Image.new("RGBA", (SIZE * ss, SIZE * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    off = (SIZE - TILE) / 2 * ss
    d.rounded_rectangle([off, off, off + TILE * ss - 1, off + TILE * ss - 1], RADIUS * ss, fill=BLACK)
    for t in tris:
        d.polygon([(x * ss, y * ss) for x, y in t], fill=GREEN)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path)


def main():
    depth = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    tris = sierpinski(outer_triangle(), depth)
    os.makedirs(ROOT, exist_ok=True)
    write_svg(tris, os.path.join(ROOT, "AppIcon.svg"))
    write_png(tris, os.path.join(ROOT, "AppIcon.png"))
    print("wrote assets/AppIcon.svg and assets/AppIcon.png (depth %d)" % depth)


if __name__ == "__main__":
    main()
