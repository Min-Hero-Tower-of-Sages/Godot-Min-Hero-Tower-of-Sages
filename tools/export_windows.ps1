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
# Windows GUI executables need explicit -Wait. Matching export templates
# must be installed via the editor's Manage Export Templates dialog.
$arguments = '--headless --path "{0}" --export-release "Windows Desktop" "{1}"' -f $rootPath, $exePath
$process = Start-Process -FilePath $resolvedGodot -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exePath)) {
    Get-Content -LiteralPath $stderrPath
    throw "Windows export failed (exit $($process.ExitCode)). See $stdoutPath and $stderrPath."
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
