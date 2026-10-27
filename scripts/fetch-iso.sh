#!/usr/bin/env bash
# Downloads the current Debian arm64 netinst ISO (~700 MB) and verifies it.
# Any arm64 ISO with EFI boot works; this is just a known-good default.
set -euo pipefail

dest="${1:-$(cd "$(dirname "$0")/.." && pwd)/.cache/iso}"
base="https://cdimage.debian.org/debian-cd/current/arm64/iso-cd"

mkdir -p "$dest"
cd "$dest"

curl -fsSL -o SHA256SUMS "$base/SHA256SUMS"
name="$(awk '$2 ~ /-arm64-netinst\.iso$/ { print $2; exit }' SHA256SUMS)"
[[ -n "$name" ]] || { echo "no netinst ISO listed in $base/SHA256SUMS" >&2; exit 1; }

if ! grep " $name\$" SHA256SUMS | shasum -a 256 -c - >/dev/null 2>&1; then
  echo "fetching $name"
  curl -fL -C - --progress-bar -o "$name" "$base/$name"
  grep " $name\$" SHA256SUMS | shasum -a 256 -c -
fi
ln -sf "$name" debian-arm64-netinst.iso
echo "ready: $dest/debian-arm64-netinst.iso"
