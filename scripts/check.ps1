$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'use-project-tools.ps1')
Push-Location $projectRoot
try {
    $project = Get-Content -LiteralPath 'default.project.json' -Raw | ConvertFrom-Json
    foreach ($worldService in @('Workspace','Lighting')) {
        if ($project.tree.PSObject.Properties.Name -contains $worldService) {
            throw "World ownership requires an explicit task and backup: $worldService"
        }
    }
    if ($project.tree.'$ignoreUnknownInstances' -ne $true) {
        throw 'DataModel must preserve unknown Studio content.'
    }
    $expectedMappings = @{
        'src/shared' = $project.tree.ReplicatedStorage.GameShared.'$path'
        'src/server' = $project.tree.ServerScriptService.GameServer.'$path'
        'src/client' = $project.tree.StarterPlayer.StarterPlayerScripts.GameClient.'$path'
    }
    foreach ($mapping in $expectedMappings.GetEnumerator()) {
        if ($mapping.Key -ne $mapping.Value) { throw "Unexpected mapping: $($mapping.Key)" }
    }

    $config = Get-Content -LiteralPath 'src/shared/Config/GameConfig.luau' -Raw
    if ($config -notmatch 'Enabled\s*=\s*false') {
        throw 'Persistence must remain disabled for this local MVP.'
    }

    stylua --check src
    if ($LASTEXITCODE -ne 0) { throw 'StyLua check failed.' }
    selene src
    if ($LASTEXITCODE -ne 0) { throw 'Selene check failed.' }

    New-Item -ItemType Directory -Path 'build' -Force | Out-Null
    rojo build default.project.json --output build/code-foundation.rbxlx
    if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed.' }
    rojo sourcemap default.project.json --output build/sourcemap.json
    if ($LASTEXITCODE -ne 0) { throw 'Rojo sourcemap failed.' }

    [xml]$codePlace = Get-Content -LiteralPath 'build/code-foundation.rbxlx' -Raw
    foreach ($containerName in @('GameShared','GameServer','GameClient')) {
        $matchingContainers = $codePlace.SelectNodes("//Item/Properties/string[@name='Name' and text()='$containerName']")
        if ($matchingContainers.Count -ne 1) { throw "Missing or duplicate code container: $containerName" }
    }

    Write-Output 'PASS: formatting, lint, code-only build, sourcemap, safe mappings and disabled persistence.'
    Write-Output 'Studio connection, Output and Play Test still require a live Studio session.'
} finally {
    Pop-Location
}
