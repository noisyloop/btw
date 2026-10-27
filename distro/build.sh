#!/usr/bin/env bash
# Builds out/btw-factory.img (+ btw-factory.tar.gz) inside the builder container:
#   GPT disk = ESP (systemd-boot, kernel, initramfs) + ext4 root.
# Filesystems are populated with mkfs.ext4 -d / mtools, so no loop devices are
# needed; --privileged is only for pacstrap/arch-chroot mounts.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
out="${BTW_OUT:-$src/../out}"
size_gib="${BTW_IMAGE_GIB:-8}"
esp_mib=512
work="$(mktemp -d)"
root="$work/root"
esp="$work/esp"
trap 'rm -rf "$work"' EXIT

mkdir -p "$root" "$esp" "$out"

# --- rootfs -----------------------------------------------------------------
mapfile -t packages < <(grep -Ev '^\s*(#|$)' "$src/packages.txt")
pacstrap -c "$root" "${packages[@]}"

# Plain -r so files end up owned by root, not by whoever owns the checkout.
cp -r "$src/rootfs/." "$root/"
chmod 0440 "$root/etc/sudoers.d/wheel"

arch-chroot "$root" /bin/bash -euxo pipefail <<'CHROOT'
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
useradd -m -G wheel -s /bin/bash btw
echo btw:btw | chpasswd
systemctl enable systemd-networkd systemd-resolved systemd-timesyncd sshd
mkdir -p /etc/systemd/system/sysinit.target.wants
ln -sf /usr/lib/systemd/system/systemd-repart.service /etc/systemd/system/sysinit.target.wants/

# autodetect would size the initramfs for the build container, not the VM.
kver="$(ls /usr/lib/modules | head -n1)"
mkinitcpio -k "$kver" -g /boot/initramfs-linux.img -S autodetect
rm -f /boot/initramfs-linux-fallback.img
CHROOT
# arch-chroot bind-mounts resolv.conf, so link it once we're out.
ln -sf /run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
pacman --root "$root" -Scc --noconfirm >/dev/null

# --- ESP --------------------------------------------------------------------
# The guest mounts the ESP at /boot, so kernel updates inside the VM land there.
cp -a "$root/boot/." "$esp/"
find "$root/boot" -mindepth 1 -delete
rm -rf "$esp/dtbs" "$esp/Image.gz"
if [[ ! -f "$esp/Image" ]]; then
  echo "linux-aarch64 did not install /boot/Image" >&2
  exit 1
fi
# Removable-media path: boots on a fresh VM whose EFI variables are empty.
mkdir -p "$esp/EFI/BOOT" "$esp/EFI/systemd"
cp "$root/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$esp/EFI/BOOT/BOOTAA64.EFI"
cp "$root/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$esp/EFI/systemd/"
cp -r "$src/esp/." "$esp/"

# --- disk image -------------------------------------------------------------
root_mib=$((size_gib * 1024 - 1 - esp_mib - 1))   # 1 MiB for each GPT copy

truncate -s "${esp_mib}M" "$work/esp.img"
mkfs.fat -F 32 -n BTW-ESP "$work/esp.img" >/dev/null
mcopy -s -i "$work/esp.img" "$esp"/* ::/

truncate -s "${root_mib}M" "$work/root.img"
mkfs.ext4 -q -L btw-root -d "$root" "$work/root.img"

img="$work/btw-factory.img"
truncate -s "${size_gib}G" "$img"
# Root uses the arm64 root type GUID so systemd-repart can grow it on first boot.
sfdisk -q "$img" <<SFDISK
label: gpt
start=2048, size=$((esp_mib * 2048)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=esp
start=$(((1 + esp_mib) * 2048)), size=$((root_mib * 2048)), type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE, name=root
SFDISK
dd if="$work/esp.img" of="$img" bs=1M seek=1 conv=notrunc,sparse status=none
dd if="$work/root.img" of="$img" bs=1M seek=$((1 + esp_mib)) conv=notrunc,sparse status=none

cp --sparse=always "$img" "$out/btw-factory.img"
# A sparse tar.gz: macOS's built-in tar unpacks it (zstd isn't on a stock Mac)
# and recreates the holes, so the unpacked image stays small on disk.
tar --sparse -czf "$out/btw-factory.tar.gz" -C "$out" btw-factory.img
echo "built $out/btw-factory.img ($(du -h "$out/btw-factory.img" | cut -f1) used, ${size_gib}G virtual)"
echo "built $out/btw-factory.tar.gz ($(du -h "$out/btw-factory.tar.gz" | cut -f1))"
