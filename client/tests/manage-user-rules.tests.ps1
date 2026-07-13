$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot "..\manage-user-rules.ps1"
$templatePath = Join-Path $PSScriptRoot "..\active-config\mihomo-provider.yaml"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clash-user-rules-" + [guid]::NewGuid().ToString("N"))
$configDir = Join-Path $tempRoot "user-config"
$outputDir = Join-Path $tempRoot "local-config"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [scriptblock]$Action,
        [string]$Message
    )

    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }

    Assert-True $threw $Message
}

try {
    & $scriptPath init -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    $directPath = Join-Path $configDir "direct-domains.txt"
    $proxyPath = Join-Path $configDir "proxy-domains.txt"
    $providerPath = Join-Path $configDir "provider-url.txt"

    Assert-True (Test-Path $directPath) "init must create direct-domains.txt"
    Assert-True (Test-Path $proxyPath) "init must create proxy-domains.txt"
    Assert-True (Test-Path $providerPath) "init must create provider-url.txt"

    Set-Content -Path $directPath -Value "keep.example.com" -Encoding utf8
    & $scriptPath init -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    Assert-True ((Get-Content $directPath -Raw).Trim() -eq "keep.example.com") "init must not overwrite existing files"

    @(
        "# Direct domains"
        "Example.COM"
        "*.example.com"
        ".direct.example.net. # inline comment"
    ) | Set-Content -Path $directPath -Encoding utf8
    @(
        "api.example.com"
        "proxy.example.org"
    ) | Set-Content -Path $proxyPath -Encoding utf8
    "https://203.0.113.10.sslip.io:8443/test-provider.yaml" | Set-Content -Path $providerPath -Encoding utf8

    & $scriptPath render -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath

    $clashRulesPath = Join-Path $outputDir "clash-verge-user-rules.yaml"
    $mihomoPath = Join-Path $outputDir "mihomo.yaml"
    $clashRules = Get-Content $clashRulesPath -Raw
    $mihomo = Get-Content $mihomoPath -Raw

    Assert-True (([regex]::Matches($clashRules, "DOMAIN-SUFFIX,example\.com,DIRECT")).Count -eq 1) "duplicate domains must be removed"
    Assert-True ($clashRules.Contains("DOMAIN-SUFFIX,direct.example.net,DIRECT")) "domains must be normalized"
    Assert-True ($clashRules.Contains("DOMAIN-SUFFIX,api.example.com,PROXY")) "proxy rules must be rendered"
    Assert-True ($clashRules.IndexOf("api.example.com") -lt $clashRules.IndexOf("example.com,DIRECT")) "more specific domains must be ordered first"
    Assert-True ($mihomo.Contains("https://203.0.113.10.sslip.io:8443/test-provider.yaml")) "mihomo config must contain the provider URL"
    Assert-True (-not $mihomo.Contains("__USER_RULES__")) "mihomo user rule marker must be replaced"
    Assert-True ($mihomo.IndexOf("api.example.com") -lt $mihomo.IndexOf("IP-CIDR")) "personal rules must precede managed rules"
    Assert-True ($mihomo.Contains("name: PROXY")) "mihomo config must keep the stable PROXY group"

    "same.example.com" | Set-Content -Path $directPath -Encoding utf8
    "same.example.com" | Set-Content -Path $proxyPath -Encoding utf8
    Assert-Throws {
        & $scriptPath validate -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    } "the same domain in both policies must fail validation"

    "https://invalid.example.com/path" | Set-Content -Path $directPath -Encoding utf8
    "" | Set-Content -Path $proxyPath -Encoding utf8
    Assert-Throws {
        & $scriptPath validate -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    } "URLs must not be accepted as domains"

    "valid.example.com" | Set-Content -Path $directPath -Encoding utf8
    "http://example.com/test-provider.yaml" | Set-Content -Path $providerPath -Encoding utf8
    Assert-Throws {
        & $scriptPath render -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    } "provider URLs must use HTTPS"

    "https://example.com/test-provider.yaml" | Set-Content -Path $providerPath -Encoding utf8
    Assert-Throws {
        & $scriptPath validate -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    } "validate must reject provider hosts that do not expose the VPS public IP"

    "" | Set-Content -Path $providerPath -Encoding utf8
    Assert-Throws {
        & $scriptPath render -ConfigDir $configDir -OutputDir $outputDir -TemplatePath $templatePath
    } "render must fail when the provider URL is missing"

    Write-Output "Validated manage-user-rules.ps1 behavior."
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
