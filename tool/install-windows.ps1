<#
.SYNOPSIS
  Install OR upgrade the Airclone Windows build at %LOCALAPPDATA%\Programs\Airclone.
  Re-running with a newer -Tag performs a proper in-place upgrade: it stops the running
  app, swaps the binaries, and relaunches — while KEEPING your rclone config and the
  already-provisioned engine. Per-user, no admin required.

.EXAMPLE
  ./tool/install-windows.ps1 -Tag v0.1.0-alpha.2     # install
  ./tool/install-windows.ps1 -Tag v0.1.0-alpha.3     # upgrade in place
  ./tool/install-windows.ps1 -LocalBuild app/build/windows/x64/runner/Release
#>
param(
  [string]$Tag = 'latest',
  [string]$LocalBuild = '',
  [switch]$NoLaunch,
  [switch]$NoSeedEngine,      # don't provision rclone at all
  [switch]$ForceSeedEngine    # re-download rclone even if already present
)
$ErrorActionPreference = 'Stop'
$install = Join-Path $env:LOCALAPPDATA 'Programs\Airclone'
$marker = Join-Path $install 'AIRCLONE_VERSION.txt'
$staging = Join-Path $env:TEMP ('airclone-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $staging | Out-Null
$verMark = if ($LocalBuild) { 'local-build' } else { $Tag }

# ── detect current version (for upgrade messaging) ───────────────────────────
$current = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { '' }
if ($current) { Write-Output "Upgrading Airclone: $current -> $verMark" }
else { Write-Output "Installing Airclone: $verMark" }

# ── stop any running instance, then replace the app dir ──────────────────────
Get-Process airclone -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600
if (Test-Path $install) { Remove-Item -Recurse -Force $install }
New-Item -ItemType Directory -Force $install | Out-Null

if ($LocalBuild) {
  Copy-Item -Recurse -Force (Join-Path (Resolve-Path $LocalBuild) '*') $install
} else {
  $url = if ($Tag -eq 'latest') {
    'https://github.com/GigaionLLC/Airclone/releases/latest/download/airclone-windows-x64.zip'
  } else {
    "https://github.com/GigaionLLC/Airclone/releases/download/$Tag/airclone-windows-x64.zip"
  }
  Write-Output "Downloading $url"
  $zip = Join-Path $staging 'app.zip'
  Invoke-WebRequest -Uri $url -OutFile $zip
  Unblock-File $zip
  Expand-Archive -Path $zip -DestinationPath $install -Force
}
Get-ChildItem -Recurse $install | Unblock-File -ErrorAction SilentlyContinue
$exe = (Get-ChildItem -Path $install -Filter 'airclone.exe' -Recurse | Select-Object -First 1).FullName
if (-not $exe) { throw "airclone.exe not found in $install" }
Set-Content -Path $marker -Value $verMark -Encoding utf8
Write-Output "Installed to: $install"

# ── ensure the rclone engine is provisioned (kept across upgrades) ───────────
if (-not $NoSeedEngine) {
  $vi = (Get-Item $exe).VersionInfo
  $company = if ($vi.CompanyName) { $vi.CompanyName } else { 'com.example' }
  $product = if ($vi.ProductName) { $vi.ProductName } else { 'airclone' }
  $engineDir = Join-Path (Join-Path $env:APPDATA (Join-Path $company $product)) 'engine'
  $managed = Join-Path $engineDir 'rclone.exe'
  if ((Test-Path $managed) -and -not $ForceSeedEngine) {
    Write-Output "rclone engine already present (kept): $managed"
  } else {
    New-Item -ItemType Directory -Force $engineDir | Out-Null
    Write-Output "Provisioning rclone engine -> $engineDir"
    $rz = Join-Path $staging 'rclone.zip'
    Invoke-WebRequest -Uri 'https://downloads.rclone.org/rclone-current-windows-amd64.zip' -OutFile $rz
    Unblock-File $rz
    $rd = Join-Path $staging 'rclone'; Expand-Archive -Path $rz -DestinationPath $rd -Force
    $rcExe = (Get-ChildItem -Path $rd -Filter 'rclone.exe' -Recurse | Select-Object -First 1).FullName
    Copy-Item $rcExe $managed -Force
  }
}

# ── Start-Menu shortcut ──────────────────────────────────────────────────────
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Airclone.lnk'
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($startMenu)
$lnk.TargetPath = $exe; $lnk.WorkingDirectory = $install
$lnk.IconLocation = "$exe,0"; $lnk.Description = 'Airclone — a modern GUI for rclone'
$lnk.Save()

Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
if (-not $NoLaunch) { Start-Process -FilePath $exe | Out-Null; Write-Output 'Launched Airclone.' }
Write-Output 'Done.'
