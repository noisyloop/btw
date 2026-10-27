#!/usr/bin/env bash
# Downloads Debian's arm64 netboot kernel + initrd (~40 MB) for the headless
# smoke test, verifies them against Debian's SHA256SUMS, and decompresses the
# kernel (Virtualization.framework's Linux boot loader wants a raw arm64 Image).
set -euo pipefail

dest="${1:-$(cd "$(dirname "$0")/.." && pwd)/.cache/netboot}"
images="https://deb.debian.org/debian/dists/stable/main/installer-arm64/current/images"
dir="netboot/debian-installer/arm64"

mkdir -p "$dest"
cd "$dest"

if [[ -f Image && -f initrd.gz ]]; then
  echo "already fetched: $dest"
  exit 0
fi

curl -fsSL -o SHA256SUMS "$images/SHA256SUMS"
for f in linux initrd.gz; do
  echo "fetching $dir/$f"
  curl -fL --progress-bar -o "$f" "$images/$dir/$f"
  want="$(awk -v p="$dir/$f" '$2 == p || $2 == "./" p { print $1; exit }' SHA256SUMS)"
  got="$(shasum -a 256 "$f" | awk '{ print $1 }')"
  if [[ -z "$want" || "$want" != "$got" ]]; then
    echo "checksum mismatch for $f" >&2
    rm -f "$f"
    exit 1
  fi
done

if [[ "$(od -An -tx1 -N2 linux | tr -d ' \n')" == "1f8b" ]]; then
  gunzip -c linux > Image
  rm linux
else
  mv linux Image
fi
echo "ready: $dest/Image $dest/initrd.gz"
