# btw on Windows

btw runs on Windows inside **WSL** (Windows Subsystem for Linux), in Arch Linux, and opens
as a window on your Windows desktop through **WSLg**, the part of WSL that shows Linux
apps. It's the same btw as on Arch and Omarchy, in the same window mode.

## Requirements

- Windows 11, or Windows 10 22H2
- An x86-64 PC. Arch Linux's WSL image doesn't exist for ARM PCs (Snapdragon) yet.
- Virtualization turned on in the PC's BIOS/UEFI (most PCs have it on already; the
  installer tells you if it's off)

## Install

Open PowerShell (your normal user; no need to run it as administrator) and run:

```powershell
irm https://raw.githubusercontent.com/noisyloop/btw/main/windows/install-btw.ps1 | iex
```

It asks no questions. It:

1. checks WSL, and installs or updates it if it's missing or too old (Windows asks for an
   administrator's OK; choose **Yes**). If Windows has to restart for WSL, the installer
   says so and carries on by itself after you log back in,
2. installs **Arch Linux** from the official WSL image,
3. sets up a Linux user with your Windows user name, sudo and systemd,
4. installs btw with its normal installer, the same one used on Arch and Omarchy, with its
   apps (Fractals, Soundgineer),
5. adds a **btw** shortcut, with the triangle icon, to the Start menu, checks that btw can
   open, and opens it.

The first run takes several minutes, mostly downloading Arch and the packages; each step
shows its progress. Everything is logged to `%LOCALAPPDATA%\btw\install.log`.

The Linux user has no password, and sudo doesn't ask for one. Under WSL, any program you
run on Windows can already be root in Linux (`wsl -u root`), so a password there would
protect nothing; it would only be one more thing to type.

## Use

Open **btw** from the Start menu. It opens in a window and uses <kbd>Alt</kbd> where btw
normally uses <kbd>Super</kbd>, because Windows keeps the Windows key:

| Keys | Action |
|---|---|
| <kbd>Alt</kbd>+<kbd>D</kbd> | App menu |
| <kbd>Alt</kbd>+<kbd>Enter</kbd> | Terminal |
| <kbd>Alt</kbd>+<kbd>1</kbd>…<kbd>5</kbd> | Switch workspace |
| <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> | Switch between the btw shell and waybar |
| <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>E</kbd> | Close btw |

<kbd>Alt</kbd>+<kbd>Space</kbd> also opens the app menu, unless Windows takes it for its own
window menu. The ▲ btw button on the bar always works.

Inside btw's terminal you're in Arch Linux: `sudo pacman -S <package>` installs software,
your Windows files are under `/mnt/c`, and `btw` opens btw's tools and apps (`btw fractals`).

## Update

Run the install command again. It skips what's done and installs the newest btw over the
old one. To try a pull request before it's merged, set the branch first:

```powershell
$env:BTW_BRANCH = "claude/sway-desktop-roadmap-q7kb2y"
irm https://raw.githubusercontent.com/noisyloop/btw/$env:BTW_BRANCH/windows/install-btw.ps1 | iex
```

## Remove

```powershell
$env:BTW_UNINSTALL = "1"
irm https://raw.githubusercontent.com/noisyloop/btw/main/windows/install-btw.ps1 | iex
Remove-Item Env:BTW_UNINSTALL
```

This removes the shortcut, the launcher and btw itself. Arch Linux stays, with your files.
To remove Arch Linux too (this deletes everything in it):

```powershell
wsl --unregister archlinux
```

## If something goes wrong

- **The installer stopped with a red message:** it says what to do. The full story is in
  `%LOCALAPPDATA%\btw\install.log`; send that file along if you ask for help.
- **btw doesn't open from the Start menu:** a message box says why. The details are in
  `%LOCALAPPDATA%\btw\open-btw.log`, and btw's own log is in Arch at
  `~/.local/state/sway.log`.
- **"WSLg isn't running":** run `wsl --update`, then `wsl --shutdown`, and try again.
  Check that Linux GUI apps work at all, e.g. `wsl -d archlinux -- foot`.
- **"virtualization is off":** turn on Intel VT-x or AMD-V (SVM) in your PC's BIOS/UEFI
  settings, then run the installer again.
- **btw is slow:** in a window under WSLg, btw draws on the CPU. That's fine for the desktop
  itself (the wallpaper is a still picture there), but heavy apps inside it will feel it.

## How it works

`install-btw.ps1` sets up Arch and runs btw's normal `install.sh` inside it. The Start menu
shortcut runs `open-btw.ps1`, which runs `wsl.exe -d archlinux -- btw-wsl` without a console
window and shows a message box if btw can't open. `btw-wsl` points btw at WSLg's display,
which lives in `/mnt/wslg/runtime-dir` while systemd's runtime folder is
`/run/user/<uid>`, and then runs `btw-session` in the foreground. WSL shuts Linux down soon
after nothing started from Windows is running, so btw has to stay in the foreground there.
The rest is unchanged btw.
