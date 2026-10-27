# btw plan

The goal is something like [Try Omarchy](https://github.com/omacom/try-omarchy),
but better: a `.dmg` with a native Mac app that boots a full btw Linux desktop
in seconds, with the Mac integration working out of the box.

Identity: **btw is fractal.** Recursive and self-similar, from the app icon to
the boot splash, the wallpaper and the desktop theme. One generator should
produce all of these at every size, so the look stays consistent.

## How Try Omarchy does it (reference)

- A Swift/AppKit launcher
- A patched QEMU runtime using Apple's Hypervisor.framework (HVF)
- A "factory disk": built in Docker by pacstrap-ing their own package repos,
  shipped as a compressed disk image that the app clones for each VM
- A guest package that provides the Mac integrations

## btw architecture

| Layer | btw choice | Why |
|---|---|---|
| Hypervisor | **Virtualization.framework** (VZ), with QEMU as a fallback to evaluate | Ships with macOS: nothing to patch, build or notarize. Apple maintains it, and it includes virtio-fs, Rosetta for Linux, clipboard sharing (SPICE agent), NAT, sound and dynamic display resizing. |
| Launcher | Swift + AppKit, a single `.app` | Native and small. `VZVirtualMachineView` handles display and input. |
| Image | Factory disk (arm64), cloned per VM with APFS `clonefile` | Cloning is instant and copy-on-write, so creating a new VM costs no disk space up front. |
| Guest | `btw-guest` package | Integrations: shares, Rosetta binfmt, clipboard, resize, time sync. |
| Distribution | Signed, notarized `.dmg` | Same as Try Omarchy. |

### The open risk: GPU acceleration

VZ gives Linux guests a 2D virtio-gpu only, with no 3D. A compositor like
Hyprland then renders on the CPU (llvmpipe). That works but is not smooth.
This is probably why Try Omarchy patches QEMU (virtio-gpu with
virgl/Venus over HVF). The plan:

1. Ship on VZ first and measure how a tiling compositor feels on llvmpipe on
   an M1. A lightweight compositor setup may be good enough.
2. Keep the runtime behind a small `VMRuntime` boundary in the app, so a QEMU
   backend with virtio-gpu GL can replace VZ for the display without touching
   the rest.

### The ISO question

`archiso` does not build arm64 ISOs, and Arch Linux ARM ships rootfs tarballs,
not installers. On a Mac the VM never needs an installer: it boots a
ready-made disk. So:

- **Mac product:** a factory disk built from Arch Linux ARM (or our own repo)
  via `pacstrap` in an arm64 Docker container, the same approach as Try Omarchy.
- **ISO:** a separate output for bare-metal x86-64 installs, built with archiso
  from the same package list. It is not on the Mac critical path.

## Milestones

- [x] **M0: boot a Linux VM from Swift on an M1.** `make smoke` (headless
      kernel boot) and `make gui` (EFI ISO boot in a window).
- [ ] **M1: factory disk.** Written but not yet run: `make image` builds it
      and `make factory` boots it. The `distro/` folder has a package list, an
      arm64 Docker builder that pacstraps Arch Linux ARM, and an image built
      without loop devices (mkfs.ext4 -d, mtools, sfdisk) containing
      systemd-boot and a root partition that grows itself. The launcher's
      `--from` option clones the image for each VM.
- [ ] **M2: guest integration (`btw-guest`).** Auto-mount `btw` and
      `rosetta` virtiofs shares, register the Rosetta binfmt, enable
      spice-vdagent for the clipboard, handle display resize, and power off
      cleanly on `requestStop`.
- [ ] **M3: real app.** An `.app` bundle with a first-run screen that
      unpacks the factory disk and clones it per VM, VM lifecycle
      (start/stop/reset), and settings for CPU, memory and shared folders.
- [ ] **M4: graphics.** Measure llvmpipe performance and decide whether to
      prototype the QEMU + virgl backend.
- [ ] **Desktop.** A first version ships: Sway (CPU rendering), waybar, fuzzel
      (app menu), foot, mako, Firefox, Thunar and Mousepad with the fractal
      theme and wallpaper. Next: Omarchy-style Hyprland, walker and Alacritty
      once graphics allow (M4), themed from `distro/themes/fractal/`. A browser
      preview already exists in `desktop/`. It shares the palette with those
      configs and shows the target layout: tiling, the app menu, a terminal
      at login and a live fractal wallpaper.
- [ ] **Fractal identity.** A generator for the icon (`assets/AppIcon.png`),
      the systemd-boot/Plymouth splash, wallpapers and a matching color theme.
- [x] **CI and releases, like Fleet-51.** One workflow builds the dmg and the
      factory disk, boot-tests the disk in QEMU, and publishes a release when
      the version in `app/Info.plist` changes.
- [ ] **M5: ship.** Developer ID signing and notarization, and an app that
      downloads the latest factory disk from releases on first run.
