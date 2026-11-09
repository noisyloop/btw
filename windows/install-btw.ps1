<#
.SYNOPSIS
  Installs btw on Windows: Arch Linux in WSL, btw inside it, and a "btw"
  shortcut in the Start menu that opens btw in a window (through WSLg).

.DESCRIPTION
  Run it in PowerShell as your normal user:

    irm https://raw.githubusercontent.com/noisyloop/btw/main/windows/install-btw.ps1 | iex

  It asks nothing. When Windows needs an administrator's OK (to install or
  update WSL), Windows asks for it. If WSL needs a restart, the installer
  carries on by itself after you log back in. Running it again updates btw.

  Steps:
    1. WSL: installs or updates it when needed (version 2.4.4 or newer),
    2. Arch Linux, from the official WSL image,
    3. a Linux user named after yours, sudo, systemd (btw's welcome terminal
       has you choose the user's password; sudo asks for it),
    4. btw, with its normal installer (install.sh),
    5. the Start menu shortcut, then a check that btw can open.

  Everything is logged to %LOCALAPPDATA%\btw\install.log.

.PARAMETER Distro
  The WSL distribution to use. Default: archlinux.

.PARAMETER Branch
  The btw branch to install (to try a pull request). Default: main, or
  $env:BTW_BRANCH if set.

.PARAMETER Uninstall
  Removes the shortcut and btw from the Linux. Arch Linux stays; remove it
  with: wsl --unregister archlinux (this deletes its files). From the
  one-line install, set $env:BTW_UNINSTALL = "1" first instead.
#>
param(
    [string]$Distro = "archlinux",
    [string]$Branch = "",
    [switch]$Uninstall
)

# Run from `irm ... | iex`, parameters can't be passed; settings come from the
# environment instead ($env:BTW_BRANCH, $env:BTW_UNINSTALL).
if (-not $Branch) { $Branch = $env:BTW_BRANCH }
if (-not $Branch) { $Branch = "main" }
if ($env:BTW_UNINSTALL) { $Uninstall = $true }

# Errors are handled by hand. Windows PowerShell 5.1 turns anything a program
# writes to stderr into a terminating error when this is "Stop", and wsl.exe
# writes plenty there, so programs run through Invoke-Native below, which
# looks at their exit codes instead.
$ErrorActionPreference = "Continue"
$env:WSL_UTF8 = "1"   # plain UTF-8 output from wsl.exe, not UTF-16
$Raw = "https://raw.githubusercontent.com/noisyloop/btw/$Branch"
$AppDir = Join-Path $env:LOCALAPPDATA "btw"
$Log = Join-Path $AppDir "install.log"
$Shortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "btw.lnk"
$ResumeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
$MinWsl = [version]"2.4.4"   # the first WSL with `wsl --install archlinux`

New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

function Log([string]$Text) {
    Add-Content -Path $Log -Value $Text -Encoding UTF8
}
function Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Green
    Log ""
    Log "==> $Message ($(Get-Date -Format s))"
}
function Note([string]$Message) {
    Write-Host "    $Message"
    Log "    $Message"
}
# Stops the install with a message; the catch at the bottom says where the
# log is.
function Fail([string]$Message) {
    throw $Message
}

# Runs a program and returns its exit code and output, never throwing on
# stderr. With -Show, its output also streams to the window as it runs, so a
# long step doesn't look stuck. Output is stdout only; stderr (where wsl.exe
# puts its own warnings) is in Errors, and in the log either way.
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [string]$InputText, [switch]$Show)
    Log "> $Exe $($Arguments -join ' ')"
    $lines = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]
    $handle = {
        $isError = $_ -is [System.Management.Automation.ErrorRecord]
        $line = ("$_" -replace "`0", "").TrimEnd()
        if ($line) {
            if ($isError) { $errors.Add($line) } else { $lines.Add($line) }
            Log $line
            if ($Show) { Write-Host "    $line" -ForegroundColor DarkGray }
        }
    }
    if ($PSBoundParameters.ContainsKey("InputText")) {
        $InputText | & $Exe @Arguments 2>&1 | ForEach-Object $handle
    } else {
        & $Exe @Arguments 2>&1 | ForEach-Object $handle
    }
    $code = $LASTEXITCODE
    Log "< exit $code"
    return [pscustomobject]@{ Code = $code; Output = ($lines -join "`n"); Errors = ($errors -join "`n") }
}

# Runs a bash script inside the distribution. The script goes in on stdin,
# with Unix line endings, so nothing in it needs Windows quoting. Windows
# PowerShell ends piped input with a Windows line ending; the comment line at
# the end takes that stray carriage return, so no command gets it.
function Invoke-Linux([string]$Script, [string]$As = "root", [switch]$Show) {
    $Script = ($Script -replace "`r", "") + "`n# end of script"
    return Invoke-Native wsl.exe @("-d", $Distro, "-u", $As, "-e", "bash", "-s") -InputText $Script -Show:$Show
}

# A program run as administrator: Windows shows its usual prompt. Returns the
# exit code, or $null if the prompt was declined.
function Invoke-Elevated([string]$Exe, [string]$Arguments) {
    Log "> (as administrator) $Exe $Arguments"
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop
        Log "< exit $($p.ExitCode)"
        return $p.ExitCode
    } catch {
        Log "< declined: $($_.Exception.Message)"
        return $null
    }
}

function Get-Distros {
    $r = Invoke-Native wsl.exe @("-l", "-q")
    if ($r.Code -ne 0) { return @() }
    return @($r.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# The installed WSL's version, or $null for none (or the old one built into
# Windows, which has no --version and can't install Arch).
function Get-WslVersion {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $null }
    $r = Invoke-Native wsl.exe @("--version")
    if ($r.Code -ne 0) { return $null }
    # The first line is the WSL version, in every language: "WSL version: 2.5.9.0".
    if ($r.Output -match "(\d+)\.(\d+)\.(\d+)") { return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    return $null
}

# Carries the install on after a restart: once, at the next login.
function Set-Resume {
    $cmd = "powershell.exe -NoExit -ExecutionPolicy Bypass -Command `"`$env:BTW_BRANCH='$Branch'; irm $Raw/windows/install-btw.ps1 | iex`""
    New-ItemProperty -Path $ResumeKey -Name "btw-install" -Value $cmd -PropertyType String -Force | Out-Null
}
function Clear-Resume {
    Remove-ItemProperty -Path $ResumeKey -Name "btw-install" -ErrorAction SilentlyContinue
}

function Get-LinuxUser {
    $r = Invoke-Linux "getent passwd 1000 | cut -d: -f1"
    return $r.Output.Trim()
}

# --- install ------------------------------------------------------------------

function Install-Wsl {
    Step "Checking WSL"
    $v = Get-WslVersion
    if ($v -and $v -ge $MinWsl) {
        Note "WSL $v is installed."
        return $true
    }
    if ($v) {
        Note "WSL $v is too old for Arch Linux; updating it. Windows asks for permission: choose Yes."
        $code = Invoke-Elevated "wsl.exe" "--update"
    } else {
        Note "WSL isn't installed (or is the old one built into Windows); installing it."
        Note "Windows asks for permission: choose Yes."
        $code = Invoke-Elevated "wsl.exe" "--install --no-distribution"
    }
    if ($null -eq $code) {
        Fail "btw needs WSL, and installing it needs an administrator's OK, which was declined. Run this again and choose Yes."
    }
    $v = Get-WslVersion
    if ($v -and $v -ge $MinWsl) {
        Note "WSL $v is ready."
        return $true
    }
    # A fresh WSL (turning on Windows features) only works after a restart.
    Set-Resume
    Step "Restart Windows"
    Note "WSL is installed, but Windows has to restart before it works."
    Note "Restart now. After you log back in, the btw installer opens and carries on by itself."
    return $false
}

function Install-Arch {
    if ((Get-Distros) -contains $Distro) {
        Note "Arch Linux is installed."
        return
    }
    if ($Distro -ne "archlinux") { Fail "there's no WSL distribution called $Distro." }
    Step "Installing Arch Linux (the official WSL image, about 150 MB)"
    $r = Invoke-Native wsl.exe @("--install", "-d", "archlinux", "--no-launch") -Show
    if ("$($r.Output)`n$($r.Errors)" -match "HCS_E_HYPERV_NOT_INSTALLED|0x80370102|Virtual Machine Platform|virtuali[sz]ation") {
        Fail "WSL can't start Linux because virtualization is off. Turn on virtualization (Intel VT-x or AMD-V/SVM) in your PC's BIOS or UEFI settings, then run this again."
    }
    if ((Get-Distros) -notcontains $Distro) {
        Fail "WSL couldn't install Arch Linux. Try running: wsl --update  then run this again."
    }
    Note "Arch Linux is installed."
}

function Install-LinuxSetup([string]$User) {
    Step "Setting up Arch Linux (user $User, sudo, systemd, base packages)"
    # sudo without a password only while this installer runs (btw's own
    # installer uses sudo): Protect-LinuxSudo takes it away at the end, and
    # btw's welcome terminal then has you choose a password.
    $r = Invoke-Linux -Show @"
set -e
# The official image leaves the package keys to be set up on first use.
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
pacman -Syu --noconfirm --needed sudo git curl
id -u $User >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash $User
# Named to sort after 10-btw: sudo goes by the last rule that matches. The
# rule also ends by itself after two hours, in case this installer is closed
# before it can take it away.
echo "$User ALL=(ALL:ALL) NOTAFTER=`$(date -u -d '+2 hours' +%Y%m%d%H%M%SZ) NOPASSWD: ALL" > /etc/sudoers.d/zz-btw-install
chmod 440 /etc/sudoers.d/zz-btw-install
visudo -cf /etc/sudoers.d/zz-btw-install >/dev/null
# Log in as $User by default, and run systemd (btw's session uses it).
touch /etc/wsl.conf
grep -q '^default=' /etc/wsl.conf || printf '\n[user]\ndefault=$User\n' >> /etc/wsl.conf
grep -q '^systemd=' /etc/wsl.conf || printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf
"@
    if ($r.Code -ne 0) { Fail "setting up Arch Linux failed (see the log)." }
    # Restart the distribution so the default user and systemd take effect.
    Invoke-Native wsl.exe @("--terminate", $Distro) | Out-Null
}

# Ends sudo without a password: sudo asks for the user's password from here
# on. A user with no password yet (a new install, or one from an older btw,
# which had none) can't sudo or log in with one until they choose it: btw's
# welcome terminal asks, through set-password, the one command sudo allows
# without a password, and only until a password is chosen.
function Protect-LinuxSudo([string]$User) {
    $r = Invoke-Linux @"
set -e
rm -f /etc/sudoers.d/zz-btw-install
cat > /etc/sudoers.d/10-btw <<'SUDOERS'
%wheel ALL=(ALL:ALL) ALL
$User ALL=(root) NOPASSWD: /usr/local/lib/btw/set-password ""
SUDOERS
chmod 440 /etc/sudoers.d/10-btw
if [ "`$(passwd -S $User | cut -d' ' -f2)" != P ]; then
    usermod -p '!' $User
    install -d -m 755 /var/lib/btw
    echo $User > /var/lib/btw/choose-password
fi
"@
    return ($r.Code -eq 0)
}

function Install-BtwLinux([string]$User) {
    Step "Installing btw (packages, btw and its apps; this takes a few minutes)"
    $r = Invoke-Linux -As $User -Show "set -o pipefail; cd ~ && curl -fsSL $Raw/install.sh | BTW_BRANCH=$Branch bash"
    if ($r.Code -ne 0) { Fail "btw's installer failed inside Linux (see the log)." }
    $r = Invoke-Linux "curl -fsSL $Raw/windows/btw-wsl -o /usr/local/bin/btw-wsl && chmod 755 /usr/local/bin/btw-wsl"
    if ($r.Code -ne 0) { Fail "couldn't fetch btw-wsl, the launcher (see the log)." }
}

function Install-Shortcut {
    Step "Adding btw to the Start menu"
    $icon = Join-Path $AppDir "btw.ico"
    $launcher = Join-Path $AppDir "open-btw.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri "$Raw/windows/btw.ico" -OutFile $icon
    Invoke-WebRequest -UseBasicParsing -Uri "$Raw/windows/open-btw.ps1" -OutFile $launcher
    # open-btw.ps1 starts btw, and if it can't open, says why in a message box
    # (btw itself runs without a console window, so its errors would be lost).
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($Shortcut)
    $link.TargetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -Distro $Distro"
    $link.WindowStyle = 7
    $link.IconLocation = "$icon,0"
    $link.Description = "btw desktop, in Arch Linux on WSL"
    $link.Save()
    Note "Start menu: btw"
}

function Test-Btw([string]$User) {
    Step "Checking that btw can open"
    $r = Invoke-Linux -As $User -Show "btw-wsl --check"
    if ($r.Code -ne 0) {
        Fail "btw is installed, but it can't open a window yet (see the messages above)."
    }
}

function Install-Btw {
    Log "btw install, branch $Branch, $(Get-Date -Format s)"
    Log "Windows $([Environment]::OSVersion.Version), PowerShell $($PSVersionTable.PSVersion)"
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ("$arch" -eq "Arm64") {
        Fail "Arch Linux's WSL image is for x86-64 PCs only, and this PC is ARM. btw on ARM PCs isn't supported yet."
    }
    if (-not (Install-Wsl)) { return }
    Clear-Resume
    Install-Arch

    $user = Get-LinuxUser
    if (-not $user) {
        $user = ($env:USERNAME.ToLower() -replace "[^a-z0-9_-]", "")
        if ($user -notmatch "^[a-z_][a-z0-9_-]{0,31}$") { $user = "btw" }
    }
    $script:SudoOpenFor = $user
    Install-LinuxSetup $user
    Install-BtwLinux $user
    if (-not (Protect-LinuxSudo $user)) { Fail "couldn't turn sudo's password back on (see the log)." }
    $script:SudoOpenFor = $null
    Install-Shortcut
    Test-Btw $user

    Step "Done: opening btw"
    Note "Next time, open btw from the Start menu (search for btw)."
    Note "In its window, Alt does what the Windows key does in btw:"
    Note "  Alt+D apps, Alt+Enter terminal, Alt+Shift+E close."
    Note "The first time, btw's terminal asks you to choose a password: sudo asks for it."
    Note "Update btw later: run this installer again, or btw update inside btw."
    Start-Process -FilePath $Shortcut
}

function Uninstall-Btw {
    Step "Removing btw"
    Clear-Resume
    if (Test-Path $Shortcut) { Remove-Item $Shortcut -Force; Note "removed the Start menu shortcut" }
    if ((Get-Distros) -contains $Distro) {
        $user = Get-LinuxUser
        Invoke-Linux "rm -f /usr/local/bin/btw-wsl" | Out-Null
        if ($user) {
            Invoke-Linux -As $user -Show "set -o pipefail; curl -fsSL $Raw/install.sh | bash -s -- --uninstall" | Out-Null
        }
    }
    Note "Done. Arch Linux is still installed; to remove it and all its files:"
    Note "  wsl --unregister $Distro"
    Note "(The install log stays in $AppDir.)"
}

try {
    if ($Uninstall) { Uninstall-Btw } else { Install-Btw }
} catch {
    Write-Host ""
    Write-Host "btw: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "The full log is in $Log; it shows what went wrong." -ForegroundColor Red
    Log "FAILED: $($_.Exception.Message)"
    # Never leave sudo without a password behind a failed install.
    if ($script:SudoOpenFor) {
        if (-not (Protect-LinuxSudo $script:SudoOpenFor)) {
            Write-Host "sudo in Arch Linux may still work without a password; run this installer again to fix that." -ForegroundColor Red
        }
    }
}
