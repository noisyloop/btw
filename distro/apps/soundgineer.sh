#!/usr/bin/env bash
# Builds Soundgineer and installs it system-wide, for the factory disk.
# build.sh runs it inside the disk's root (arch-chroot), so it builds against
# exactly the Qt and PipeWire that btw ships, with the build tools installed
# just for this and removed afterwards.
#
#   apps/soundgineer.sh <source dir> [<destdir>]
#
# <destdir> (default /) is where it installs: / inside the chroot, or a test
# root. An installed user's own copy (~/.local) is what install.sh makes on an
# existing Arch system instead.
set -euo pipefail
src="${1:?usage: soundgineer.sh <source dir> [<destdir>]}"
dest="${2:-}"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

cmake -S "$src" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DSG_BUILD_TESTS=OFF \
  -DSG_BUILD_PLUGINS=OFF >/dev/null
cmake --build "$build" --parallel
DESTDIR="$dest" cmake --install "$build" >/dev/null

# The rest of what Soundgineer's own install.sh puts in ~/.local, at the
# system paths instead (the same layout as its AUR package).
install -d "$dest/usr/share/soundgineer/factory"
install -m644 "$src"/presets/factory/*.json "$dest/usr/share/soundgineer/factory/"
install -Dm644 "$src/packaging/systemd/soundgineer.socket" "$dest/usr/lib/systemd/user/soundgineer.socket"
sed 's|%h/.local/bin/soundgineer-engine|/usr/bin/soundgineer-engine|' "$src/packaging/systemd/soundgineer.service" |
  install -Dm644 /dev/stdin "$dest/usr/lib/systemd/user/soundgineer.service"
install -Dm644 "$src/app/soundgineer.desktop" "$dest/usr/share/applications/soundgineer.desktop"
install -Dm644 "$src/app/icons/soundgineer.svg" "$dest/usr/share/icons/hicolor/scalable/apps/soundgineer.svg"
install -Dm644 "$src/LICENSE" "$dest/usr/share/licenses/soundgineer/LICENSE"
echo "soundgineer installed into ${dest:-/}"
