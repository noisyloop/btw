# btw on Windows

btw runs on Windows inside **WSL** (Windows Subsystem for Linux) and opens as a window on
your desktop. It comes as one ready-made file, **`btw.wsl`**: Arch Linux with btw already
installed and set up. Nothing gets downloaded or built on your PC during setup.

## Install

1. **Download btw:**
   [btw.wsl](https://github.com/noisyloop/btw/releases/latest/download/btw.wsl)
2. **Double-click `btw.wsl`.** Windows installs it, then opens a window that asks for a
   **user name** and a **password** (you'll need the password when installing software
   inside btw).
3. **btw opens.** Next time, open **btw** from the Start menu.

That's all. If double-clicking does nothing, or Windows doesn't know how to open the file,
see "Before you start" below.

### Before you start (only if step 2 doesn't work)

btw needs WSL, version 2.4.4 or newer, which comes with current Windows 11 and Windows 10
22H2. If you've never used WSL, or double-clicking `btw.wsl` doesn't install it:

1. Open **PowerShell as administrator** (right-click the Start button, then
   "Terminal (Admin)" or "Windows PowerShell (Admin)") and run:
   ```powershell
   wsl --install --no-distribution
   wsl --update
   ```
2. **Restart Windows**, then double-click `btw.wsl` again.

If WSL says virtualization isn't enabled, turn on **virtualization** (often called Intel
VT-x, AMD-V or SVM) in your PC's BIOS/UEFI settings. On some PCs it's off from the factory.

btw for Windows needs an **x86-64 PC**; ARM PCs (Snapdragon) aren't supported yet.

## Use

Opening btw from the Start menu opens a small terminal window, then the btw window. **Keep
the terminal window open** while you use btw: Windows stops Linux once nothing started from
Windows is running.

Inside the window btw uses <kbd>Alt</kbd> where it normally uses <kbd>Super</kbd>, because
Windows keeps the Windows key:

| Keys | Action |
|---|---|
| <kbd>Alt</kbd>+<kbd>D</kbd> | App menu |
| <kbd>Alt</kbd>+<kbd>Enter</kbd> | Terminal |
| <kbd>Alt</kbd>+<kbd>1</kbd>…<kbd>5</kbd> | Switch workspace |
| <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> | Switch between waybar and the btw shell |
| <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>E</kbd> | Close btw |

<kbd>Alt</kbd>+<kbd>Space</kbd> also opens the app menu, unless Windows takes it for its own
window menu. The ▲ btw button on the bar always works.

Inside btw's terminal you're in Arch Linux: `sudo pacman -S <package>` installs software,
and your Windows files are under `/mnt/c`. To get a plain Linux terminal instead of btw when
you open it, create the file `~/.config/btw/no-autostart`.

## Update

Download the newest `btw.wsl` and install it over the old one (this replaces everything
inside btw, so copy out anything you saved there first):

```powershell
wsl --unregister btw
```

then double-click the new `btw.wsl`.

## Remove

```powershell
wsl --unregister btw
```

This removes btw and everything inside it.

## If something goes wrong

- **btw doesn't open, but the terminal window does:** the terminal shows why. btw's own log
  is in btw at `~/.local/state/sway.log`.
- **"no WSLg display":** WSL's support for Linux windows (WSLg) isn't running. In PowerShell:
  `wsl --update`, then `wsl --shutdown`, then open btw again.
- **btw is slow:** in a window on Windows, btw draws on the CPU. That's fine for the desktop
  itself, but heavy apps inside it will feel it.
- **No internet inside btw:** a VPN with a kill switch can block it, as on the Mac. Look
  for "Allow LAN connections" in the VPN's settings.

## Another way: install into Arch Linux on WSL

If you already use Arch Linux in WSL and want btw in it, `install-btw.ps1` installs btw
into that Arch, with a "btw" Start menu shortcut:

```powershell
irm https://raw.githubusercontent.com/noisyloop/btw/main/windows/install-btw.ps1 | iex
```

It does more on your PC (packages, user, systemd), so `btw.wsl` above is the simpler choice.

## How it's built

CI builds `btw.wsl` with `windows/build-wsl.sh`. It starts from Arch Linux's official
container image, installs the same packages and files as `install.sh` on Arch
(`windows/wsl/setup.sh`), adds the WSL parts in `windows/wsl/` (the first-launch setup, the
Start menu shortcut and icon, systemd, and the auto-start), and packs it as a WSL package.
`windows/wsl/test.sh` then opens btw from it in a stand-in for WSLg's display and checks it
comes up and closes cleanly. `btw-wsl` is the launcher: it points btw at WSLg's display and
keeps it in the foreground.
