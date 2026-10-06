param(
    [string]$GodotExecutable = 'godot',
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath($ProjectRoot)
$resolvedGodot = (Get-Command $GodotExecutable -ErrorAction Stop).Source
$outputDirectory = Join-Path $rootPath 'build/windows'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $rootPath 'build/.gdignore'), '', [Text.UTF8Encoding]::new($false))
$exePath = Join-Path $outputDirectory 'MinHero.exe'
$stdoutPath = Join-Path $outputDirectory 'export.stdout.log'
$stderrPath = Join-Path $outputDirectory 'export.stderr.log'
$exportTemp = Join-Path $rootPath 'build/export-temp'
New-Item -ItemType Directory -Path $exportTemp -Force | Out-Null
# Windows GUI executables need explicit -Wait. Matching export templates
# must be installed via the editor's Manage Export Templates dialog.
$arguments = '--headless --path "{0}" --export-release "Windows Desktop" "{1}"' -f $rootPath, $exePath
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
try {
    # Godot serializes project.binary through the OS temp directory. Keep it
    # in the workspace so sandbox safe-save failures cannot produce a corrupt
    # embedded pack while still reporting a successful process exit.
    $env:TEMP = $exportTemp
    $env:TMP = $exportTemp
    $process = Start-Process -FilePath $resolvedGodot -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
} finally { $env:TEMP = $previousTemp; $env:TMP = $previousTmp }
$exportErrors = [IO.File]::ReadAllText($stderrPath)
if ($process.ExitCode -ne 0 -or $exportErrors -match '(?m)^ERROR:' -or -not (Test-Path -LiteralPath $exePath)) {
    Get-Content -LiteralPath $stderrPath
    throw "Windows export failed (exit $($process.ExitCode)). See $stdoutPath and $stderrPath."
}
# Never publish a pack merely because the exporter returned zero. Verify that
# the actual exported player can read it, using an isolated save/settings profile.
$bootProfile = Join-Path $rootPath 'build/release-boot-profile'
New-Item -ItemType Directory -Path $bootProfile -Force | Out-Null
$bootStdout = Join-Path $outputDirectory 'boot.stdout.log'
$bootStderr = Join-Path $outputDirectory 'boot.stderr.log'
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = $bootProfile
    $env:LOCALAPPDATA = $bootProfile
    $boot = Start-Process -FilePath $exePath -ArgumentList '--headless --quit-after 10' -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $bootStdout -RedirectStandardError $bootStderr
} finally { $env:APPDATA = $previousAppData; $env:LOCALAPPDATA = $previousLocalAppData }
if ($boot.ExitCode -ne 0 -or [IO.File]::ReadAllText($bootStderr) -match '(?m)^ERROR:|SCRIPT ERROR:') {
    Get-Content -LiteralPath $bootStderr
    throw "Exported player startup failed. No release ZIP was generated; see $bootStderr."
}
$archivePath = Join-Path $outputDirectory 'MinHero-windows-x86_64.zip'
$releaseFiles = @($exePath, (Join-Path $rootPath 'ASSET_NOTICES.md'))
# Explicit files only: never include old builds, logs or personal saves.
Compress-Archive -LiteralPath $releaseFiles -DestinationPath $archivePath -Force
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($archivePath + '.sha256', "$hash  MinHero-windows-x86_64.zip`n", [Text.UTF8Encoding]::new($false))
Write-Output "Windows export: $exePath"
Write-Output "GitHub Release asset: $archivePath"
Write-Output "Verify the exported build outside the editor before publishing."
