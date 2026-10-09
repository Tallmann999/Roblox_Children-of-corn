param([ValidateRange(1024,65535)][int]$Port = 34872)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'use-project-tools.ps1')
Push-Location $projectRoot
try {
    rojo serve default.project.json --address 127.0.0.1 --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Rojo serve failed.' }
} finally {
    Pop-Location
}
