param([switch]$SkipPluginInstall)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'use-project-tools.ps1')
Push-Location $projectRoot
try {
    $rokitExecutable = Join-Path $bootstrapBin 'rokit.exe'
    if (-not (Test-Path -LiteralPath $rokitExecutable -PathType Leaf)) {
        New-Item -ItemType Directory -Path $bootstrapBin,$env:ROKIT_ROOT -Force | Out-Null
        $rokitArchive = Join-Path $bootstrapBin 'rokit-1.2.0-windows-x86_64.zip'
        Invoke-WebRequest -Uri 'https://github.com/rojo-rbx/rokit/releases/download/v1.2.0/rokit-1.2.0-windows-x86_64.zip' -OutFile $rokitArchive
        $expectedArchiveHash = 'f9ba1704014ff67d51e8005f605955c7c26d2429a5312a9419dc477fc310e96d'
        if ((Get-FileHash -LiteralPath $rokitArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedArchiveHash) {
            throw 'Rokit release checksum does not match.'
        }
        Expand-Archive -LiteralPath $rokitArchive -DestinationPath $bootstrapBin -Force
    }

    & $rokitExecutable install
    if ($LASTEXITCODE -ne 0) { throw 'Rokit install failed.' }

    if (-not $SkipPluginInstall) {
        $pluginsDirectory = Join-Path $env:LOCALAPPDATA 'Roblox\Plugins'
        if (Test-Path -LiteralPath $pluginsDirectory -PathType Container) {
            $existingRojoPlugins = @(Get-ChildItem -LiteralPath $pluginsDirectory -File -Filter '*rojo*')
            if ($existingRojoPlugins.Count -gt 0) {
                $pluginBackup = Join-Path $projectRoot ('.tools\plugin-backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
                New-Item -ItemType Directory -Path $pluginBackup -Force | Out-Null
                foreach ($pluginFile in $existingRojoPlugins) {
                    Copy-Item -LiteralPath $pluginFile.FullName -Destination $pluginBackup
                }
            }
        }
        rojo plugin install
        if ($LASTEXITCODE -ne 0) { throw 'Rojo plugin installation failed.' }
    }

    rokit --version
    rojo --version
    stylua --version
    selene --version
} finally {
    Pop-Location
}
