#!/usr/bin/env bash
# Installs the btw desktop on an existing Arch-based system (Arch, Omarchy,
# EndeavourOS, CachyOS, ...), next to whatever desktop it already has. It
# replaces any btw already installed, so it's also how you update.
#
#   ./install.sh                 install the packages and btw
#   ./install.sh --no-packages   only copy btw's files (packages already there)
#   ./install.sh --uninstall     remove btw's files (packages are left alone)
#
# Without a checkout, it fetches btw first (into ~/.local/share/btw/src):
#   curl -fsSL https://raw.githubusercontent.com/noisyloop/btw/main/install.sh | bash
# Once installed, btw-update [branch] fetches the newest btw and reinstalls it.
#
# btw becomes a separate "btw" session: pick it on the login screen, or run
# btw-session from a text console. It keeps its configs in /usr/share/btw and
# doesn't touch your ~/.config, so your current desktop (e.g. Omarchy's
# Hyprland) stays exactly as it is.
set -euo pipefail
REPO="${BTW_REPO:-https://github.com/noisyloop/btw.git}"
SRC="${XDG_DATA_HOME:-$HOME/.local/share}/btw/src"

# Sway and its helpers, the btw shell, and what the desktop scripts use.
PACKAGES=(
  sway swaybg waybar foot fuzzel mako libnotify
  quickshell polkit xdg-utils
  ttf-ibm-plex ttf-dejavu
)

step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf '\n\033[1;31minstall: %s\033[0m\n' "$*" >&2; exit 1; }

packages=yes
case "${1:-}" in
"") ;;
--no-packages) packages=no ;;
--uninstall) mode=uninstall ;;
-h | --help)
  sed -n '2,17p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
  exit 0
  ;;
*) die "unknown option $1 (try --help)" ;;
esac

# Run from a checkout, install that checkout. Otherwise (curl ... | bash),
# fetch btw into $SRC and run the install.sh there.
here="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$here/distro/install-files.sh" ]]; then
  cd "$here"
elif [[ "${mode:-}" != uninstall ]]; then
  command -v git >/dev/null || die "git is missing (sudo pacman -S git)."
  step "Fetching btw"
  if [[ -d "$SRC/.git" ]]; then
    git -C "$SRC" fetch -q --depth 1 origin main
    git -C "$SRC" reset -q --hard FETCH_HEAD
  else
    mkdir -p "$(dirname "$SRC")"
    git clone -q --depth 1 "$REPO" "$SRC"
  fi
  exec bash "$SRC/install.sh" "$@"
fi

[[ $EUID -ne 0 ]] || die "run this as your normal user; it asks for sudo when it needs it."
command -v sudo >/dev/null || die "sudo is missing."

if [[ "${mode:-}" == uninstall ]]; then
  manifest=/usr/share/btw/installed-files
  [[ -f $manifest ]] || die "btw isn't installed here (no $manifest)."
  step "Removing btw's files"
  mapfile -t files <"$manifest"
  sudo rm -f -- "${files[@]}"
  sudo rm -rf /usr/share/btw /usr/share/backgrounds/btw
  rm -rf "$SRC"
  note "Done. The packages are still installed; remove them with pacman if you"
  note "don't need them. Your settings in ~/.config/btw are left in place."
  exit 0
fi

command -v pacman >/dev/null || die "this needs an Arch-based system with pacman."
[[ -x distro/install-files.sh ]] || die "run this from a btw checkout (distro/ is missing)."

if [[ $packages == yes ]]; then
  step "Installing packages"
  # No -Sy here: a sync without a full upgrade can leave Arch half-updated.
  # If pacman can't find a package version, update first (sudo pacman -Syu).
  wanted=()
  for p in "${PACKAGES[@]}"; do
    if pacman -Si "$p" >/dev/null 2>&1; then
      wanted+=("$p")
    else
      note "warning: $p isn't in your repos; skipped"
    fi
  done
  sudo pacman -S --needed --noconfirm "${wanted[@]}"
fi

step "Installing btw"
# Replace any btw already installed: remove its files first, so nothing from
# an older version is left behind.
if [[ -f /usr/share/btw/installed-files ]]; then
  mapfile -t old </usr/share/btw/installed-files
  sudo rm -f -- "${old[@]}"
  note "replaced the btw that was installed"
fi
sudo distro/install-files.sh /
# So app menus find the new icon right away.
if command -v gtk-update-icon-cache >/dev/null; then
  sudo gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
fi
note "scripts in /usr/local/bin, everything else in /usr/share/btw"

step "Done"
note "Try it in a window: open btw from your app menu (or run btw-session)."
note "There it uses Alt instead of Super: Alt+Space apps, Alt+Enter terminal,"
note "Alt+Shift+E closes it."
note ""
note "Or as your whole desktop: log out and choose \"btw\" on the login screen,"
note "or switch to a text console (Ctrl+Alt+F3), log in, and run: btw-session"
note "There: Super+Space apps, Super+Enter terminal, Super+Shift+B switches to"
note "the btw shell (bar, menu, notifications), Super+Shift+E leaves btw."
if [[ -d "$HOME/.local/share/omarchy" ]]; then
  note ""
  note "Omarchy: your Hyprland setup is untouched. If Omarchy logs you in"
  note "automatically, log out from its menu to reach the session list."
fi
note ""
note "To update btw later: btw-update"
note "To remove btw: ./install.sh --uninstall"
