param(
    [string]$Version,
    [string]$BuildNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DefaultVersion {
    $gitVersion = ""
    try {
        $gitVersion = (git describe --tags --abbrev=0).Trim()
    } catch {
        $gitVersion = ""
    }

    if ($gitVersion.StartsWith("v")) {
        return $gitVersion.Substring(1)
    }

    if (-not [string]::IsNullOrWhiteSpace($gitVersion)) {
        return $gitVersion
    }

    return "0.28.3"
}

function Remove-DirectoryIfExists {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-DefaultVersion
}

if ([string]::IsNullOrWhiteSpace($BuildNumber)) {
    if ($env:GITHUB_RUN_NUMBER) {
        $BuildNumber = $env:GITHUB_RUN_NUMBER
    } else {
        $BuildNumber = "1"
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runnerDir = Join-Path $scriptDir "build\windows\x64\runner"
$releaseDir = Join-Path $runnerDir "Release"
$stagingRoot = Join-Path $runnerDir "package"
$packageDir = Join-Path $stagingRoot "flet"
$zipPath = Join-Path $scriptDir "flet-windows.zip"
$buildWindowsDir = Join-Path $scriptDir "build\windows"
$runtimeDlls = @(
    "msvcp140.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll"
)

Write-Host "Building Windows client version $Version+$BuildNumber"

Push-Location $scriptDir
try {
    flutter config --enable-windows-desktop | Out-Host
    # Clear generated CMake state so the build doesn't reuse an older VS generator.
    Remove-DirectoryIfExists -Path $buildWindowsDir
    flutter build windows --build-name="$Version" --build-number="$BuildNumber" | Out-Host
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $releaseDir)) {
    throw "Flutter Windows release directory was not created: $releaseDir"
}

foreach ($dll in $runtimeDlls) {
    $sourceDll = Join-Path $env:WINDIR "System32\$dll"
    if (Test-Path -LiteralPath $sourceDll) {
        Copy-Item -LiteralPath $sourceDll -Destination (Join-Path $releaseDir $dll) -Force
    } else {
        Write-Warning "Runtime DLL not found and was skipped: $sourceDll"
    }
}

Remove-DirectoryIfExists -Path $packageDir
if (-not (Test-Path -LiteralPath $stagingRoot)) {
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
}

Copy-Item -LiteralPath $releaseDir -Destination $packageDir -Recurse

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path $packageDir -DestinationPath $zipPath -Force

Write-Host "Windows package created at: $zipPath"
