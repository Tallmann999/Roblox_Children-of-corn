$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:ROKIT_ROOT = Join-Path $projectRoot '.tools\rokit-data'
$bootstrapBin = Join-Path $projectRoot '.tools\bootstrap'
$managedBin = Join-Path $env:ROKIT_ROOT 'bin'
$pathEntries = @($env:PATH -split ';')
foreach ($toolBin in @($managedBin, $bootstrapBin)) {
    if ($toolBin -notin $pathEntries) {
        $env:PATH = $toolBin + ';' + $env:PATH
        $pathEntries = @($env:PATH -split ';')
    }
}
