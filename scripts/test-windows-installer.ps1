# Exercise the actual installer on the disposable Windows CI runner.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path $PSScriptRoot -Parent
$installers = @(Get-ChildItem (Join-Path $repoRoot 'dist/*-setup.exe'))
if ($installers.Count -ne 1) { throw 'Expected exactly one Windows installer' }
$installer = $installers[0].FullName
$bundle = Join-Path $repoRoot 'build/windows/x64/runner/Release'
$archives = @(Get-ChildItem (Join-Path $repoRoot 'dist/ferry-windows-x64-*.zip'))
if ($archives.Count -ne 1) { throw 'Expected exactly one Windows ZIP' }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ferry-installer-' + [guid]::NewGuid())
$installDir = Join-Path $testRoot 'Install with spaces'
$logDir = Join-Path $repoRoot 'build/installer-logs'
$registryKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\com.wildalley.ferry_is1'
$startShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) '渡 Ferry/渡 Ferry.lnk'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) '渡 Ferry.lnk'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Invoke-Installer([string]$executable, [string[]]$arguments) {
    $process = Start-Process -FilePath $executable -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installer exited with $($process.ExitCode): $executable" }
}

function Assert-Payload([string]$destination) {
    foreach ($source in Get-ChildItem $bundle -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($bundle, $source.FullName)
        $target = Join-Path $destination $relative
        if (-not (Test-Path $target -PathType Leaf)) { throw "Missing installed file: $relative" }
        if ((Get-FileHash $source.FullName).Hash -ne (Get-FileHash $target).Hash) {
            throw "Installed file differs: $relative"
        }
    }
    if ((Get-FileHash (Join-Path $repoRoot 'LICENSE')).Hash -ne
        (Get-FileHash (Join-Path $destination 'LICENSE.txt')).Hash) {
        throw 'Installed license differs'
    }
}

if (Test-Path $registryKey) { throw 'Smoke test requires a runner without an existing Ferry installation' }
try {
    $zipDir = Join-Path $testRoot 'ZIP with spaces'
    Expand-Archive $archives[0].FullName $zipDir
    Assert-Payload $zipDir
    $sourceFiles = @(Get-ChildItem $bundle -File -Recurse)
    $zipFiles = @(Get-ChildItem $zipDir -File -Recurse)
    if ($sourceFiles.Count -ne $zipFiles.Count) { throw 'ZIP contains unexpected files' }
    & (Join-Path $zipDir 'sing-box.exe') version
    if ($LASTEXITCODE -ne 0) { throw 'ZIP sing-box could not run' }

    $installArgs = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/RESTARTEXITCODE=3010',
        "/DIR=`"$installDir`"", '/TASKS=desktopicon')
    Invoke-Installer $installer ($installArgs + "/LOG=`"$logDir/install.log`"")
    Assert-Payload $installDir
    foreach ($path in @($registryKey, $startShortcut, $desktopShortcut)) {
        if (-not (Test-Path $path)) { throw "Missing installation registration or shortcut: $path" }
    }
    $registration = Get-ItemProperty $registryKey
    if ($registration.InstallLocation.TrimEnd('\') -ne $installDir) { throw 'Incorrect registered install path' }
    & (Join-Path $installDir 'sing-box.exe') version
    if ($LASTEXITCODE -ne 0) { throw 'Installed sing-box could not run' }

    # Reinstall must replace damaged payloads and preserve unknown user files.
    $marker = Join-Path $installDir 'user-data-sentinel.txt'
    Set-Content $marker 'keep me'
    Set-Content (Join-Path $installDir 'LICENSE.txt') 'damaged payload'
    # Omit /DIR on reinstall: the stable AppId must find the previous directory.
    $repairArgs = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/RESTARTEXITCODE=3010',
        "/LOG=`"$logDir/repair.log`"")
    Invoke-Installer $installer $repairArgs
    Assert-Payload $installDir
    if ((Get-Content $marker -Raw).Trim() -ne 'keep me') { throw 'Reinstall modified user data' }

    Invoke-Installer (Join-Path $installDir 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES',
        '/NORESTART', "/LOG=`"$logDir/uninstall.log`"")
    foreach ($path in @($registryKey, $startShortcut, $desktopShortcut, (Join-Path $installDir 'ferry.exe'),
        (Join-Path $installDir 'sing-box.exe'), (Join-Path $installDir 'LICENSE.txt'))) {
        if (Test-Path $path) { throw "Uninstall left an installed resource: $path" }
    }
    if ((Get-Content $marker -Raw).Trim() -ne 'keep me') { throw 'Uninstall removed user data' }
    Write-Host 'Windows ZIP, install, repair and uninstall checks passed'
} finally {
    # Clean up a partial installation on failure as well. Logs remain in build/.
    $uninstaller = Join-Path $installDir 'unins000.exe'
    if (Test-Path $uninstaller) {
        Invoke-Installer $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    }
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
}
