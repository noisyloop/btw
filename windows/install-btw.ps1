<#
.SYNOPSIS
  Installs btw on Windows: Arch Linux in WSL, btw inside it, and a "btw"
  shortcut in the Start menu that opens btw in a window (through WSLg).

.DESCRIPTION
  Run it in PowerShell as your normal user (no admin needed if WSL is already
  installed):

    irm https://raw.githubusercontent.com/noisyloop/btw/main/windows/install-btw.ps1 | iex

  It is safe to run again: it skips what's already done and updates btw.

  Steps:
    1. checks for WSL (and says how to install it if it's missing),
    2. installs Arch Linux from the official WSL image, if it isn't there,
    3. sets up a Linux user (you choose the password) and turns on systemd,
    4. installs btw with its normal installer (install.sh),
    5. adds btw-wsl (the Windows launcher) and the Start menu shortcut.

.PARAMETER Distro
  The WSL distribution to use. Default: archlinux.

.PARAMETER Branch
  The btw branch to take the Windows files from (to try a pull request).
  Default: main, or $env:BTW_BRANCH if set.

.PARAMETER Uninstall
  Removes the shortcut, btw-wsl and btw itself from the Linux. Arch Linux
  stays; remove it with: wsl --unregister archlinux (this deletes its files).
  From the one-line install, set $env:BTW_UNINSTALL = "1" first instead.
#>
param(
    [string]$Distro = "archlinux",
    [string]$Branch = "",
    [switch]$Uninstall
)

# Run from `irm ... | iex`, parameters can't be passed; settings come from the
# environment instead ($env:BTW_BRANCH, $env:BTW_UNINSTALL).
if (-not $Branch) { $Branch = $env:BTW_BRANCH }
if ($env:BTW_UNINSTALL) { $Uninstall = $true }
if (-not $Branch) { $Branch = "main" }

$ErrorActionPreference = "Stop"
$env:WSL_UTF8 = "1"   # plain UTF-8 output from wsl.exe, not UTF-16
$Repo = "https://raw.githubusercontent.com/noisyloop/btw"
$Raw = "$Repo/$Branch"
$AppDir = Join-Path $env:LOCALAPPDATA "btw"
$Shortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "btw.lnk"

function Step([string]$Message) { Write-Host ""; Write-Host "==> $Message" -ForegroundColor Green }
function Note([string]$Message) { Write-Host "    $Message" }

# Runs a bash script inside the distribution. The script goes in on stdin,
# with Unix line endings, so nothing in it needs Windows quoting. Windows
# PowerShell ends piped input with a Windows line ending; the comment line at
# the end takes that stray carriage return, so no command gets it.
function Invoke-Linux([string]$Script, [string]$As = "root") {
    $Script = ($Script -replace "`r", "") + "`n# end of script"
    $Script | wsl.exe -d $Distro -u $As -e bash -s
    if ($LASTEXITCODE -ne 0) { throw "a step inside Linux failed (exit code $LASTEXITCODE); see the messages above." }
}

# The Linux user btw runs as: the first regular user (uid 1000), if any.
function Get-LinuxUser {
    $out = ("getent passwd 1000 | cut -d: -f1`n# end of script") | wsl.exe -d $Distro -u root -e bash -s
    return ($out | Out-String).Trim()
}

function Get-Distros {
    $list = wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($list | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Uninstall-Btw {
    Step "Removing btw"
    if (Test-Path $Shortcut) { Remove-Item $Shortcut -Force; Note "removed the Start menu shortcut" }
    if (Test-Path $AppDir) { Remove-Item $AppDir -Recurse -Force }
    if ((Get-Distros) -contains $Distro) {
        $user = Get-LinuxUser
        Invoke-Linux "rm -f /usr/local/bin/btw-wsl"
        if ($user) {
            Invoke-Linux "echo '$user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-btw-setup && chmod 440 /etc/sudoers.d/90-btw-setup"
            try {
                Invoke-Linux "set -o pipefail; curl -fsSL $Repo/main/install.sh | bash -s -- --uninstall" -As $user
            } finally {
                Invoke-Linux "rm -f /etc/sudoers.d/90-btw-setup"
            }
        }
    }
    Note "Done. Arch Linux is still installed; to remove it and all its files:"
    Note "  wsl --unregister $Distro"
}

function Install-Btw {
    # 1. Windows and WSL ---------------------------------------------------
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ("$arch" -eq "Arm64") {
        throw "Arch Linux's WSL image is for x86-64 PCs only, and this PC is ARM. On ARM, btw needs another distribution; that isn't supported yet."
    }

    Step "Checking WSL"
    wsl.exe --version *> $null
    if ($LASTEXITCODE -ne 0) {
        if (Test-Admin) {
            Note "WSL isn't installed; installing it now."
            wsl.exe --install --no-distribution
            Note ""
            Note "Restart Windows, then run this installer again."
            return
        }
        throw "WSL isn't installed. Open PowerShell as administrator, run: wsl --install --no-distribution  then restart Windows and run this installer again."
    }
    Note "WSL is installed."

    # 2. Arch Linux --------------------------------------------------------
    if ((Get-Distros) -notcontains $Distro) {
        if ($Distro -ne "archlinux") { throw "there's no WSL distribution called $Distro." }
        Step "Installing Arch Linux (the official WSL image)"
        wsl.exe --install --distribution archlinux --no-launch
        if ($LASTEXITCODE -ne 0) { throw "WSL couldn't install Arch Linux. Try: wsl --update  then run this again." }
        if ((Get-Distros) -notcontains $Distro) { throw "Arch Linux was downloaded but isn't registered; open it once from the Start menu, close it, and run this again." }
    } else {
        Note "Arch Linux is installed."
    }

    # 3. Linux user, packages, systemd --------------------------------------
    $user = Get-LinuxUser
    $newUser = $false
    if (-not $user) {
        $suggested = ($env:USERNAME.ToLower() -replace "[^a-z0-9_-]", "")
        if ($suggested -notmatch "^[a-z_]") { $suggested = "btw" }
        Write-Host ""
        $answer = Read-Host "Choose a Linux user name for btw [$suggested]"
        if ($answer) { $user = $answer.Trim().ToLower() } else { $user = $suggested }
        if ($user -notmatch "^[a-z_][a-z0-9_-]{0,31}$") { throw "'$user' isn't a valid Linux user name (lowercase letters, digits, - and _)." }
        $newUser = $true
    }

    Step "Setting up Arch Linux (packages, user $user, systemd)"
    Invoke-Linux @"
set -e
# The official image leaves the package keys to be set up on first use.
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
pacman -Syu --noconfirm --needed sudo git curl
id -u $user >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash $user
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
# Log in as $user by default, and run systemd (btw's session uses it).
touch /etc/wsl.conf
grep -q '^\[user\]' /etc/wsl.conf || printf '\n[user]\ndefault=$user\n' >> /etc/wsl.conf
grep -q '^systemd=' /etc/wsl.conf || printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf
"@

    if ($newUser) {
        Write-Host ""
        Write-Host "Choose a password for $user (Linux asks for it when installing software):"
        do {
            wsl.exe -d $Distro -u root -e passwd $user
        } while ($LASTEXITCODE -ne 0)
    }

    # Restart the distribution so the default user and systemd take effect.
    wsl.exe --terminate $Distro *> $null

    # 4. btw ---------------------------------------------------------------
    Step "Installing btw"
    # install.sh asks sudo for a password, which can't be typed through this
    # window; allow it without one just for the install, then take that back.
    Invoke-Linux "echo '$user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-btw-setup && chmod 440 /etc/sudoers.d/90-btw-setup"
    try {
        Invoke-Linux "set -o pipefail; cd ~ && curl -fsSL $Repo/main/install.sh | bash" -As $user
    } finally {
        Invoke-Linux "rm -f /etc/sudoers.d/90-btw-setup"
    }

    # 5. Windows launcher -------------------------------------------------
    Step "Adding btw to the Start menu"
    Invoke-Linux "curl -fsSL $Raw/windows/btw-wsl -o /usr/local/bin/btw-wsl && chmod 755 /usr/local/bin/btw-wsl"

    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    $icon = Join-Path $AppDir "btw.ico"
    Invoke-WebRequest -UseBasicParsing -Uri "$Raw/windows/btw.ico" -OutFile $icon

    # wslg.exe starts Linux GUI apps without a console window; older WSL has
    # only wsl.exe, which then runs minimized.
    $wslg = Join-Path $env:ProgramFiles "WSL\wslg.exe"
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($Shortcut)
    if (Test-Path $wslg) {
        $link.TargetPath = $wslg
        $link.WindowStyle = 1
    } else {
        $link.TargetPath = Join-Path $env:SystemRoot "System32\wsl.exe"
        $link.WindowStyle = 7
    }
    $link.Arguments = "-d $Distro --cd ~ -- btw-wsl"
    $link.IconLocation = "$icon,0"
    $link.Description = "btw desktop, in Arch Linux on WSL"
    $link.Save()
    Note "Start menu: btw"

    Invoke-Linux "test -d /mnt/wslg" -As $user
    Step "Done"
    Note "Open btw from the Start menu (search for btw)."
    Note "It opens in a window and uses Alt where btw uses Super:"
    Note "  Alt+D apps, Alt+Enter terminal, Alt+Shift+B btw shell, Alt+Shift+E close."
    Note "(Alt+Space may open Windows' own window menu instead, so use Alt+D.)"
    Note ""
    Note "Update btw later: run this installer again."
    Note "Remove it: run it with -Uninstall (see windows/README.md)."
}

try {
    if ($Uninstall) { Uninstall-Btw } else { Install-Btw }
} catch {
    Write-Host ""
    Write-Host "btw: $($_.Exception.Message)" -ForegroundColor Red
}
