# btw lab

**The lab notebook: what we tried, what broke, how we found out why, and what it taught us.**

This isn't the place to report a bug or a vulnerability; open an issue for that. It's
the record of the fundamentals we learned building btw: a Swift VM launcher, an Arch
Linux disk image, a desktop that sits politely inside someone else's desktop, a Windows
installer and a music player. A lot of it was reverse engineering: reading a kernel oops,
a cgroup, a PowerShell error or a file's first bytes until the system told us how it
really works.

We build in the spirit of this year's DEF CON theme, the **age of experimentation**: try
things, have fun, vibe a little, but find out *why* before moving on. Speed is fine.
Not knowing what something does is not. So btw is safe from the start: the first
version of each piece shipped locked down, and nothing was "made secure later".

Each experiment has the same five parts:

- **Tried:** what we expected to work.
- **Saw:** what actually happened.
- **Dug in:** how we found the real cause.
- **Changed:** what btw does now, and where.
- **Fundamental:** the lesson that applies to the next project.

---

## The fundamentals, in short

1. **Trust a key, not a connection.** Pin what you verify (a full fingerprint, a
   checksum file) and an untrusted mirror or plain HTTP can't hurt you.
2. **No shared secrets ship.** No factory password, no default SSH, no open ports.
   The user chooses the one secret, once.
3. **Default deny, then open one hole on purpose.** Firewalls, sudo rules and parser
   options all list what's allowed, not what's forbidden.
4. **Content, not names.** A file's extension is a suggestion; its bytes decide what
   parses it. Check what a file *is* before handing it to a big parser.
5. **Only touch what you started.** Kill your own PIDs, not process names; own your
   own config dir, not `~/.config`; claim a D-Bus name only when it's yours to claim.
6. **Least privilege is precise.** A sudo rule names one command *and* its arguments.
   An entitlement grants one capability.
7. **A password only protects a boundary.** Where there's no boundary (WSL's root is one
   command away for the Windows user), a password is theatre; say so and skip it.
8. **The sandbox is the boundary for root.** A firewall in the VM contains programs and
   users; root can turn it off, so the VM itself is what contains root.
9. **Be loud when something fails.** A silent failure looks like success or a crash,
   and either one gets "fixed" the wrong way.
10. **Read the actual error.** Most of the fixes below came from reading one log line
    carefully instead of guessing.

---

## Supply chain: getting the bits safely

### Arch Linux ARM's mirror had no valid TLS certificate
- **Tried:** download the Arch Linux ARM root tarball over HTTPS, check its md5.
- **Saw:** the build died on its first step: `os.archlinuxarm.org` redirects to mirrors
  without a valid certificate, so curl refused.
- **Dug in:** TLS was never what made the download trustworthy anyway: md5 is broken,
  and HTTPS only proves you reached *a* mirror, not that the mirror is honest.
- **Changed:** fetch over plain HTTP and verify the PGP signature against Arch Linux
  ARM's build key, pinned by its **full fingerprint**
  (`distro/Dockerfile`, `ALARM_SIGNER`). The check greps GnuPG's machine-readable
  `VALIDSIG` line for that exact fingerprint, so "some valid signature" isn't enough.
- **Fundamental:** authenticity comes from a pinned key, not the transport. Plain HTTP
  plus a pinned signature is stronger than HTTPS plus md5.

### Test kernels and ISOs are checksum-verified, or deleted
- **Changed:** `scripts/fetch-netboot.sh` and `scripts/fetch-iso.sh` download Debian's
  `SHA256SUMS` and compare. On a mismatch the netboot script deletes the file, and the
  ISO script stops before linking the ISO into place and checks it again on every run,
  so a bad download is never used.
- **Fundamental:** a failed check must leave nothing behind that looks valid.

### pacman's download sandbox inside Docker
- **Saw:** `restricting filesystem access failed because the Landlock ruleset could not
  be applied: Operation not permitted`. pacman 7 sandboxes downloads with Landlock and a
  separate `alpm` user, and a `docker build` step isn't allowed to set that up.
- **Changed:** `DisableSandbox` in the builder's pacman.conf, and in `distro/build.sh`
  only for the step that needs it, removed again right after. Package signatures are
  still checked.
- **Fundamental:** when you must turn a protection off, turn off the smallest one, for
  the shortest time, and keep the check that matters (signatures) on. Write down why.

### Docker reads "KEY" as a secret
- **Saw:** Docker's `SecretsUsedInArgOrEnv` lint flagged `ALARM_KEY`.
- **Changed:** renamed to `ALARM_SIGNER`. It's a public fingerprint, not a secret.
- **Fundamental:** name things for what they are. A linter crying wolf trains you to
  ignore it the one time it's right.

---

## Locked down from the first boot

### No factory password
- **Tried:** the first images had user `btw`, password `btw`, like many VM images.
- **Saw:** a password everyone knows is a password nobody has. Anything that could reach
  a login or `sudo` could use it.
- **Changed:** the account starts with no password. The welcome terminal on the VM's own
  screen asks you to choose one, through `/usr/local/lib/btw/set-password`. sudo allows
  that one script without a password (`/etc/sudoers.d/wheel`) **with no arguments**
  (the trailing `""`), and the script itself refuses to run once
  `/var/lib/btw/choose-password` is gone. Order matters in sudoers: the last match wins,
  so the rule sits after the `%wheel` line.
- **Fundamental:** first-run secrets are chosen by the user, once, through a door that
  closes behind them.

### No SSH server
- **Changed:** `sshd` is installed but not enabled. If you turn it on, it takes keys
  only: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
  `PermitRootLogin no` (`/etc/ssh/sshd_config.d/10-btw.conf`).
- **Fundamental:** ship services off. Make turning them on a deliberate act that
  already has safe settings waiting.

### An always-on firewall
- **Changed:** `/etc/nftables.conf` drops everything inbound, forwards nothing, and lets
  the VM reach the internet but **not** private ranges (your Mac, your LAN, other VMs),
  except DNS and DHCP from the Mac's NAT. Private destinations get a clear
  `admin-prohibited` reject, not a silent timeout, so a blocked app fails fast. Holes go
  in `/etc/nftables.d/*.input.nft`, so you never edit the base rules.
- **Dug in:** the honest limit: root in the VM can turn the firewall off. What contains
  root is Apple's Virtualization framework. A VPN on the Mac doesn't change any of this.
- **Fundamental:** know which layer contains which attacker, and write it down.

### The boot test checks the lockdown, not just the boot
- **Changed:** `scripts/boot-test.py` checks that the firewall is loaded, sshd is off,
  the old password `btw` is refused and the first-password flow works.
- **Dug in:** two flaky timeouts taught us about terminals: `passwd` flushes pending
  input when it exits, and `sudo` runs its command in its own pty, so text typed before
  either finished was silently thrown away. The test now waits for the prompt.
- **Fundamental:** security settings are features, so test them like features. A
  regression back to a default password should fail CI.

### One entitlement
- **Changed:** `app/btw.entitlements` grants exactly `com.apple.security.virtualization`,
  and CI checks it's there after signing. Without it the framework refuses to start a VM.
- **Fundamental:** ask the OS for one capability, then verify you got exactly that.

---

## Living inside someone else's desktop

btw can run in a window inside Omarchy or any desktop. Most of what we learned here is
about blast radius: a guest must not break the host.

### `pkill waybar` would have killed Omarchy's bar
- **Tried:** stop btw's bar by name.
- **Saw:** that also matches the user's own waybar and mako.
- **Changed:** `btw-bar` records each program it starts in a pid file per Sway instance,
  and before killing a PID it reads `/proc/<pid>/cmdline` to check it's still btw's
  (PIDs get reused).
- **Fundamental:** act on what you started, verified, never on a name.

### Never read or write `~/.config`
- **Changed:** btw keeps its configs in `/usr/share/btw/config` and passes them to each
  program (`sway --config`, `waybar -c`, `mako --config`, …). `install.sh --uninstall`
  removes exactly the files in `/usr/share/btw/installed-files`, and leaves packages alone.
- **Fundamental:** an installer should be able to say every file it touched, and take
  all of them back.

### btw's window told the whole login that the desktop was Sway
- **Saw:** inside Omarchy, apps started hiding and new windows opened in btw.
- **Dug in:** Arch's `/etc/sway/config.d/50-systemd-user.conf` exports btw's display to
  the whole systemd user session.
- **Changed:** the window config leaves that include out.
- **Fundamental:** read what your dependencies do on startup. Defaults are written for
  the common case, not for yours.

### btw could steal every notification on the desktop
- **Saw:** if btw opened while the outer desktop's notification server was restarting,
  btw took `org.freedesktop.Notifications`, and every notification went into btw's
  window until it closed.
- **Changed:** in window mode `btw-session` sets `BTW_IN_WINDOW=1`, and neither the btw
  shell nor mako starts a server.
- **Fundamental:** a shared bus name is first-come, first-served. Don't race for names
  that belong to someone else.

### Killed with signal 9 before the window appeared
- **Dug in:** the log recorded how Sway ended and which cgroup it started in. App
  launchers run each app in a systemd unit and clean it up; btw, as their child, was
  cleaned up with them.
- **Changed:** `btw-session` hands btw to the user's systemd as its own transient service
  (`systemd-run --user --collect`).
- **Fundamental:** log *how* a process died (exit code or signal) and *where* it lived.
  It turns a mystery into one line.

---

## Untrusted input

### A song is untrusted input
- **Tried:** give Qt's player whatever file is in `~/Music`.
- **Dug in:** a deliberately broken file is the usual way into a media player, and FFmpeg
  picks its demuxer from a file's **contents**, not its name. An HLS playlist renamed
  `.mp3` would make the player fetch URLs and open other files.
- **Changed:** every song goes through `ffprobe` first with
  `-protocol_whitelist file -format_whitelist mp3,flac,ogg,mov,wav,aiff,aac`
  (`distro/music/music.qml`, `safeInput`), and the waveform's ffmpeg gets the same rules.
  Only a file that passes reaches Qt, which can't take those options itself. We dropped
  `.mka` (a container for anything). Tested with an HLS playlist named `.mp3`, a Matroska
  file named `.ogg` and a text file named `.wav`: all skipped.
- **Fundamental:** when a big parser can't be configured safely, put a small, strict gate
  in front of it, with an allowlist, and test it with lies.

### Desktop entries are commands
- **Changed:** `btw-launch` drops `.desktop` field codes (`%f`, `%U`, …) so the menu opens
  apps without file arguments, and Music registers no file types, so it never becomes
  another desktop's default player.
- **Fundamental:** don't register for more than you handle.

---

## Reverse engineering the platform

Not every lesson is a security fix, but each made us better at finding the real cause.

| Symptom | What it really was | How we found it |
|---|---|---|
| Every QEMU boot test timed out | `-cpu max` advertises FEAT_MOPS; the kernel's MOPS `memset` faulted in `modprobe` | Read the oops: `pc : __memset+0x10/0x20`. Apple silicon has no MOPS, so emulate a Neoverse N1 |
| The Mac VM had no sound | Arch Linux ARM's kernel lacks `CONFIG_SND_VIRTIO`, the only sound device the framework offers | Built Linux's own `sound/virtio` with DKMS and checked the module's vermagic against the headers |
| "Is this disk empty?" | A disk with a system has `EFI PART` at byte 512 | Read the GPT spec; `VMBundle.swift` checks those 8 bytes |
| Sparse images in a Mac download | macOS tar is libarchive, which keeps holes in gzip tarballs | Tested a 2 GiB sparse image: identical, 5.1 MB on disk |
| `wsl --version` stopped the Windows install | PowerShell 5.1 turns any stderr from a program into a terminating error | `Invoke-Native` judges by exit code and keeps stdout and stderr apart |
| Recipes vanished from `/tmp` in the build | `arch-chroot` mounts an empty tmpfs over `/tmp` | Staged them in `/var/tmp` |
| Music played silence on a 24-channel interface | Qt's PipeWire output used the sink's AUX0–AUX23 layout and wrote nothing | Compared with apps that worked; routed through PipeWire's PulseAudio service as plain stereo |
| The shell broke during an update | Quickshell hot-reloaded while files were replaced one by one | Turned off file watching for installed files |
| Fractals always thought there was a GPU | `GraphicsInfo` asked on an object that isn't in a window | Asked the page instead |
| A themed config silently didn't apply | foot 1.28 renamed `[colors]` to `[colors-dark]` | Read foot's own warning |

---

## Open edges

The trade-offs we know about and chose for now. Revisit them before each release.

- **`curl … | bash` and `irm … | iex`** trust GitHub and this repo on first run. The
  script is short and readable; reading it before running it is always an option.
- **The dmg is ad-hoc signed, not notarized.** The first open needs right-click → Open.
- **Clipboard sharing is on** between the Mac and the VM (`VMConfiguration.swift`), and
  `--share` folders are writable. Both are opt-in by what you run in the VM.
- **WSL gets sudo without a password,** on purpose: for that Windows user, root in WSL is
  already one command away (`wsl -u root`), so a password would protect nothing.
- **VMs made from an older disk** still have the password `btw` and SSH on. The fix is in
  the README (`passwd`, then `sudo systemctl disable --now sshd`).
- **Root in the VM can turn the firewall off.** The VM boundary is what contains root.

---

## Adding to the lab (here and in every project)

Every project gets a `LAB.md` like this one and a link to it from its README. Add an
entry when you learn something you'd want to know at the start of the next project:
a protection you had to turn off, a default you changed, a failure you only understood
after digging. Keep it short and true, link the file, and if it's a trade-off rather
than a fix, put it under **Open edges**.

```markdown
### <What happened, in a few words>
- **Tried:** <what we expected to work>
- **Saw:** <the actual error or behaviour, quoted if you have it>
- **Dug in:** <how we found the real cause>
- **Changed:** <what the project does now, and in which file>
- **Fundamental:** <the lesson for the next project>
```
