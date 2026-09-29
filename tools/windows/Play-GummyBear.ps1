# Gummy Bear launcher for the Windows PC by the TV (the desktop shortcut runs
# it). Fetches the newest build from GitHub, the "windows-latest" release
# that CI publishes on every push to main, if it has changed, then starts the
# game (full screen). Offline, or if GitHub can't be reached, it plays the
# copy it already has.

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1: GitHub needs TLS 1.2, and the progress bar makes
# downloads crawl.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$Repo = 'alexnoox/gummybear'
$Tag = 'windows-latest'
$InstallDir = Join-Path $env:LOCALAPPDATA 'GummyBear'
$Exe = Join-Path $InstallDir 'GummyBear.exe'
# The release asset id of the build in $Exe; a new release means a new id.
$Stamp = Join-Path $InstallDir 'build-id.txt'

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Host 'Looking for the newest Gummy Bear...'
try {
    $release = Invoke-RestMethod -TimeoutSec 15 `
        -Headers @{ 'User-Agent' = 'GummyBearLauncher' } `
        -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    $asset = $release.assets | Where-Object { $_.name -eq 'GummyBear.exe' } | Select-Object -First 1
    $current = if (Test-Path $Stamp) { (Get-Content $Stamp -Raw).Trim() } else { '' }
    if ($asset -and ("$($asset.id)" -ne $current -or -not (Test-Path $Exe))) {
        Write-Host 'Downloading the new version...'
        $download = "$Exe.download"
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 900 `
            -Uri $asset.browser_download_url -OutFile $download
        Move-Item -Force $download $Exe
        Unblock-File $Exe
        Set-Content -Path $Stamp -Value $asset.id
    }
} catch {
    Write-Host "Couldn't update ($($_.Exception.Message)); playing the copy we have."
}

if (Test-Path $Exe) {
    Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
} else {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "Gummy Bear couldn't be downloaded. Check the internet connection and try again.",
        'Gummy Bear') | Out-Null
}
