<#
.SYNOPSIS
    Monitors TCP ports defined in a CSV file and reports status to the Overview Dashboard.

.DESCRIPTION
    Reads a CSV file (no headers: Host,Port), groups checks by Host, performs TCP connectivity tests,
    calculates severity, and posts the results to the Overview Dashboard API.

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
    Timeout for TCP connection in milliseconds. Default: 1000

.PARAMETER DryRun
    Shows what would be checked without sending API calls or doing connection checks.

.PARAMETER MockRun
    Generates random ok/error TCP results and sends to API.
#>

param(
    [string]$CsvPath = "$PSScriptRoot\components.csv",
    [string]$ApiUrl = "https://overview.526443026.xyz/api/components",
    [string]$ProjectName = "TCP Checks",
    [string]$SystemName = "Network Monitoring",
    [int]$DefaultTTL = 60,
    [int]$TimeoutMs = 1000,
    [switch]$DryRun,
    [switch]$MockRun
)

# Startup Banner
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " TCP Agent - Overview Dashboard          " -ForegroundColor Cyan
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

    # Generate deterministic ID from key fields
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
        Write-Warning "Failed to send to API: $_"
        return $false
    }
}

function Test-TcpConnection {
    param(
        [string]$Target,
        [int]$Port,
        [int]$Timeout
    )

    $tcpClient = New-Object System.Net.Sockets.TcpClient
    try {
        $connectTask = $tcpClient.ConnectAsync($Target, $Port)
        $wait = $connectTask.Wait($Timeout)
        
        if ($wait -and $tcpClient.Connected) {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        if ($tcpClient) {
            $tcpClient.Close()
            $tcpClient.Dispose()
        }
    }
}

if (-not (Test-Path $CsvPath)) {
    Write-Host "CSV file not found at $CsvPath" -ForegroundColor Red
    exit 1
}

# Read CSV, assume headers might be Host,Port or Host,Port,Name
# To handle no headers nicely and avoid missing columns, we read as lines and parse
$csvLines = Get-Content $CsvPath
$hosts = @()
foreach ($line in $csvLines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    # Skip if it looks like a header line
    if ($line -match "^Host,Port") { continue }
    
    $parts = $line -split ","
    if ($parts.Length -ge 2) {
        $nameField = if ($parts.Length -ge 3) { $parts[2].Trim() } else { $parts[0].Trim() }
        $hosts += [PSCustomObject]@{
            Host = $parts[0].Trim()
            Port = $parts[1].Trim()
            Name = $nameField
        }
    }
}

$groupedData = $hosts | Group-Object Host

Write-Host "Found $($groupedData.Count) hosts in CSV." -ForegroundColor Magenta

foreach ($group in $groupedData) {
    $hostName = $group.Name
    $displayName = $group.Group[0].Name
    $messages = @()
    $failedCount = 0

    if ($DryRun) {
        Write-Host "[DRY RUN] Would check TCP ports for $hostName and report." -ForegroundColor Yellow
        continue
    }

    Write-Host "Checking $hostName... " -ForegroundColor Cyan

    foreach ($item in $group.Group) {
        $port = [int]$item.Port
        
        $isUp = $false
        if ($MockRun) {
            $isUp = (Get-Random -Minimum 0 -Maximum 100) -gt 20
        } else {
            $isUp = Test-TcpConnection -Target $hostName -Port $port -Timeout $TimeoutMs
        }
        
        if ($isUp) {
            $messages += "Port $port Up"
            Write-Host "  Port ${port}: UP" -ForegroundColor Green
        }
        else {
            $messages += "Port $port Down"
            $failedCount++
            Write-Host "  Port ${port}: DOWN" -ForegroundColor Red
        }
    }

    $severity = "ok"
    if ($failedCount -gt 0) {
        $severity = "error"
    }
    $statusMessage = $messages -join ", "

    $success = Send-ToApi -ApiUrl $ApiUrl -SystemName $SystemName -ProjectName $ProjectName `
        -Name $displayName -Metric "TCP Port" -Severity $severity -Status $statusMessage -TTL $DefaultTTL

    if ($success) {
        Write-Host "  -> Reported (Severity: $severity)" -ForegroundColor Green
    } else {
        Write-Host "  -> Failed to report" -ForegroundColor Red
    }
}
