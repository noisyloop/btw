<p align="center">
  <img src="assets/fractal-banner.svg" alt="btw: a fractal tree growing branch by branch" width="720">
</p>

<!-- Temporary fractal banner. Regenerate with scripts/fractal-banner.py;
     it will be replaced by the real fractal identity (docs/PLAN.md). -->

# btw

A fractal-themed Linux desktop you can try on a Mac with one download: a native macOS
launcher that boots a btw VM on Apple silicon.

The current milestone is proving the hardest part: **booting a Linux VM from
Swift on an M1**. See [docs/PLAN.md](docs/PLAN.md) for the full roadmap.

## Requirements

- An Apple silicon Mac (M1 or newer) on macOS 13 Ventura or newer
- Xcode Command Line Tools (`xcode-select --install`) for `swift` and `codesign`

## Prove it boots

```sh
# 1. Headless: boots Debian's arm64 installer kernel with the console in your terminal.
#    ~40 MB download. Success = kernel log, then the installer's language menu.
#    Press Ctrl-] to stop the VM.
make smoke

# 2. Windowed: boots an arm64 installer ISO through UEFI in a native window with
#    virtio-gpu graphics, keyboard, mouse, sound, NAT networking and clipboard sharing.
#    ~700 MB download.
make gui
```

`make build` alone produces `app/.build/release/btw`, ad-hoc signed with the
`com.apple.security.virtualization` entitlement. Without that entitlement the
framework refuses to start a VM.

## Build and boot the btw factory disk

```sh
make image     # Docker (arm64): pacstrap Arch Linux ARM -> out/btw-factory.img (+ .zst)
make factory   # clone it into a 32 GiB VM and boot it via EFI + systemd-boot
```

The factory disk is a GPT image: an ESP with systemd-boot, the kernel and the
initramfs (mounted at `/boot`), and an ext4 root that grows itself to fill
whatever disk size the launcher gives the VM. It logs in automatically as `btw`
(password `btw`) on both the window and the serial console. Packages are listed
in `distro/packages.txt`, and config files are overlaid from `distro/rootfs/`.

## Package as an app

```sh
make dmg   # dist/btw.app and dist/btw.dmg, ad-hoc signed
```

Drop a 1024×1024 `assets/AppIcon.png` in place to get an app icon. Double-clicking
`btw.app` asks whether to boot the existing VM or install from an ISO. The dmg is
ad-hoc signed, not notarized, so on another Mac you have to right-click the app
and choose Open the first time.

## Using the launcher directly

```sh
btw run --iso ~/Downloads/some-arm64.iso       # install from an ISO (EFI)
btw run                                         # boot the installed disk afterwards
btw run --headless --kernel Image --initrd initrd.gz --cmdline "console=hvc0 root=/dev/vda2"
btw run --share ~/code                          # in the guest: mount -t virtiofs btw /mnt/btw
btw --help
```

Each VM is a bundle in `~/Library/Application Support/btw/VMs/<name>/`
containing a sparse `disk.img`, EFI variables, a stable machine identifier and
`console.log` (the serial console in windowed mode). Delete the folder to start over.

If Rosetta for Linux is installed on the host (`softwareupdate --install-rosetta`),
it is exposed to the guest under the `rosetta` virtiofs tag, so x86-64 Linux
binaries can run in the arm64 guest.

## Layout

```
distro/     factory disk build: Dockerfile, build.sh, package list, rootfs overlay
app/        Swift package: the launcher (Virtualization.framework + AppKit), Info.plist, entitlements
assets/     fractal art (the README banner is a temporary placeholder)
scripts/    fetch known-good test kernels/ISOs (checksum-verified), package the .app/.dmg, generate the banner
docs/       plan and design notes
```
