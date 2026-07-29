<#
.SYNOPSIS
    Example monitoring agent for Overview Dashboard demonstrating architecture guidelines.

.DESCRIPTION
    Collects sample system/application metrics, evaluates severity against configurable thresholds,
    and posts formatted payloads to the Overview Dashboard REST API.

.PARAMETER ConfigPath
    Path to config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    If specified, displays configuration and targets without making connections or API calls.

.PARAMETER MockRun
    If specified, generates sample metric values and posts them to the Overview Dashboard API.

.EXAMPLE
    .\Get-ExampleMetrics.ps1 -DryRun

.EXAMPLE
    .\Get-ExampleMetrics.ps1 -MockRun

.NOTES
    Architecture Reference: AGENT-DEVELOPMENT-GUIDE.md
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$MockRun
)

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot "config.json"
}

#region Helper Functions

function Send-ToApi {
    param(
        [string]$ApiUrl,
        [string]$SystemName,
        [string]$ProjectName,
        [string]$Name,
        [string]$Metric,
        [string]$Severity,
        [string]$Status,
        [int]$TTL
    )

    # Deterministic ID generation: SystemName|ProjectName|Name|Metric
    $idSource = "$SystemName|$ProjectName|$Name|$Metric"
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($idSource)
    $hash = $md5.ComputeHash($bytes)
    $componentId = [System.BitConverter]::ToString($hash) -replace '-', ''

    $componentPayload = @{
        Id       = $componentId
        Name     = $Name
        Metric   = $Metric
        Severity = $Severity
        Status   = $Status
        TTL      = $TTL
    } | ConvertTo-Json -Compress

    $body = @{
        systemName  = $SystemName
        projectName = $ProjectName
        payload     = $componentPayload
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body `
            -ContentType "application/json" -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Warning "Failed to send payload for component '$Name' ($Metric) to API: $_"
        return $false
    }
}

function Get-CyberArkCredential {
    param(
        [string]$CcpUrl,
        [string]$AppId,
        [string]$Safe,
        [string]$ObjectName,
        [bool]$VerifySsl = $true,
        [int]$TimeoutSeconds = 10
    )

    $queryParams = @(
        "AppID=$([uri]::EscapeDataString($AppId))",
        "Safe=$([uri]::EscapeDataString($Safe))",
        "Object=$([uri]::EscapeDataString($ObjectName))"
    )
    $fullUrl = "$CcpUrl`?$($queryParams -join '&')"

    $invokeParams = @{
        Uri         = $fullUrl
        Method      = 'GET'
        ContentType = 'application/json'
        TimeoutSec  = $TimeoutSeconds
        ErrorAction = 'Stop'
    }

    if (-not $VerifySsl -and $PSVersionTable.PSVersion.Major -ge 7) {
        $invokeParams.SkipCertificateCheck = $true
    }

    try {
        $response = Invoke-RestMethod @invokeParams
        return @{
            Username = $response.UserName
            Password = $response.Content
            Success  = $true
        }
    }
    catch {
        Write-Warning "CyberArk CCP lookup failed for '$ObjectName' in safe '$Safe': $_"
        return @{ Username = ""; Password = ""; Success = $false }
    }
}

function Get-EncryptedCredential {
    param(
        [string]$EncryptedFilePath,
        [string]$Username
    )

    if (-not (Test-Path $EncryptedFilePath)) {
        Write-Warning "Encrypted credential file not found: $EncryptedFilePath"
        return @{ Username = $Username; Password = ""; Success = $false }
    }

    try {
        $secureString = Get-Content $EncryptedFilePath | ConvertTo-SecureString
        $credential = New-Object System.Management.Automation.PSCredential($Username, $secureString)
        return @{
            Username = $Username
            Password = $credential.GetNetworkCredential().Password
            Success  = $true
        }
    }
    catch {
        Write-Warning "Failed to decrypt credential file '$EncryptedFilePath': $_"
        return @{ Username = $Username; Password = ""; Success = $false }
    }
}

function Resolve-Credential {
    param(
        [string]$Method,
        [object]$Target,
        [object]$CyberArkConfig
    )

    switch ($Method.ToLower()) {
        'cyberark' {
            return Get-CyberArkCredential `
                -CcpUrl $CyberArkConfig.ccpUrl `
                -AppId $CyberArkConfig.appId `
                -Safe $Target.cyberarkSafe `
                -ObjectName $Target.cyberarkObject `
                -VerifySsl $CyberArkConfig.verifySsl `
                -TimeoutSeconds $CyberArkConfig.timeoutSeconds
        }
        'encrypted' {
            $encPath = Join-Path $PSScriptRoot $Target.encryptedPasswordFile
            return Get-EncryptedCredential -EncryptedFilePath $encPath -Username $Target.username
        }
        default {
            return @{
                Username = $Target.username
                Password = $Target.password
                Success  = ($null -ne $Target.password -and $Target.password -ne "")
            }
        }
    }
}

function Calculate-Severity {
    param(
        [double]$Value,
        [double]$WarningThreshold,
        [double]$ErrorThreshold
    )

    if ($Value -ge $ErrorThreshold) {
        return "error"
    }
    elseif ($Value -ge $WarningThreshold) {
        return "warning"
    }
    else {
        return "ok"
    }
}

function Get-MockValue {
    param(
        [double]$WarningThreshold,
        [double]$ErrorThreshold
    )

    $rand = Get-Random -Minimum 0 -Maximum 100
    if ($rand -lt 70) {
        return [double](Get-Random -Minimum 10 -Maximum ([math]::Max(11, [int]($WarningThreshold - 5))))
    }
    elseif ($rand -lt 90) {
        return [double](Get-Random -Minimum ([int]$WarningThreshold) -Maximum ([int]($ErrorThreshold - 1)))
    }
    else {
        return [double](Get-Random -Minimum ([int]$ErrorThreshold) -Maximum ([int]($ErrorThreshold + 10)))
    }
}

#endregion

#region Main Logic

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found at $ConfigPath"
    exit 1
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse config file: $_"
    exit 1
}

$apiUrl = $config.apiUrl
$projectName = $config.projectName
$systemName = $config.systemName
$defaultTTL = if ($config.defaultTTL) { $config.defaultTTL } else { 120 }
$credMethod = if ($config.credentialMethod) { $config.credentialMethod } else { "plaintext" }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Example Monitoring Agent (PowerShell)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API URL:           $apiUrl"
Write-Host "Project Name:      $projectName"
Write-Host "System Name:       $systemName"
Write-Host "Default TTL:       $defaultTTL s"
Write-Host "Credential Method: $credMethod"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - No metrics will be collected or sent to API]" -ForegroundColor Yellow
}
if ($MockRun) {
    Write-Host "[MOCK RUN MODE - Generated metrics will be sent to API]" -ForegroundColor Magenta
}

foreach ($target in $config.targets) {
    if ($target.PSObject.Properties['enabled'] -and -not $target.enabled) {
        Write-Host "Skipping disabled target: $($target.name)" -ForegroundColor Gray
        continue
    }

    Write-Host "Processing Target: $($target.name) ($($target.host):$($target.port))" -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would resolve credentials using method '$credMethod'"
        foreach ($metric in $target.metrics) {
            Write-Host "  [DRY RUN] Would check '$($metric.name)' (Warning: $($metric.warning)%, Error: $($metric.error)%)"
        }
        continue
    }

    # Resolve credential
    $cred = Resolve-Credential -Method $credMethod -Target $target -CyberArkConfig $config.cyberark
    if (-not $cred.Success) {
        Write-Host "  -> Credential resolution failed for $($target.name)" -ForegroundColor Red
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $target.name -Metric "Credential" -Severity "error" `
            -Status "Failed to resolve credentials" -TTL $defaultTTL | Out-Null
        continue
    }

    foreach ($metric in $target.metrics) {
        $metricValue = 0.0
        if ($MockRun) {
            $metricValue = Get-MockValue -WarningThreshold $metric.warning -ErrorThreshold $metric.error
        }
        else {
            # Live collection simulation (e.g. random realistic metric for sample target)
            $metricValue = [double](Get-Random -Minimum 15 -Maximum 85)
        }

        $severity = Calculate-Severity -Value $metricValue -WarningThreshold $metric.warning -ErrorThreshold $metric.error
        $status = "$($metricValue)%"

        $color = switch ($severity) {
            'ok'      { 'Green' }
            'warning' { 'Yellow' }
            'error'   { 'Red' }
            default   { 'White' }
        }

        Write-Host "  Metric: $($metric.name) = $status [$severity]" -ForegroundColor $color

        $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $target.name -Metric $metric.name -Severity $severity `
            -Status $status -TTL $defaultTTL

        if ($sent) {
            Write-Host "    -> Successfully reported to API" -ForegroundColor Gray
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Agent run completed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
