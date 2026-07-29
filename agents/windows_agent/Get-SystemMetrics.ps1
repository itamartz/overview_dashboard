<#
.SYNOPSIS
    Gathers system metrics and posts them to the API.

.DESCRIPTION
    Collects CPU, memory, disk usage, and service status.
    Computes severity based on thresholds. Outputs JSON formatted for API consumption.
    Can operate in DryRun (no API calls) and MockRun (fake data, sends to API) modes.

.PARAMETER ConfigPath
    Path to config.json (default: .\config.json)

.PARAMETER DryRun
    Collects metrics but does not send them to the API.

.PARAMETER MockRun
    Generates fake metrics and sends them to the API.
#>
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

# 1. PRINT BANNER
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "         Overview Dashboard Agent            " -ForegroundColor Cyan
Write-Host "         Windows System Metrics              " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

if ($DryRun) { Write-Host "[MODE] DryRun - No data will be sent to API" -ForegroundColor Yellow }
if ($MockRun) { Write-Host "[MODE] MockRun - Using fake data" -ForegroundColor Yellow }

# 2. LOAD CONFIGURATION
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

try {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse config.json: $_"
    exit 1
}

$apiUrl = $config.apiUrl
$projectName = $config.projectName
$systemName = $config.systemName
$defaultTTL = if ($config.defaultTTL) { $config.defaultTTL } else { 120 }
$warnThresh = if ($config.thresholds.warning) { $config.thresholds.warning } else { 85 }
$errThresh = if ($config.thresholds.error) { $config.thresholds.error } else { 95 }
$services = if ($config.services) { $config.services } else { @() }

# 5. COLLECT DATA
function Get-CPUUsage {
    if ($MockRun) { return Get-Random -Minimum 10 -Maximum 99 }
    $cpuUsage = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 2 | 
        Select-Object -ExpandProperty CounterSamples | Select-Object -Last 1 -ExpandProperty CookedValue
    return [math]::Round($cpuUsage, 2)
}

function Get-MemoryUsage {
    if ($MockRun) { return Get-Random -Minimum 10 -Maximum 99 }
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemory = $os.TotalVisibleMemorySize
    $freeMemory = $os.FreePhysicalMemory
    $usedMemory = $totalMemory - $freeMemory
    return [math]::Round(($usedMemory / $totalMemory) * 100, 2)
}

function Get-DiskUsage {
    if ($MockRun) {
        return @(
            @{ DeviceID = "C:"; UsedPercent = (Get-Random -Minimum 10 -Maximum 99) },
            @{ DeviceID = "D:"; UsedPercent = (Get-Random -Minimum 10 -Maximum 99) }
        )
    }
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | 
    Select-Object DeviceID, 
    @{Name = "UsedPercent"; Expression = {
            if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 2) } else { 0 }
        }
    }
    return $disks
}

function Get-StoppedAutoServices {
    if ($MockRun) {
        $chance = Get-Random -Minimum 1 -Maximum 10
        if ($chance -gt 7) { return @("MockService1") }
        return @()
    }
    
    $stopped = Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } | Select-Object -ExpandProperty Name
    $filtered = @()
    foreach ($s in $stopped) {
        $ignore = $false
        foreach ($pattern in $services) {
            if ($s -like "*$pattern*") { $ignore = $true; break }
        }
        if (-not $ignore) { $filtered += $s }
    }
    return $filtered
}

$cpuUsage = Get-CPUUsage
$memoryUsage = Get-MemoryUsage
$disks = Get-DiskUsage
$stoppedServices = Get-StoppedAutoServices

# 7. CALCULATE SEVERITY
$severity = "ok"

if ($cpuUsage -ge $errThresh) { $severity = "error" }
elseif ($cpuUsage -ge $warnThresh -and $severity -ne "error") { $severity = "warning" }

if ($memoryUsage -ge $errThresh) { $severity = "error" }
elseif ($memoryUsage -ge $warnThresh -and $severity -ne "error") { $severity = "warning" }

foreach ($disk in $disks) {
    if ($disk.UsedPercent -ge $errThresh) { $severity = "error" }
    elseif ($disk.UsedPercent -ge $warnThresh -and $severity -ne "error") { $severity = "warning" }
}

if ($stoppedServices.Count -gt 0) { $severity = "error" }

# 8. FORMAT STATUS
$diskStrings = @()
foreach ($disk in $disks) { $diskStrings += "$($disk.DeviceID) ($($disk.UsedPercent)%)" }
$disksString = $diskStrings -join ", "
$servicesString = if ($stoppedServices.Count -gt 0) { "Down: " + ($stoppedServices -join ", ") } else { "All Automatic Services Running" }
$hostName = $env:COMPUTERNAME
$metricName = "System"

# Calculate Deterministic MD5 Component ID
$idSource = "$systemName|$projectName|$hostName|$metricName"
$md5 = [System.Security.Cryptography.MD5]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($idSource)
$hash = $md5.ComputeHash($bytes)
$componentId = [System.BitConverter]::ToString($hash) -replace '-', ''

$payloadDict = @{
    Id       = $componentId
    Name     = $hostName
    CPU      = "$cpuUsage%"
    Memory   = "$memoryUsage%"
    Disks    = $disksString
    Services = $servicesString
    Severity = $severity
    TTL      = $defaultTTL
}

$body = @{
    systemName  = $systemName
    projectName = $projectName
    payload     = ($payloadDict | ConvertTo-Json -Compress)
} | ConvertTo-Json -Compress -Depth 10

# 10. LOG RESULTS
Write-Host "`nSystem Metrics Summary:" -ForegroundColor Green

$cpuColor = if ($cpuUsage -ge $errThresh) { "Red" } elseif ($cpuUsage -ge $warnThresh) { "Yellow" } else { "Green" }
Write-Host "CPU Usage: $cpuUsage%" -ForegroundColor $cpuColor

$memColor = if ($memoryUsage -ge $errThresh) { "Red" } elseif ($memoryUsage -ge $warnThresh) { "Yellow" } else { "Green" }
Write-Host "Memory Usage: $memoryUsage%" -ForegroundColor $memColor

foreach ($disk in $disks) {
    $diskColor = if ($disk.UsedPercent -ge $errThresh) { "Red" } elseif ($disk.UsedPercent -ge $warnThresh) { "Yellow" } else { "Green" }
    Write-Host "Disk $($disk.DeviceID) Usage: $($disk.UsedPercent)%" -ForegroundColor $diskColor
}

if ($stoppedServices.Count -gt 0) {
    Write-Host "Stopped Auto Services: $($stoppedServices.Count)" -ForegroundColor Red
    $stoppedServices | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "All automatic services are running (or ignored)" -ForegroundColor Green
}

$sevColor = if ($severity -eq "error") { "Red" } elseif ($severity -eq "warning") { "Yellow" } else { "Green" }
Write-Host "`nOverall Severity: $severity" -ForegroundColor $sevColor

Write-Host "`nPayload ID: $componentId" -ForegroundColor Cyan

# 9. SEND TO API
if ($DryRun) {
    Write-Host "`n[DRY RUN] Skipping API POST." -ForegroundColor Yellow
    Write-Host "Payload JSON:`n$body" -ForegroundColor Gray
} else {
    Write-Host "`nPosting to API: $apiUrl" -ForegroundColor Cyan
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
        Write-Host "[SUCCESS] Metrics posted successfully." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to post to API: $_" -ForegroundColor Red
    }
}
