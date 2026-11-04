<#
.SYNOPSIS
  Opens btw: what the btw shortcut in the Start menu runs.

.DESCRIPTION
  Starts btw-wsl in Arch Linux (WSL), which opens btw in a window through
  WSLg. btw has no console window, so if it can't open, this shows why in a
  message box instead of failing silently. install-btw.ps1 puts it in
  %LOCALAPPDATA%\btw.
#>
param([string]$Distro = "archlinux")

$ErrorActionPreference = "Continue"
$env:WSL_UTF8 = "1"
$Log = Join-Path $env:LOCALAPPDATA "btw\open-btw.log"

# btw-wsl stays running while btw is open, and prints only when something is
# wrong; keep its last lines for the message.
$out = & wsl.exe -d $Distro -- btw-wsl 2>&1 | ForEach-Object { ("$_" -replace "`0", "").TrimEnd() }
$code = $LASTEXITCODE
Set-Content -Path $Log -Value (@("exit $code") + $out) -Encoding UTF8

if ($code -ne 0) {
    $why = ($out | Where-Object { $_ } | Select-Object -Last 8) -join "`n"
    if (-not $why) { $why = "wsl.exe exited with code $code." }
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "btw couldn't open.`n`n$why`n`nThe details are in $Log. Running the btw installer again often fixes it.",
        "btw", "OK", "Warning") | Out-Null
}
