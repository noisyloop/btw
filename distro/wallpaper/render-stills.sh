#!/usr/bin/env bash
# Renders the still wallpapers, one per fractal, from the live wallpaper's
# shaders: distro/themes/fractal/stills/<fractal>.png, 2560x1600. They're
# committed, like the .qsb files, so building btw doesn't need a GPU. Rerun
# after changing the shaders or the camera times in render-stills.qml.
# Needs a Wayland desktop with a GPU, Quickshell and Pillow (python-pillow).
set -euo pipefail
cd "$(dirname "$0")"
out="$PWD/../themes/fractal/stills"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$out"

BTW_STILLS_OUT="$tmp" QT_QPA_PLATFORM=wayland quickshell -p "$PWD/render-stills.qml" 2>&1 |
    grep -E "saved|FAILED|ERROR" || true

# Scaled displays render at a multiple of the size asked for; scale to 2560x1600
# and drop the alpha channel, which wallpapers don't use.
python3 - "$tmp" "$out" <<'PY'
import sys
from pathlib import Path
from PIL import Image
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
files = sorted(src.glob("*.png"))
if len(files) != 4:
    sys.exit(f"expected 4 renders, got {len(files)}")
for f in files:
    im = Image.open(f).convert("RGB").resize((2560, 1600), Image.LANCZOS)
    im.save(dst / f.name, optimize=True)
    print(f"wrote {dst / f.name} ({(dst / f.name).stat().st_size // 1024} KiB)")
PY
