<#
.SYNOPSIS
    Monitors Active Directory Health and reports metrics to the Overview Dashboard.

.DESCRIPTION
    Runs locally on a Domain Controller. Checks mandatory AD services (NTDS, Netlogon, DNS, etc.)
    and executes 'dcdiag /q' to check for replication and AD-specific errors.
    Calculates overall severity and reports as a single component.

.PARAMETER ConfigPath
    Path to the config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    If specified, shows what would be reported without connecting or sending to API.

.PARAMETER MockRun
    If specified, generates sample data and sends to API without real connections.

.EXAMPLE
    .\Get-ActiveDirectoryMetrics.ps1

.EXAMPLE
    .\Get-ActiveDirectoryMetrics.ps1 -MockRun
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$MockRun
)

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot "config.json"
}


# Shared functions: Send-ToApi
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

#region Main Script

# Check config file exists
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found at $ConfigPath"
    exit 1
}

# Read configuration
try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse config file: $_"
    exit 1
}

# Extract settings
$apiUrl = $config.apiUrl
$projectName = $config.projectName
$systemName = $config.systemName
$defaultTTL = if ($config.defaultTTL) { $config.defaultTTL } else { 3600 }
$hostname = [System.Net.Dns]::GetHostName()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Active Directory Metrics Agent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API URL: $apiUrl"
Write-Host "Project: $projectName"
Write-Host "System:  $systemName"
Write-Host "Host:    $hostname"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - No connections or API calls]" -ForegroundColor Yellow
}
if ($MockRun) {
    Write-Host "[MOCK RUN MODE - Sending sample data to API]" -ForegroundColor Magenta
}

$overallServicesSeverity = "ok"
$serviceStatuses = @()
$downServices = @()

# 1. Services Check
foreach ($service in $config.services) {
    if ($DryRun) {
        Write-Host "[DRY RUN] Would check service: $service"
        continue
    }
    
    if ($MockRun) {
        $status = "Running"
        $sev = "ok"
    } else {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            $status = "Not Found"
            $sev = "error"
            $downServices += $service
        } elseif ($svc.Status -ne 'Running') {
            $status = $svc.Status
            $sev = "error"
            $downServices += $service
        } else {
            $status = "Running"
            $sev = "ok"
        }
    }
    
    if ($sev -eq "error") {
        $overallServicesSeverity = "error"
        $serviceStatuses += "$($service): $status"
    }
}

# 2. DCDiag Check
$dcdiagSeverity = "ok"
$dcdiagStatus = "Tests Passed"
$dcdiagErrorsText = ""
$dcdiagTestResults = @{}

if ($DryRun) {
    Write-Host "[DRY RUN] Would run dcdiag"
} elseif ($MockRun) {
    Write-Host "[MOCK RUN] Mocking dcdiag pass"
    $dcdiagTestResults["Connectivity"] = "Passed"
    $dcdiagTestResults["Replications"] = "Passed"
} else {
    try {
        Write-Host "Running dcdiag (this might take a minute)..."
        $dcdiagOutput = dcdiag /test:NetLogons /test:Services /test:Replications /test:Advertising /test:DNS 2>&1
        $failedTests = @()
        
        $allowedTests = @('advertising', 'dns', 'netlogons', 'replications', 'services')
        
        $dcdiagOutput | ForEach-Object {
            if ($_ -match "passed test\s+(.+)") {
                $testName = $matches[1].Trim().ToLower()
                if ($allowedTests -contains $testName) {
                    $dcdiagTestResults[$testName] = "Passed"
                }
            } elseif ($_ -match "failed test\s+(.+)") {
                $testName = $matches[1].Trim().ToLower()
                if ($allowedTests -contains $testName) {
                    if ($testName -eq 'dns' -and (($dcdiagOutput -join ' ') -match 'Broken delegated')) {
                        $dcdiagTestResults[$testName] = "Passed"
                    } else {
                        $dcdiagTestResults[$testName] = "Failed"
                        $failedTests += $testName
                    }
                }
            }
        }
        
        if ($failedTests.Count -gt 0) {
            $dcdiagSeverity = "error"
            $dcdiagStatus = "Failed Tests Found"
            $failedJoined = ($failedTests -join " | ").Trim()
            if ($failedJoined.Length -gt 250) {
                $dcdiagErrorsText = $failedJoined.Substring(0, 247) + "..."
            } else {
                $dcdiagErrorsText = $failedJoined
            }
        }
    } catch {
        $dcdiagSeverity = "error"
        $dcdiagStatus = "Execution Failed"
        $dcdiagErrorsText = $_.Exception.Message
    }
}

# 3. Compile Results
$overallSeverity = "ok"
if ($overallServicesSeverity -eq "error" -or $dcdiagSeverity -eq "error") {
    $overallSeverity = "error"
}

$statusMessage = ""
if ($overallSeverity -eq "ok") {
    $statusMessage = "All AD Services running. DCDiag passed."
    Write-Host "[SUCCESS] $statusMessage" -ForegroundColor Green
} else {
    $errors = @()
    if ($overallServicesSeverity -eq "error") { $errors += "Service(s) down ($($downServices -join ', '))" }
    if ($dcdiagSeverity -eq "error") { $errors += "DCDiag failed" }
    $statusMessage = $errors -join "; "
    Write-Host "[ERROR] $statusMessage" -ForegroundColor Red
}

$extraFields = New-Object PSObject -Property @{
    advertising  = if ($dcdiagTestResults['advertising']) { $dcdiagTestResults['advertising'] } else { 'N/A' }
    dns          = if ($dcdiagTestResults['dns']) { $dcdiagTestResults['dns'] } else { 'N/A' }
    netlogons    = if ($dcdiagTestResults['netlogons']) { $dcdiagTestResults['netlogons'] } else { 'N/A' }
    replications = if ($dcdiagTestResults['replications']) { $dcdiagTestResults['replications'] } else { 'N/A' }
    services     = if ($dcdiagTestResults['services']) { $dcdiagTestResults['services'] } else { 'N/A' }
}

# 4. Report to API
if (-not $DryRun) {
    Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
        -Name $hostname -Metric "AD Health" -Severity $overallSeverity `
        -Status $statusMessage -TTL $defaultTTL -ExtraFields $extraFields | Out-Null
}


Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Completed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
