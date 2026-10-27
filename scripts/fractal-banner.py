#!/usr/bin/env python3
"""Generates assets/fractal-banner.svg, the temporary README banner.

A recursive branching tree that grows in one depth level at a time, with
twinkling tips. Placeholder until the real fractal identity generator exists
(see docs/PLAN.md). Stdlib only: python3 scripts/fractal-banner.py
"""
import math
import pathlib

WIDTH, HEIGHT = 900, 340
DEPTH = 11
SPREAD = math.radians(24)
SHRINK = 0.74
TRUNK = 84


def grow(x, y, angle, length, depth, levels):
    if depth > DEPTH:
        return
    x2 = x + length * math.cos(angle)
    y2 = y - length * math.sin(angle)
    levels[depth].append((x, y, x2, y2))
    for turn in (-SPREAD, SPREAD):
        grow(x2, y2, angle + turn, length * SHRINK, depth + 1, levels)


def main():
    levels = [[] for _ in range(DEPTH + 1)]
    grow(WIDTH / 2, HEIGHT - 8, math.pi / 2, TRUNK, 0, levels)

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" '
        f'width="{WIDTH}" height="{HEIGHT}" role="img" aria-label="btw fractal">',
        "<style>",
        ".level{opacity:0;animation:grow .6s ease-out forwards}",
        ".tip{animation:grow .6s ease-out forwards,twinkle 2.4s ease-in-out infinite alternate}",
        "@keyframes grow{from{opacity:0}to{opacity:1}}",
        "@keyframes twinkle{from{opacity:1}to{opacity:.35}}",
        "@media (prefers-reduced-motion:reduce){.level,.tip{animation:none;opacity:1}}",
        "</style>",
        '<g stroke-linecap="round" fill="none">',
    ]
    for depth, segments in enumerate(levels):
        t = depth / DEPTH
        hue = 275 - 95 * t  # violet trunk -> cyan tips
        width = max(0.6, 7 * (1 - t) ** 1.6)
        d = "".join(f"M{x1:.1f} {y1:.1f}L{x2:.1f} {y2:.1f}" for x1, y1, x2, y2 in segments)
        cls = "level tip" if depth == DEPTH else "level"
        delay = depth * 0.18
        out.append(
            f'<path class="{cls}" style="animation-delay:{delay:.2f}s,{delay + 0.6:.2f}s" '
            f'stroke="hsl({hue:.0f} 85% 62%)" stroke-width="{width:.2f}" d="{d}"/>'
        )
    out += ["</g>", "</svg>", ""]

    path = pathlib.Path(__file__).resolve().parent.parent / "assets" / "fractal-banner.svg"
    path.write_text("\n".join(out))
    print(f"wrote {path} ({path.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
