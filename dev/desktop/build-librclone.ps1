# Builds rclone as a c-shared library (librclone.dll) for the in-process desktop
# engine (FfiRcloneClient). Windows counterpart of the macOS/Linux build-librclone.sh;
# mirrors dev/android/build-rclone.ps1's dummy-module / go get / env-snapshot pattern.
#
# Two things matter for a BUNDLABLE artifact (vs the throwaway Phase-0 spike):
#   1. Version stamp — a plain module build reports "vX.Y.Z-DEV", which the app's
#      meetsMinRclone() rejects; -X fs.Version=<ver> makes it report clean.
#   2. Static runtime — -extldflags "-static" folds libgcc/libwinpthread INTO the
#      dll so we ship ONE self-contained file (no stray mingw runtime dlls).
#
# Requires: Go 1.24+, a mingw-w64 gcc on PATH (or pass -Gcc). Internet on first run.
# CI equivalent: the librclone build step in .github/workflows/release.yml.
#
# Usage: powershell -File dev\desktop\build-librclone.ps1 [-OutDir <dir>] [-Gcc <path>]
param(
    [string]$RcloneVersion = 'v1.75.0',
    [string]$OutDir = "$(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)\app\windows\librclone",
    [string]$Gcc = ''
)
$ErrorActionPreference = 'Stop'

# Resolve a gcc: explicit -Gcc, else PATH, else the portable WinLibs we fetch to
# a user dir for local dev.
if (-not $Gcc) {
    $onPath = (Get-Command gcc -ErrorAction SilentlyContinue).Source
    $portable = "$env:USERPROFILE\tools\mingw64\bin\gcc.exe"
    if ($onPath) { $Gcc = $onPath }
    elseif (Test-Path $portable) { $Gcc = $portable }
    else { throw 'no gcc found: install mingw-w64 or pass -Gcc <path to gcc.exe>' }
}
$mingwBin = Split-Path $Gcc
if ($Gcc -match ' ') { throw "gcc path contains spaces (cgo cannot handle that): $Gcc" }

$go = 'go'
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    $go = 'C:\Program Files\Go\bin\go.exe'
    if (-not (Test-Path $go)) { throw 'Go not found (install Go 1.24+)' }
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$out = Join-Path $OutDir 'librclone.dll'

# Dummy module pinning the rclone version, kept out of the repo so the module
# cache is reused across runs.
$work = Join-Path $env:USERPROFILE '.airclone-librclone-desktop'
New-Item -ItemType Directory -Force $work | Out-Null

$envNames = 'GOOS', 'GOARCH', 'CGO_ENABLED', 'CC', 'PATH'
$snapshot = @{}
foreach ($n in $envNames) { $snapshot[$n] = [Environment]::GetEnvironmentVariable($n) }

Push-Location $work
try {
    if (-not (Test-Path 'go.mod')) {
        & $go mod init rclone-librclone-build
        if ($LASTEXITCODE -ne 0) { throw 'go mod init failed' }
    }
    & $go get "github.com/rclone/rclone@$RcloneVersion"
    if ($LASTEXITCODE -ne 0) { throw 'go get rclone failed' }

    $env:PATH = "$mingwBin;$env:PATH"
    $env:CGO_ENABLED = '1'
    $env:CC = $Gcc
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'

    Write-Host "== building librclone.dll ($RcloneVersion, static runtime) =="
    # -X stamps the version; -static folds the mingw runtime in; noselfupdate
    # keeps rclone from trying to replace itself.
    & $go build -tags 'noselfupdate' -trimpath `
        -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=$RcloneVersion -extldflags `"-static`"" `
        --buildmode=c-shared -o $out github.com/rclone/rclone/librclone
    if ($LASTEXITCODE -ne 0) { throw 'go build failed' }
}
finally {
    Pop-Location
    foreach ($n in $envNames) { [Environment]::SetEnvironmentVariable($n, $snapshot[$n]) }
}

if (-not (Test-Path $out)) { throw "build ok but $out missing" }
Write-Host ("   -> {0}  {1:N1} MB" -f $out, ((Get-Item $out).Length / 1MB))

# Confirm it is self-contained: no dependency on the mingw runtime dlls.
$objdump = Join-Path $mingwBin 'objdump.exe'
if (Test-Path $objdump) {
    $deps = & $objdump -p $out | Select-String 'DLL Name:' | ForEach-Object { ($_ -split ':')[1].Trim() }
    Write-Host "DLL dependencies: $($deps -join ', ')"
    $bad = $deps | Where-Object { $_ -match 'libwinpthread|libgcc|libstdc' }
    if ($bad) { throw "NOT self-contained - still depends on: $($bad -join ', ')" }
    Write-Host 'self-contained: OK (no mingw runtime deps)'
}
Write-Host 'done.'
