<#
.SYNOPSIS
    Monitors ICMP Ping status for hosts defined in a CSV file and reports to the Overview Dashboard.

.DESCRIPTION
    Reads a list of hosts from a plain CSV/Text file (no headers expected, first column is Host),
    performs a quick ICMP ping, calculates severity, and posts results to the API.

.PARAMETER CsvPath
    Path to the components.csv file. Default: $PSScriptRoot\components.csv

.PARAMETER ApiUrl
    The API endpoint URL. Default: https://overview.526443026.xyz/api/components

.PARAMETER ProjectName
    The project name for the dashboard. Default: "Ping Checks"

.PARAMETER SystemName
    The system name for the dashboard. Default: "Network Monitoring"

.PARAMETER TimeoutMs
    Timeout for Ping in milliseconds. Default: 1000

.EXAMPLE
    .\Get-PingMetrics.ps1
#>

param(
    [string]$CsvPath = "$PSScriptRoot\components.csv",
    [string]$ApiUrl = "https://overview.526443026.xyz/api/components",
    [string]$ProjectName = "Ping Checks",
    [string]$SystemName = "Network Monitoring",
    [int]$TimeoutMs = 1000
)

# Function to test Ping quickly
function Test-Ping {
    param(
        [string]$Target,
        [int]$Timeout
    )

    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        # Buffer size 32 bytes is standard for Windows ping, but we can use less for speed if needed.
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
        $ping.Dispose()
    }
}

# Check if file exists
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV/Host file not found at $CsvPath"
    exit 1
}

# Read Hosts. Assuming simple list. We check if it has headers or not.
# Based on user input, it's just a list of domains.
# We will use Import-Csv with Header "Host" to handle it consistently.
$hosts = Import-Csv -Path $CsvPath -Header "Host"

Write-Host "Found $($hosts.Count) hosts."

foreach ($item in $hosts) {
    $hostName = $item.Host.Trim()
    
    # Skip empty lines
    if ([string]::IsNullOrWhiteSpace($hostName)) { continue }

    Write-Host "Pinging $hostName..." -NoNewline

    $isUp = Test-Ping -Target $hostName -Timeout $TimeoutMs

    if ($isUp) {
        Write-Host " UP"
        $severity = "ok"
        $status = "Ping OK"
    }
    else {
        Write-Host " DOWN"
        $severity = "error"
        $status = "Ping Failed"
    }

    # Build Component Payload
    $componentPayload = @{
        Name     = "Ping $hostName"
        Severity = $severity
        Status   = $status
        TTL      = 60 
    } | ConvertTo-Json -Compress

    # Build API Body
    $body = @{
        systemName  = $SystemName
        projectName = $ProjectName
        payload     = $componentPayload
    } | ConvertTo-Json -Compress

    # Send to API
    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host " -> Reported"
    }
    catch {
        Write-Error "`nFailed to report $($hostName): $_"
    }
}
