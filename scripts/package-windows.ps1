# Build both Windows distributions from the same release bundle.
# Run after scripts/build-windows-core.sh and flutter build windows --release.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path $PSScriptRoot -Parent
$bundle = Join-Path $repoRoot 'build/windows/x64/runner/Release'
$outputDir = Join-Path $repoRoot 'dist'

$versionMatch = [regex]::Match(
    (Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw),
    '(?m)^version: (\d+\.\d+\.\d+)\+([1-9]\d*)\s*$'
)
if (-not $versionMatch.Success) { throw 'Expected a stable version and build number in pubspec.yaml' }
$appVersion = $versionMatch.Groups[1].Value
$appBuild = $versionMatch.Groups[2].Value

foreach ($file in @('ferry.exe', 'flutter_windows.dll', 'sing-box.exe', 'data/icudtl.dat', 'data/app.so')) {
    if (-not (Test-Path (Join-Path $bundle $file) -PathType Leaf)) {
        throw "Missing Windows release payload: $file"
    }
}

# Ship the Visual Studio runtime app-locally, so a clean PC does not need a
# separate, elevated VC++ redistributable installation or a network download.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vsPath) { throw 'Visual Studio C++ tools were not found' }
$redistRoot = Join-Path $vsPath 'VC/Redist/MSVC'
$redistVersion = Get-ChildItem $redistRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not $redistVersion) { throw 'Visual Studio C++ redistributable directory was not found' }
$crtDir = Get-ChildItem (Join-Path $redistVersion.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
    Select-Object -First 1
if (-not $crtDir) { throw 'Visual Studio x64 CRT was not found' }
Copy-Item (Join-Path $crtDir.FullName '*.dll') $bundle -Force
foreach ($file in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path (Join-Path $bundle $file) -PathType Leaf)) { throw "Missing C++ runtime: $file" }
}

# GitHub's Windows runners include Inno Setup 6. Local builders can install it
# themselves; no package-manager changes are made by this script.
$compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($compiler) {
    $iscc = $compiler.Source
} else {
    $iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
}
if (-not (Test-Path $iscc -PathType Leaf)) { throw 'Install Inno Setup 6 or add ISCC.exe to PATH' }
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
Copy-Item (Join-Path $repoRoot 'LICENSE') (Join-Path $bundle 'LICENSE.txt') -Force
& $iscc '/Qp' "/DAppVersion=$appVersion" "/DAppBuild=$appBuild" "/DBundleDir=$bundle" "/DOutputDir=$outputDir" (Join-Path $repoRoot 'windows/installer/ferry.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
$installer = Join-Path $outputDir "ferry-windows-x64-$appVersion-$appBuild-setup.exe"
if (-not (Test-Path $installer -PathType Leaf)) { throw "Installer was not generated: $installer" }
Write-Host "Built $installer"

$archive = Join-Path $outputDir "ferry-windows-x64-$appVersion-$appBuild.zip"
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive -Force
if (-not (Test-Path $archive -PathType Leaf)) { throw "ZIP was not generated: $archive" }
Write-Host "Built $archive"
