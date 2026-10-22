param(
    [ValidateSet('A','B')][string]$Variant,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
if (-not $Variant) {
    throw 'Choose the scene explicitly: .\scripts\serve.ps1 -Variant A (or B). The default project is build-only.'
}
. (Join-Path $PSScriptRoot 'use-project-tools.ps1')
Push-Location $projectRoot
try {
    python scripts/rojo-ab.py --check
    if ($LASTEXITCODE -ne 0) { throw 'A/B ownership or build validation failed; Rojo was not started.' }
    $projectFile = "$Variant.project.json"
    $project = Get-Content -LiteralPath $projectFile -Raw | ConvertFrom-Json
    Write-Output "Rojo $Variant -> $($project.name), 127.0.0.1:$($project.servePort)"
    if ($CheckOnly) { return }
    Write-Output 'Connect only after fresh MCP verification of this exact scene in Edit and its current Sources.'
    Write-Output 'Review the initial sync diff in the Rojo plugin. Stop this server with Ctrl+C.'
    rojo serve $projectFile --address 127.0.0.1 --port $project.servePort
    if ($LASTEXITCODE -ne 0) { throw 'Rojo serve failed.' }
} finally {
    Pop-Location
}
