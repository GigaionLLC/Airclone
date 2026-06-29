<#
.SYNOPSIS
  Download (or use a local build of) the Airclone Windows app, launch it, screenshot
  its window, and clean up. A visual smoke-test harness for alpha builds.

.EXAMPLE
  ./tool/run-windows.ps1 -Tag v0.1.0-alpha.2 -ProvisionRclone -Shot out.png
  ./tool/run-windows.ps1 -LocalBuild app/build/windows/x64/runner/Release -KeepOpen
#>
param(
  [string]$Tag = 'latest',                # GitHub release tag, or 'latest'
  [string]$LocalBuild = '',               # use a local build dir instead of downloading
  [string]$Shot = '',                     # screenshot output path (default: temp)
  [switch]$ProvisionRclone,               # put rclone on PATH so the engine auto-starts
  [switch]$KeepOpen,                       # leave the app running after the screenshot
  [int]$WaitSeconds = 12                   # how long to wait for the window before capturing
)
$ErrorActionPreference = 'Stop'
$work = Join-Path $env:TEMP ("airclone-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

# ── obtain the app ───────────────────────────────────────────────────────────
if ($LocalBuild) {
  $appDir = (Resolve-Path $LocalBuild).Path
} else {
  $url = if ($Tag -eq 'latest') {
    'https://github.com/GigaionLLC/Airclone/releases/latest/download/airclone-windows-x64.zip'
  } else {
    "https://github.com/GigaionLLC/Airclone/releases/download/$Tag/airclone-windows-x64.zip"
  }
  Write-Output "Downloading $url"
  $zip = Join-Path $work 'app.zip'
  Invoke-WebRequest -Uri $url -OutFile $zip
  Unblock-File $zip
  $appDir = Join-Path $work 'app'
  Expand-Archive -Path $zip -DestinationPath $appDir -Force
  Get-ChildItem -Recurse $appDir | Unblock-File -ErrorAction SilentlyContinue
}
$exe = (Get-ChildItem -Path $appDir -Filter 'airclone.exe' -Recurse | Select-Object -First 1).FullName
if (-not $exe) { throw "airclone.exe not found under $appDir" }

# ── optionally pre-provision rclone on PATH (skips the first-run setup gate) ──
if ($ProvisionRclone) {
  Write-Output 'Provisioning rclone on PATH...'
  $rcZip = Join-Path $work 'rclone.zip'
  Invoke-WebRequest -Uri 'https://downloads.rclone.org/rclone-current-windows-amd64.zip' -OutFile $rcZip
  Unblock-File $rcZip
  $rcDir = Join-Path $work 'rclone'
  Expand-Archive -Path $rcZip -DestinationPath $rcDir -Force
  $rcExe = (Get-ChildItem -Path $rcDir -Filter 'rclone.exe' -Recurse | Select-Object -First 1).FullName
  $env:PATH = (Split-Path $rcExe) + ';' + $env:PATH   # child process inherits this
}

# ── launch ───────────────────────────────────────────────────────────────────
Write-Output "Launching: $exe"
$proc = Start-Process -FilePath $exe -PassThru

Add-Type @"
using System; using System.Runtime.InteropServices;
public struct RECT { public int Left, Top, Right, Bottom; }
public class Win {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
}
"@
Add-Type -AssemblyName System.Drawing

$h = [IntPtr]::Zero
for ($i = 0; $i -lt $WaitSeconds; $i++) {
  Start-Sleep -Seconds 1
  $p = Get-Process -Name airclone -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($p) { $h = $p.MainWindowHandle; break }
}
if ($h -eq [IntPtr]::Zero) {
  Write-Output 'RESULT: no window appeared (exe may have failed to start).'
} else {
  [Win]::ShowWindow($h, 9) | Out-Null
  [Win]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Seconds 3
  $r = New-Object RECT
  # DWMWA_EXTENDED_FRAME_BOUNDS = 9 → tight bounds without the drop-shadow margin
  if ([Win]::DwmGetWindowAttribute($h, 9, [ref]$r, 16) -ne 0) { [Win]::GetWindowRect($h, [ref]$r) | Out-Null }
  $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
  if ($w -gt 0 -and $hh -gt 0) {
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    if (-not $Shot) { $Shot = Join-Path $work 'shot.png' }
    $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "SHOT: $Shot ($w x $hh)"
  }
}

if (-not $KeepOpen) {
  Start-Sleep -Seconds 1
  taskkill /PID $proc.Id /T /F 2>$null | Out-Null
  Write-Output 'Cleaned up (process terminated).'
} else {
  Write-Output ("App left running, PID " + $proc.Id)
}
