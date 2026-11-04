#!/usr/bin/env bash
# Builds btw.wsl: Arch Linux with btw installed, as a WSL package that
# Windows installs with a double-click (WSL 2.4.4 or newer). Needs Docker,
# on x86-64 Linux (CI runs it on GitHub's ubuntu-latest).
#
#   windows/build-wsl.sh [output, default out/btw.wsl]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/out/btw.wsl}"
mkdir -p "$(dirname "$out")"

# The same packages install.sh installs on Arch, read from install.sh itself.
mapfile -t packages < <(bash -c 'source <(sed -n "/^PACKAGES=(/,/^)/p" "$1"); printf "%s\n" "${PACKAGES[@]}"' _ "$root/install.sh")
echo "packages: ${packages[*]}"

name="btw-wsl-build-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run --name "$name" -v "$root:/src:ro" archlinux:base \
  bash /src/windows/wsl/setup.sh "${packages[@]}"

# WSL installs a gzipped tar of the whole filesystem.
docker export "$name" | gzip -6 >"$out"
echo "built $out ($(du -h "$out" | cut -f1))"
