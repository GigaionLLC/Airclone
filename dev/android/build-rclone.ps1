# Cross-compiles rclone for Android and drops the per-ABI executables into
# app/android/app/src/main/jniLibs/<abi>/librclone.so, where gradle packages
# them as (fake) JNI libraries. useLegacyPackaging=true in build.gradle.kts
# makes the installer extract them to nativeLibraryDir, the one location
# Android still permits exec() from (W^X, targetSdk 29+). The app then spawns
# `librclone.so rcd` exactly like the desktop engine.
#
# Requires: Go 1.24+, the Android NDK (path below), internet (module fetch).
# CI equivalent lives in .github/workflows/release.yml (android job).
#
# Usage: powershell -File dev\android\build-rclone.ps1 [-Abis arm64-v8a,x86_64]
param(
    # Flutter's Android release ABIs. x86 (32-bit) is intentionally absent.
    [string[]]$Abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64'),
    [string]$RcloneVersion = 'v1.74.3',
    [string]$NdkRoot = "$env:USERPROFILE\android-sdk\ndk\28.2.13676358",
    # Must be <= the app's minSdk (flutter.minSdkVersion; 24 as of Flutter 3.44).
    [int]$ApiLevel = 24
)
$ErrorActionPreference = 'Stop'

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$jniLibs = Join-Path $repo 'app\android\app\src\main\jniLibs'
$ndkBin = Join-Path $NdkRoot 'toolchains\llvm\prebuilt\windows-x86_64\bin'
if (-not (Test-Path $ndkBin)) { throw "NDK toolchain not found: $ndkBin" }
if ($ndkBin -match ' ') {
    # cgo splits $env:CC on whitespace, so a spaced path silently breaks the
    # compile. Install the NDK under a space-free prefix instead.
    throw "NDK path contains spaces (cgo cannot handle that): $ndkBin"
}

$go = 'go'
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    $go = 'C:\Program Files\Go\bin\go.exe'
    if (-not (Test-Path $go)) { throw 'Go not found (install Go 1.24+)' }
}

# A dummy module pinning the rclone version; kept outside the repo so the Go
# module cache is reused across runs.
$work = Join-Path $env:USERPROFILE '.airclone-rclone-android'
New-Item -ItemType Directory -Force $work | Out-Null

# Snapshot the build env vars so an interactive session gets them back exactly
# as they were (deleting them outright would clobber a user's own GOOS etc.).
$envNames = 'GOOS', 'GOARCH', 'CGO_ENABLED', 'CC', 'CGO_LDFLAGS', 'GOARM'
$envSnapshot = @{}
foreach ($n in $envNames) { $envSnapshot[$n] = [Environment]::GetEnvironmentVariable($n) }

Push-Location $work
try {
    if (-not (Test-Path 'go.mod')) {
        & $go mod init rclone-android-build
        if ($LASTEXITCODE -ne 0) { throw 'go mod init failed' }
    }
    & $go get "github.com/rclone/rclone@$RcloneVersion"
    if ($LASTEXITCODE -ne 0) { throw 'go get rclone failed' }

    # GOARCH + NDK clang wrapper per Android ABI.
    $targets = @{
        'arm64-v8a'   = @{ goarch = 'arm64'; cc = "aarch64-linux-android$ApiLevel-clang.cmd"; goarm = $null }
        'armeabi-v7a' = @{ goarch = 'arm';   cc = "armv7a-linux-androideabi$ApiLevel-clang.cmd"; goarm = '7' }
        'x86_64'      = @{ goarch = 'amd64'; cc = "x86_64-linux-android$ApiLevel-clang.cmd"; goarm = $null }
    }

    foreach ($abi in $Abis) {
        $t = $targets[$abi]
        if ($null -eq $t) { throw "unknown ABI: $abi" }
        $out = Join-Path $jniLibs "$abi\librclone.so"
        New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
        Write-Host "== building rclone $RcloneVersion for $abi =="
        $env:GOOS = 'android'
        $env:GOARCH = $t.goarch
        $env:CGO_ENABLED = '1'       # C resolver + system certs need cgo on Android
        $env:CC = Join-Path $ndkBin $t.cc
        $env:CGO_LDFLAGS = '-fuse-ld=lld -Wl,--hash-style=both -s'
        if ($t.goarm) { $env:GOARM = $t.goarm } else { Remove-Item Env:GOARM -ErrorAction SilentlyContinue }
        # noselfupdate: self-update would try to replace the extracted binary.
        & $go build -tags 'android noselfupdate' -trimpath `
            -ldflags '-s -w -buildid=' -o $out github.com/rclone/rclone
        if ($LASTEXITCODE -ne 0) { throw "go build failed for $abi" }
        Write-Host ("   -> {0}  {1:N1} MB" -f $out, ((Get-Item $out).Length / 1MB))
    }
}
finally {
    Pop-Location
    foreach ($n in $envNames) {
        [Environment]::SetEnvironmentVariable($n, $envSnapshot[$n])
    }
}
Write-Host 'done.'
