#!/usr/bin/env bash
# Builds btw on your own Mac: no GitHub Actions needed.
#
#   ./build-local.sh          update, build the app and the disk image, then boot it
#   ./build-local.sh app      only btw.app and btw-macos.dmg (about a minute)
#   ./build-local.sh image    only the disk image (needs Docker, 5-15 minutes)
#   ./build-local.sh boot     boot the last disk image you built
#
# Results: dist/btw.app, dist/btw-macos.dmg, out/btw-factory.img, out/btw-factory.tar.gz
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf '\n\033[1;31mbuild-local: %s\033[0m\n' "$*" >&2; exit 1; }

if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

[[ "$(uname -s)" == Darwin ]] || die "this script runs on a Mac."
[[ "$(uname -m)" == arm64 ]] || die "btw needs an Apple silicon Mac (M1 or newer)."

need_xcode() {
  if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    die "Apple's command line tools are missing. Finish the install window that just opened, then run this again."
  fi
}

need_docker() {
  command -v docker >/dev/null 2>&1 ||
    die "the disk image needs Docker. Install Docker Desktop or OrbStack, open it, then run this again."
  docker info >/dev/null 2>&1 ||
    die "Docker isn't running. Open Docker Desktop (or OrbStack), wait until it has started, then run this again."
  local free_gb
  free_gb="$(df -g . | awk 'NR == 2 { print $4 }')"
  if [[ -n "$free_gb" && "$free_gb" -lt 12 ]]; then
    die "the disk image needs about 12 GB free here; this disk has ${free_gb} GB."
  fi
}

update() {
  if [[ ! -d .git ]] || ! git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    return
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    note "You have local changes, so I'm not pulling updates."
    return
  fi
  step "Getting the latest btw"
  git pull --ff-only || note "Couldn't update automatically; building what's here."
}

build_app() {
  need_xcode
  step "Building btw.app"
  scripts/package.sh
}

build_image() {
  need_docker
  step "Building the btw disk image (5-15 minutes)"
  make image
}

boot() {
  [[ -f out/btw-factory.img ]] || die "there's no disk image yet. Run ./build-local.sh image first."
  need_xcode
  local vm="$HOME/Library/Application Support/btw/VMs/factory"
  # The VM keeps its own disk, so a new image only shows up in a fresh VM.
  if [[ -f "$vm/disk.img" && "$out_is_new" == yes && -t 0 ]]; then
    printf '\nReplace your "factory" VM with the image you just built? Its files will be lost. [y/N] '
    read -r answer
    if [[ "$answer" == [yY]* ]]; then
      rm -rf "$vm"
    fi
  fi
  step "Booting btw (close the window or run 'sudo poweroff' inside to stop)"
  make factory
}

out_is_new=no
case "${1:-all}" in
  app)
    build_app
    ;;
  image)
    build_image
    ;;
  boot)
    boot
    ;;
  all)
    update
    build_app
    build_image
    out_is_new=yes
    step "Built"
    note "App:        dist/btw.app (and dist/btw-macos.dmg)"
    note "Disk image: out/btw-factory.img (and out/btw-factory.tar.gz)"
    boot
    ;;
  *)
    die "unknown command '$1'. Use: app, image, boot, or nothing for everything."
    ;;
esac
