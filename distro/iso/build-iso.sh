#!/usr/bin/env bash
# Builds out/btw-<version>-x86_64.iso: btw for PCs, as a live USB that boots
# on BIOS and UEFI (real PCs and VMs alike) and can install itself to a disk
# with "Install btw" (usr/local/bin/btw-install).
#
# Runs as root in an Arch Linux x86-64 container (make iso, or the Build
# workflow on GitHub):
#
#   docker run --rm --privileged -v "$PWD:/work" archlinux:latest /work/distro/iso/build-iso.sh
#
# The profile is Arch's own minimal "baseline" archiso profile for booting,
# with btw on top: the same packages and files as the Mac VM's disk
# (../packages.txt, ../install-files.sh, ../rootfs), minus what only the Mac's
# VM needs, plus what a PC needs (packages.txt here, airootfs/ here).
set -euo pipefail

iso="$(cd "$(dirname "$0")" && pwd)"
distro="$(dirname "$iso")"
repo="$(dirname "$distro")"
out="${BTW_OUT:-$repo/out}"
work="$(mktemp -d /var/tmp/btw-iso.XXXXXX)"
trap 'rm -rf "$work"' EXIT
profile="$work/profile"
air="$profile/airootfs"

version="${BTW_VERSION:-$(grep -A1 CFBundleShortVersionString "$repo/app/Info.plist" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')}"
[[ -n $version ]] || { echo "no version found in app/Info.plist" >&2; exit 1; }

# --- build tools --------------------------------------------------------------
# Containers can't see pacman's disk space and don't allow its download sandbox.
sed -i -e 's/^CheckSpace/#CheckSpace/' -e '/^\[options\]/a DisableSandbox' /etc/pacman.conf
pacman -Syu --noconfirm --needed archiso grub syslinux git base-devel cmake ninja pkgconf \
  qt6-declarative qt6-multimedia pipewire-jack >/dev/null

# --- profile: Arch's baseline, for booting only ---------------------------------
base=/usr/share/archiso/configs/baseline
mkdir -p "$air/etc/mkinitcpio.conf.d" "$air/etc/systemd"
cp -r "$base/efiboot" "$base/grub" "$base/syslinux" "$base/pacman.conf" "$profile/"
cp "$base/airootfs/etc/locale.conf" "$air/etc/"
cp -P "$base/airootfs/etc/localtime" "$air/etc/"
cp "$base/airootfs/etc/mkinitcpio.conf.d/archiso.conf" "$air/etc/mkinitcpio.conf.d/"
# Keeps the live system from mounting the PC's own partitions by itself.
cp -rP "$base/airootfs/etc/systemd/system-generators" "$air/etc/systemd/"
# Its menus say btw, not Arch Linux.
find "$profile/efiboot" "$profile/grub" "$profile/syslinux" -type f -name '*.c*' \
  -exec sed -i 's/Arch Linux/btw/g' {} +

# --- packages: btw's, without the Mac VM's, plus a PC's -------------------------
{
  grep -Ev '^\s*(#|$)' "$distro/packages.txt" |
    grep -Evx 'archlinuxarm-keyring|linux-aarch64|linux-aarch64-headers|dkms'
  grep -Ev '^\s*(#|$)' "$iso/packages.txt"
} | sort -u >"$profile/packages.x86_64"

# --- btw's files -----------------------------------------------------------------
# mkarchiso copies airootfs in before it installs the packages, and some of
# btw's files replace ones that packages ship (sway's config, nftables.conf,
# ...). So btw's files wait in a stage, and a pacman hook that runs after
# every package is in copies them over and removes itself (airootfs/etc/pacman.d/hooks).
stage="$air/var/lib/btw-iso/stage"
mkdir -p "$stage"
cp -r "$distro/rootfs/." "$stage/"
# Only for the Mac's VM: its disk layout, its virtio-only initramfs, its wired
# network, its serial console, and a firewall that keeps it off your LAN.
rm -rf "$stage/etc/fstab" "$stage/etc/repart.d" "$stage/etc/mkinitcpio.conf.d/btw.conf" \
  "$stage/etc/systemd/network" "$stage/etc/systemd/system/serial-getty@hvc0.service.d"
"$distro/install-files.sh" "$stage"
install -Dm644 "$distro/themes/fractal/waybar.css" "$stage/etc/xdg/waybar/style.css"
cp -r "$iso/stage/." "$stage/"
cp -r "$iso/airootfs/." "$air/"

# Soundgineer (and any other app in apps.txt), built against the same Arch
# packages the ISO ships, the way build.sh does it for the Mac disk.
apps="$work/apps"
mkdir -p "$apps"
while read -r name repo_url branch _cmd; do
  git clone -q --depth 1 --branch "$branch" "$repo_url" "$apps/src-$name" </dev/null
  bash "$distro/apps/$name.sh" "$apps/src-$name" "$stage" </dev/null
done < <(grep -Ev '^\s*(#|$)' "$distro/apps.txt")

# Services, enabled the way systemctl would.
want() { # want <target> <unit> [<unit dir>]
  local dir="${3:-/usr/lib/systemd/system}"
  mkdir -p "$stage/etc/systemd/system/$1.wants"
  ln -sf "$dir/$2" "$stage/etc/systemd/system/$1.wants/$2"
}
want multi-user.target NetworkManager.service
want multi-user.target systemd-resolved.service
want multi-user.target nftables.service
want sysinit.target systemd-timesyncd.service
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service \
  "$stage/etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service"
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
  "$stage/etc/systemd/system/dbus-org.freedesktop.resolve1.service"
if [[ -f $stage/usr/lib/systemd/user/soundgineer.socket ]]; then
  mkdir -p "$stage/etc/systemd/user/sockets.target.wants"
  ln -sf /usr/lib/systemd/user/soundgineer.socket "$stage/etc/systemd/user/sockets.target.wants/"
fi
# Straight into airootfs, not the stage: during the build, pacstrap's chroot
# has the build machine's resolv.conf mounted over this path.
ln -sf /run/systemd/resolve/stub-resolv.conf "$air/etc/resolv.conf"

# --- profiledef: mkarchiso copies airootfs without its modes, so list them -------
{
  cat <<EOF
#!/usr/bin/env bash
# shellcheck disable=SC2034
iso_name="btw"
iso_label="BTW_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="btw <https://github.com/noisyloop/btw>"
iso_application="btw live and installer"
iso_version="$version"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="erofs"
airootfs_image_tool_options=('-zlzma,109' -E 'ztailpacking')
file_permissions=(
EOF
  (cd "$air" && find . -type f -perm -u+x -printf '%P\n') | sort |
    while read -r f; do printf '  ["/%s"]="0:0:755"\n' "$f"; done
  (cd "$air" && find var/lib/btw-iso/stage/etc/sudoers.d -type f -printf '%p\n') | sort |
    while read -r f; do printf '  ["/%s"]="0:0:440"\n' "$f"; done
  echo ')'
} >"$profile/profiledef.sh"

# --- build ---------------------------------------------------------------------
mkdir -p "$out"
mkarchiso -v -r -w "$work/mkarchiso" -o "$work/out" "$profile"
built=("$work/out"/btw-*.iso)
name="btw-$version-x86_64.iso"
mv "${built[0]}" "$out/$name"
(cd "$out" && sha256sum "$name" >"$name.sha256")
echo "built $out/$name ($(du -h "$out/$name" | cut -f1))"
