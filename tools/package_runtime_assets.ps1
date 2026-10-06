param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath($ProjectRoot)
$extractionPath = Join-Path $rootPath 'development/extracted/full-20260908'
$imagePath = Join-Path $extractionPath 'image'
$destinationPath = Join-Path $rootPath 'content/base/art/source_symbols'
New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
$symbolMap = [ordered]@{}
$copied = 0
foreach ($asset in (Get-ChildItem -LiteralPath $imagePath -File | Sort-Object Name)) {
    if ($asset.Extension -notin @('.png', '.jpg', '.jpeg')) { continue }
    $destination = Join-Path $destinationPath $asset.Name
    if (Test-Path -LiteralPath $destination) {
        if ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $asset.FullName).Hash) {
            throw "Refusing to replace a different runtime asset: $destination"
        }
    } else { Copy-Item -LiteralPath $asset.FullName -Destination $destination; $copied++ }
    if ($asset.BaseName -match '_Utilities\.SpriteHandler_(.+)$') {
        $symbolMap[$Matches[1]] = 'res://content/base/art/source_symbols/' + $asset.Name
    }
}
# Shared embedded PNGs have numeric filenames. Resolve aliases once during
# packaging, rather than requiring ActionScript files in the exported game.
$wrapperPath = Join-Path $extractionPath 'script/scripts/Utilities'
foreach ($wrapper in (Get-ChildItem -LiteralPath $wrapperPath -Filter 'SpriteHandler_*.as' -File | Sort-Object Name)) {
    $sourceText = [IO.File]::ReadAllText($wrapper.FullName)
    if ($sourceText -match 'Embed\(source="/_assets/([^"\r\n]+)"') {
        $filename = $Matches[1]
        if (Test-Path -LiteralPath (Join-Path $destinationPath $filename)) {
            $symbolMap[$wrapper.BaseName.Substring('SpriteHandler_'.Length)] = 'res://content/base/art/source_symbols/' + $filename
        }
    }
}
$encoding = [Text.UTF8Encoding]::new($false)
$manifestPath = Join-Path $destinationPath 'symbols.json'
[IO.File]::WriteAllText($manifestPath, ($symbolMap | ConvertTo-Json -Depth 4) + "`n", $encoding)
$updated = 0
$payloads = 0
foreach ($subdirectory in @('src', 'scenes', 'content', 'tests')) {
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $rootPath $subdirectory) -Recurse -File)) {
        if ($file.Extension -notin @('.gd', '.tscn', '.tres', '.json')) { continue }
        $original = [IO.File]::ReadAllText($file.FullName)
        $rewritten = $original.Replace('res://development/extracted/full-20260908/image/', 'res://content/base/art/source_symbols/')
        $rewritten = [regex]::Replace($rewritten, 'res://development/normalized/[^"\s]+\.json', {
            param($match)
            $oldPath = $match.Value
            $relative = $oldPath.Substring('res://development/normalized/'.Length)
            $newRelative = 'content/base/room_payloads/packaged/' + $relative
            $sourcePath = Join-Path $rootPath $oldPath.Substring('res://'.Length)
            $targetPath = Join-Path $rootPath $newRelative
            if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Missing room payload: $oldPath" }
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
            if (-not (Test-Path -LiteralPath $targetPath)) { Copy-Item -LiteralPath $sourcePath -Destination $targetPath }
            'res://' + $newRelative
        })
        if ($rewritten -ne $original) {
            [IO.File]::WriteAllText($file.FullName, $rewritten, $encoding)
            $updated++
        }
    }
}
Write-Output "Packaged $copied images; $($symbolMap.Count) symbol bindings; migrated $updated runtime/test files. Originals preserved."
