<p align="center">
  <img src="assets/fractal-banner.svg" alt="btw: a fractal tree growing branch by branch" width="720">
</p>

<!-- Temporary fractal banner. Regenerate with scripts/fractal-banner.py;
     it will be replaced by the real fractal identity (docs/PLAN.md). -->

<h1 align="center">btw</h1>

<p align="center">
  <a href="https://github.com/noisyloop/btw/actions/workflows/build.yml"><img src="https://github.com/noisyloop/btw/actions/workflows/build.yml/badge.svg?branch=main" alt="Build status"></a>
  <a href="https://github.com/noisyloop/btw/releases/latest"><img src="https://img.shields.io/github/v/release/noisyloop/btw?label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%20(Apple%20silicon)-blue" alt="macOS on Apple silicon">
</p>

<p align="center"><b>A fractal-themed Linux desktop you can try on a Mac with one download.</b><br>
A native macOS launcher that boots btw in a VM on Apple silicon.</p>

<p align="center"><a href="https://github.com/noisyloop/btw/releases/latest/download/btw-macos.dmg"><b>Download for Mac</b></a> · <a href="https://github.com/noisyloop/btw/releases/latest/download/btw-factory.img.zst"><b>btw disk image</b></a> · free and open source</p>

> Early days: the app doesn't download the disk image by itself yet. Unpack it with
> `zstd -d btw-factory.img.zst`, then boot it with `btw run --from btw-factory.img`.

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

On Linux (arm64 or x86-64 with QEMU installed), `make boot-test` boots the
built image in QEMU and checks that it logs in, grows its root and powers off.

## How it's built and released

Like [Fleet-51](https://github.com/noisyloop/Fleet-51), one GitHub Actions
workflow (`.github/workflows/build.yml`) does everything:

- **macOS app:** builds, signs and packages `btw-macos.dmg` on an Apple silicon
  runner, then checks its signature and entitlement. Hosted Mac runners can't
  run VMs inside themselves, so the launcher's boot test runs only where
  `btw check` passes.
- **Factory disk:** builds `btw-factory.img` on an arm64 Linux runner and
  boot-tests it in QEMU.
- **Release:** bump `CFBundleShortVersionString` in `app/Info.plist` and merge
  to main. CI then publishes `v<version>` with both files, and the download
  links above point to it.

## Package as an app

```sh
make dmg   # dist/btw.app and dist/btw-macos.dmg, ad-hoc signed
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
.github/    CI: build, test and release (dmg + disk image)
distro/     factory disk build: Dockerfile, build.sh, package list, rootfs overlay
app/        Swift package: the launcher (Virtualization.framework + AppKit), Info.plist, entitlements
assets/     fractal art (the README banner is a temporary placeholder)
scripts/    fetch known-good test kernels/ISOs (checksum-verified), package the .app/.dmg, boot tests, generate the banner
docs/       plan and design notes
```
