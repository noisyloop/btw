#!/usr/bin/env bash
# Runs inside an Arch Linux container, as root, to turn it into btw for WSL.
# build-wsl.sh mounts the btw checkout at /src and passes the packages.
set -euo pipefail
src=/src

# A container can't use pacman's download sandbox or see its disk space; turn
# both off for the build only (the original pacman.conf goes back at the end).
cp /etc/pacman.conf /etc/pacman.conf.orig
sed -i -e 's/^CheckSpace/#CheckSpace/' -e '/^\[options\]/a DisableSandbox' /etc/pacman.conf

pacman-key --init
pacman-key --populate archlinux
pacman -Syu --noconfirm --needed "$@" sudo git

# btw itself, the same files install.sh puts on Arch.
"$src/distro/install-files.sh" /
# btw's "open in a window" app entry is for other desktops; here WSL's own
# Start menu shortcut opens btw.
rm -f /usr/share/applications/btw.desktop

# The WSL parts.
install -Dm755 "$src/windows/btw-wsl" /usr/local/bin/btw-wsl
install -Dm644 "$src/windows/btw.ico" /usr/lib/wsl/btw.ico
install -Dm755 "$src/windows/wsl/btw-oobe.sh" /usr/lib/wsl/btw-oobe.sh
install -Dm644 "$src/windows/wsl/wsl-distribution.conf" /etc/wsl-distribution.conf
install -Dm644 "$src/windows/wsl/wsl.conf" /etc/wsl.conf
install -Dm644 "$src/windows/wsl/profile.sh" /etc/profile.d/btw-wsl.sh

echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
echo 'LANG=C.UTF-8' >/etc/locale.conf

# Clean up: pacman as shipped, no package cache, and no signing keys (each
# install makes its own on first launch). resolv.conf and hostname are
# Docker's while the container runs and come out empty; WSL writes its own.
mv /etc/pacman.conf.orig /etc/pacman.conf
pacman -Scc --noconfirm >/dev/null
rm -rf /etc/pacman.d/gnupg
