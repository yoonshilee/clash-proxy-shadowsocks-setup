[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("init", "validate", "render", "copy")]
    [string]$Action = "render",

    [string]$ConfigDir,

    [string]$OutputDir,

    [string]$TemplatePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ConfigDir)) {
    $ConfigDir = Join-Path $PSScriptRoot "user-config"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $PSScriptRoot "local-config"
}
if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $TemplatePath = Join-Path $PSScriptRoot "active-config\mihomo-provider.yaml"
}

$exampleDir = Join-Path $PSScriptRoot "user-config.example"
$directFileName = "direct-domains.txt"
$proxyFileName = "proxy-domains.txt"
$providerFileName = "provider-url.txt"
$clashOutputName = "clash-verge-user-rules.yaml"
$mihomoOutputName = "mihomo.yaml"
$providerPlaceholder = "__VPS_PROVIDER_URL__"
$publicIpPlaceholder = "__VPS_PUBLIC_IP__"
$userRulesMarker = "# __USER_RULES__"
$domainPattern = "^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Initialize-UserConfig {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

    foreach ($fileName in @($directFileName, $proxyFileName, $providerFileName)) {
        $sourcePath = Join-Path $exampleDir $fileName
        $targetPath = Join-Path $ConfigDir $fileName

        if (-not (Test-Path -LiteralPath $targetPath)) {
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath
            Write-Output "Created: $targetPath"
        }
        else {
            Write-Output "Kept existing: $targetPath"
        }
    }
}

function Assert-UserConfigExists {
    foreach ($fileName in @($directFileName, $proxyFileName, $providerFileName)) {
        $path = Join-Path $ConfigDir $fileName
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing user config: $path. Run 'client\manage-user-rules.cmd init' first."
        }
    }
}

function Get-DomainEntries {
    param(
        [string]$Path,
        [ValidateSet("DIRECT", "PROXY")]
        [string]$Policy
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $lineNumber = 0

    foreach ($sourceLine in Get-Content -LiteralPath $Path) {
        $lineNumber += 1
        $value = $sourceLine.Split("#", 2)[0].Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        if ($value.StartsWith("*.")) {
            $value = $value.Substring(2)
        }
        elseif ($value.StartsWith(".")) {
            $value = $value.Substring(1)
        }

        $value = $value.TrimEnd(".")
        if ($value -notmatch $domainPattern) {
            throw "Invalid domain in ${Path}:${lineNumber}: $value"
        }

        if ($seen.Add($value)) {
            $entries.Add([pscustomobject]@{
                    Domain = $value
                    Policy = $Policy
                    Labels = $value.Split(".").Count
                })
        }
    }

    return $entries.ToArray()
}

function Get-UserRules {
    Assert-UserConfigExists

    $directPath = Join-Path $ConfigDir $directFileName
    $proxyPath = Join-Path $ConfigDir $proxyFileName
    $directEntries = @(Get-DomainEntries -Path $directPath -Policy "DIRECT")
    $proxyEntries = @(Get-DomainEntries -Path $proxyPath -Policy "PROXY")
    $directDomains = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $directEntries) {
        $null = $directDomains.Add($entry.Domain)
    }

    foreach ($entry in $proxyEntries) {
        if ($directDomains.Contains($entry.Domain)) {
            throw "Domain is configured for both DIRECT and PROXY: $($entry.Domain)"
        }
    }

    return @($directEntries + $proxyEntries | Sort-Object `
            @{ Expression = { $_.Labels }; Descending = $true }, `
            @{ Expression = { $_.Domain.Length }; Descending = $true }, `
            @{ Expression = { $_.Domain }; Ascending = $true }, `
            @{ Expression = { $_.Policy }; Ascending = $true })
}

function Get-ProviderUrl {
    Assert-UserConfigExists

    $providerPath = Join-Path $ConfigDir $providerFileName
    $values = @(Get-Content -LiteralPath $providerPath | ForEach-Object {
            $_.Split("#", 2)[0].Trim()
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($values.Count -eq 0) {
        return $null
    }
    if ($values.Count -ne 1) {
        throw "provider-url.txt must contain exactly one URL."
    }

    $value = $values[0]
    $uri = $null
    if (-not [uri]::TryCreate($value, [System.UriKind]::Absolute, [ref]$uri)) {
        throw "Invalid provider URL."
    }
    if ($uri.Scheme -ne "https") {
        throw "Provider URL must use HTTPS."
    }
    if (-not $uri.AbsolutePath.EndsWith("-provider.yaml", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Provider URL must end with -provider.yaml."
    }
    if (-not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment) -or -not [string]::IsNullOrEmpty($uri.UserInfo)) {
        throw "Provider URL must not contain user info, a query, or a fragment."
    }

    return $value
}

function Get-ProviderPublicIp {
    param([string]$ProviderUrl)

    $uri = [uri]$ProviderUrl
    if ($uri.DnsSafeHost -notmatch "^(?<ip>[0-9]+(?:\.[0-9]+){3})\.sslip\.io$") {
        throw "Provider URL host must use the <public-ip>.sslip.io format."
    }

    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($matches.ip, [ref]$address) -or $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Provider URL does not contain a valid public IPv4 address."
    }

    return $address.ToString()
}

function Get-ClashRuleLines {
    param([object[]]$Rules)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Generated from client/user-config by client/manage-user-rules.ps1")
    $lines.Add("")

    if ($Rules.Count -eq 0) {
        $lines.Add("prepend: []")
    }
    else {
        $lines.Add("prepend:")
        foreach ($rule in $Rules) {
            $lines.Add("  - DOMAIN-SUFFIX,$($rule.Domain),$($rule.Policy)")
        }
    }

    $lines.Add("")
    $lines.Add("append: []")
    $lines.Add("")
    $lines.Add("delete: []")
    return $lines.ToArray()
}

function Write-Utf8Lines {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [System.IO.File]::WriteAllLines($Path, $Lines, $utf8NoBom)
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Write-ClashRules {
    param([object[]]$Rules)

    $path = Join-Path $OutputDir $clashOutputName
    Write-Utf8Lines -Path $path -Lines (Get-ClashRuleLines -Rules $Rules)
    Write-Host "Rendered Clash Verge user rules: $path"
    return $path
}

function Write-MihomoConfig {
    param(
        [object[]]$Rules,
        [string]$ProviderUrl,
        [string]$PublicIp
    )

    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        throw "Mihomo template not found: $TemplatePath"
    }

    $template = Get-Content -LiteralPath $TemplatePath -Raw
    if (([regex]::Matches($template, [regex]::Escape($providerPlaceholder))).Count -ne 1) {
        throw "Mihomo template must contain exactly one provider URL placeholder."
    }
    if (([regex]::Matches($template, [regex]::Escape($publicIpPlaceholder))).Count -ne 1) {
        throw "Mihomo template must contain exactly one public IP placeholder."
    }
    if (([regex]::Matches($template, [regex]::Escape($userRulesMarker))).Count -ne 1) {
        throw "Mihomo template must contain exactly one user rule marker."
    }

    if ($Rules.Count -eq 0) {
        $userRuleText = "# No personal domain rules configured."
    }
    else {
        $userRuleText = ($Rules | ForEach-Object {
                "- DOMAIN-SUFFIX,$($_.Domain),$($_.Policy)"
            }) -join [Environment]::NewLine
    }

    $content = $template.Replace($providerPlaceholder, $ProviderUrl).Replace($publicIpPlaceholder, $PublicIp).Replace($userRulesMarker, $userRuleText)
    $path = Join-Path $OutputDir $mihomoOutputName
    Write-Utf8Text -Path $path -Content $content
    Write-Host "Rendered Mihomo config: $path"
    return $path
}

function Write-ValidationSummary {
    param(
        [object[]]$Rules,
        [string]$ProviderUrl
    )

    $directCount = @($Rules | Where-Object { $_.Policy -eq "DIRECT" }).Count
    $proxyCount = @($Rules | Where-Object { $_.Policy -eq "PROXY" }).Count
    $providerStatus = if ([string]::IsNullOrEmpty($ProviderUrl)) { "not configured" } else { "configured" }
    Write-Output "Validated user rules: DIRECT=$directCount, PROXY=$proxyCount, provider=$providerStatus"
}

switch ($Action.ToLowerInvariant()) {
    "init" {
        Initialize-UserConfig
    }
    "validate" {
        $rules = @(Get-UserRules)
        $providerUrl = Get-ProviderUrl
        if (-not [string]::IsNullOrEmpty($providerUrl)) {
            $null = Get-ProviderPublicIp -ProviderUrl $providerUrl
        }
        Write-ValidationSummary -Rules $rules -ProviderUrl $providerUrl
    }
    "render" {
        $rules = @(Get-UserRules)
        $providerUrl = Get-ProviderUrl
        if ([string]::IsNullOrEmpty($providerUrl)) {
            throw "provider-url.txt is required for render. Use 'copy' for Clash Verge-only rules."
        }
        $publicIp = Get-ProviderPublicIp -ProviderUrl $providerUrl
        $null = Write-ClashRules -Rules $rules
        $null = Write-MihomoConfig -Rules $rules -ProviderUrl $providerUrl -PublicIp $publicIp
        Write-ValidationSummary -Rules $rules -ProviderUrl $providerUrl
    }
    "copy" {
        $rules = @(Get-UserRules)
        $path = Write-ClashRules -Rules $rules
        if (-not (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
            throw "Set-Clipboard is not available in this PowerShell session."
        }
        Set-Clipboard -Value (Get-Content -LiteralPath $path -Raw)
        Write-Output "Copied Clash Verge user rules to the clipboard."
    }
}
