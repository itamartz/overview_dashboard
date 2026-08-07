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

# Shared functions: Send-ToApi, Get-CyberArkCredential, Get-EncryptedCredential, Resolve-Credential
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

#region Helper Functions

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

        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $target.name -Metric $metric.name -Severity $severity `
            -Status $status -TTL $defaultTTL | Out-Null
    }
}


Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Agent run completed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
