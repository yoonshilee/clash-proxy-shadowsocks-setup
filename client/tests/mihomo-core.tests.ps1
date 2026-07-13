[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MihomoPath,

    [Parameter(Mandatory = $true)]
    [string]$MihomoHome
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$managerPath = Join-Path $PSScriptRoot "..\manage-user-rules.ps1"
$templatePath = Join-Path $PSScriptRoot "..\active-config\mihomo-provider.yaml"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mihomo-config-" + [guid]::NewGuid().ToString("N"))
$configDir = Join-Path $tempRoot "user-config"
$outputDir = Join-Path $tempRoot "local-config"

try {
    & $managerPath init -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    "local.example.com" | Set-Content -Path (Join-Path $configDir "direct-domains.txt") -Encoding utf8
    "proxy.example.com" | Set-Content -Path (Join-Path $configDir "proxy-domains.txt") -Encoding utf8
    "https://203.0.113.10.sslip.io:8443/test-provider.yaml" | Set-Content -Path (Join-Path $configDir "provider-url.txt") -Encoding utf8

    & $managerPath render -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    $mihomoConfig = Join-Path $outputDir "mihomo.yaml"

    & $MihomoPath -t -d $MihomoHome -f $mihomoConfig
    if ($LASTEXITCODE -ne 0) {
        throw "Mihomo rejected the generated config with exit code $LASTEXITCODE."
    }

    Write-Output "Validated generated mihomo.yaml with the Mihomo core."
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
