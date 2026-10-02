# One-time setup on the Windows PC by the TV: installs the Gummy Bear
# launcher (Play-GummyBear.ps1) and puts a "Gummy Bear" shortcut on the
# desktop, then starts the game. Paste this into PowerShell:
#
#   irm https://raw.githubusercontent.com/alexnoox/gummybear/main/tools/windows/Install-GummyBear.ps1 | iex
#
# Running it again reinstalls the launcher and shortcut; nothing else changes.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$InstallDir = Join-Path $env:LOCALAPPDATA 'GummyBear'
$Launcher = Join-Path $InstallDir 'Play-GummyBear.ps1'
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Invoke-WebRequest -UseBasicParsing -OutFile $Launcher `
    -Uri 'https://raw.githubusercontent.com/alexnoox/gummybear/main/tools/windows/Play-GummyBear.ps1'

$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcut = $shell.CreateShortcut((Join-Path $desktop 'Gummy Bear.lnk'))
# Windows blocks .ps1 files by default (the Restricted execution policy), so
# both the shortcut and the first run below start the launcher through
# powershell.exe with the policy bypassed for that one process only.
$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$LauncherArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$Launcher`""
$shortcut.TargetPath = $PowerShell
$shortcut.Arguments = $LauncherArgs
$shortcut.WorkingDirectory = $InstallDir
# The game's own icon, once the first run has downloaded it.
$shortcut.IconLocation = "$(Join-Path $InstallDir 'GummyBear.exe'),0"
$shortcut.Save()
Write-Host "Installed. The 'Gummy Bear' shortcut on the desktop gets the newest version and plays it."

Start-Process -FilePath $PowerShell -ArgumentList $LauncherArgs -WorkingDirectory $InstallDir -NoNewWindow -Wait
