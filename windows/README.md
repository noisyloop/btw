# btw on Windows

btw runs on Windows inside **WSL** (Windows Subsystem for Linux), in Arch Linux, and opens
as a window on your Windows desktop through **WSLg**, the part of WSL that shows Linux
apps. It's the same btw as on Arch and Omarchy, in the same window mode.

## Requirements

- Windows 11, or Windows 10 22H2 with the current WSL from the Microsoft Store
- An x86-64 PC. Arch Linux's WSL image doesn't exist for ARM PCs (Snapdragon) yet.
- WSL installed. If it isn't, open PowerShell **as administrator**, run
  `wsl --install --no-distribution`, and restart Windows.

## Install

Open PowerShell (your normal user, no admin needed) and run:

```powershell
irm https://raw.githubusercontent.com/noisyloop/btw/main/windows/install-btw.ps1 | iex
```

It:

1. checks WSL, and tells you what to do if it's missing,
2. installs **Arch Linux** from the official WSL image, if you don't have it yet,
3. asks for a Linux user name and password, and turns on systemd in Arch,
4. installs btw with its normal installer, the same one used on Arch and Omarchy,
5. adds `btw-wsl` (the launcher) and a **btw** shortcut, with the triangle icon, to the
   Start menu.

The first run takes a few minutes, mostly downloading Arch and the packages.

## Use

Open **btw** from the Start menu. It opens in a window and uses <kbd>Alt</kbd> where btw
normally uses <kbd>Super</kbd>, because Windows keeps the Windows key:

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
and your Windows files are under `/mnt/c`.

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

- **Nothing opens from the Start menu:** open PowerShell and run `wsl -d archlinux -- btw-wsl`.
  It prints why. btw's own log is in Arch at `~/.local/state/sway.log`.
- **"no WSLg display":** WSLg isn't running. Run `wsl --update`, then `wsl --shutdown`, and
  try again. Check that Linux GUI apps work at all, e.g. `wsl -d archlinux -- foot`.
- **btw is slow:** in a window under WSLg, btw draws on the CPU. That's fine for the desktop
  itself, but heavy apps inside it will feel it.

## How it works

`install-btw.ps1` sets up Arch and runs btw's normal `install.sh` inside it. The Start menu
shortcut runs `wslg.exe -d archlinux -- btw-wsl`. `btw-wsl` points btw at WSLg's display,
which lives in `/mnt/wslg/runtime-dir` while systemd's runtime folder is
`/run/user/<uid>`, and then runs `btw-session` in the foreground. WSL shuts Linux down soon
after nothing started from Windows is running, so btw has to stay in the foreground there.
The rest is unchanged btw.
