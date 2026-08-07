<#
.SYNOPSIS
    Monitors ICMP Ping status for hosts defined in a CSV file and reports to the Overview Dashboard.

.DESCRIPTION
    Reads a list of hosts from a plain CSV/Text file (no headers expected, first column is Host),
    performs a quick ICMP ping, calculates severity, and posts results to the API.

.PARAMETER CsvPath
    Path to the components.csv file. Default: $PSScriptRoot\components.csv

.PARAMETER ApiUrl
    The API endpoint URL.

.PARAMETER ProjectName
    The project name for the dashboard.

.PARAMETER SystemName
    The system name for the dashboard.

.PARAMETER DefaultTTL
    Time-To-Live in seconds for the components. Default: 60

.PARAMETER TimeoutMs
    Timeout for Ping in milliseconds. Default: 1000

.PARAMETER DryRun
    Shows what would be checked without sending API calls or doing pings.

.PARAMETER MockRun
    Generates random ok/error ping results and sends to API.
#>

param(
    [string]$CsvPath = "$PSScriptRoot\components.csv",
    [string]$ApiUrl = "https://overview.tazone.net/api/components",
    [string]$ProjectName = "Ping Checks",
    [string]$SystemName = "Network Monitoring",
    [int]$DefaultTTL = 60,
    [int]$TimeoutMs = 1000,
    [switch]$DryRun,
    [switch]$MockRun
)

# Startup Banner
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Ping Agent - Overview Dashboard         " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "API URL:      $ApiUrl" -ForegroundColor Cyan
Write-Host "Project:      $ProjectName" -ForegroundColor Cyan
Write-Host "System:       $SystemName" -ForegroundColor Cyan
Write-Host "TTL:          $DefaultTTL" -ForegroundColor Cyan
$mode = "Normal"
if ($DryRun) { $mode = "DryRun" }
if ($MockRun) { $mode = "MockRun" }
Write-Host "Mode:         $mode" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Shared functions: Send-ToApi
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

function Test-Ping {
    param(
        [string]$Target,
        [int]$Timeout
    )

    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        $buffer = New-Object byte[] 32
        $reply = $ping.Send($Target, $Timeout, $buffer)
        
        if ($reply.Status -eq 'Success') {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        if ($ping) {
            $ping.Dispose()
        }
    }
}

if (-not (Test-Path $CsvPath)) {
    Write-Host "CSV/Host file not found at $CsvPath" -ForegroundColor Red
    exit 1
}

$hosts = Import-Csv -Path $CsvPath -Header "Host"
Write-Host "Found $($hosts.Count) hosts." -ForegroundColor Magenta

foreach ($item in $hosts) {
    $hostName = $item.Host.Trim()
    
    if ([string]::IsNullOrWhiteSpace($hostName)) { continue }

    if ($DryRun) {
        Write-Host "[DRY RUN] Would ping $hostName and report to API." -ForegroundColor Yellow
        continue
    }

    Write-Host "Pinging $hostName... " -NoNewline -ForegroundColor Cyan

    $isUp = $false
    if ($MockRun) {
        $isUp = (Get-Random -Minimum 0 -Maximum 100) -gt 20
    } else {
        $isUp = Test-Ping -Target $hostName -Timeout $TimeoutMs
    }

    if ($isUp) {
        Write-Host "UP " -NoNewline -ForegroundColor Green
        $severity = "ok"
        $status = "Ping OK"
    }
    else {
        Write-Host "DOWN " -NoNewline -ForegroundColor Red
        $severity = "error"
        $status = "Ping Failed"
    }

    Send-ToApi -ApiUrl $ApiUrl -SystemName $SystemName -ProjectName $ProjectName `
        -Name "Ping $hostName" -Metric "Ping" -Severity $severity -Status $status -TTL $DefaultTTL | Out-Null
}

