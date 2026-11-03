#!/usr/bin/env bash
# Copies the btw desktop into a root directory: the scripts, configs, shell,
# theme and wallpaper, and a "btw" entry for the login screen's session list.
# Used by build.sh (the Mac VM's disk) and ../install.sh (an existing Arch
# system, with root /).
#
#   distro/install-files.sh <root>
#
# btw's programs read their configs from /usr/share/btw/config, passed on the
# command line, so they never use or change the configs in a user's ~/.config.
# Every file installed is listed in /usr/share/btw/installed-files, which
# install.sh --uninstall uses.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
root="${1:?usage: install-files.sh <root>}"
manifest=()

put() { # put <mode> <source> <destination below root>
  install -Dm"$1" "$2" "$root$3"
  manifest+=("$3")
}

for bin in btw-session btw-bar btw-apps btw-launch btw-menu btw-open; do
  put 755 "$src/rootfs/usr/local/bin/$bin" "/usr/local/bin/$bin"
done

conf=/usr/share/btw/config
put 644 "$src/rootfs/etc/sway/config" "$conf/sway/config"
put 644 "$src/rootfs/etc/xdg/waybar/config.jsonc" "$conf/waybar/config.jsonc"
put 644 "$src/themes/fractal/waybar.css" "$conf/waybar/style.css"
put 644 "$src/rootfs/etc/xdg/mako/config" "$conf/mako/config"
put 644 "$src/rootfs/etc/xdg/fuzzel/fuzzel.ini" "$conf/fuzzel/fuzzel.ini"
put 644 "$src/rootfs/etc/xdg/foot/foot.ini" "$conf/foot/foot.ini"

for f in "$src"/shell/*.qml; do
  put 644 "$f" "/usr/share/btw/shell/$(basename "$f")"
done
for f in "$src"/themes/fractal/*; do
  put 644 "$f" "/usr/share/btw/themes/fractal/$(basename "$f")"
done
put 644 "$src/themes/fractal/wallpaper.png" /usr/share/backgrounds/btw/fractal.png
put 644 "$src/btw.desktop" /usr/share/wayland-sessions/btw.desktop

manifest+=(/usr/share/btw/installed-files)
mkdir -p "$root/usr/share/btw"
printf '%s\n' "${manifest[@]}" >"$root/usr/share/btw/installed-files"
