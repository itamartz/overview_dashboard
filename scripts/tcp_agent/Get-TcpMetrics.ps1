<#
.SYNOPSIS
    Monitors TCP ports defined in a CSV file and reports status to the Overview Dashboard.

.DESCRIPTION
    Reads a CSV file (no headers: Host,Port), groups checks by Host, performs TCP connectivity tests,
    calculates severity, and posts the results to the Overview Dashboard API.

.PARAMETER CsvPath
    Path to the components.csv file. Default: $PSScriptRoot\components.csv

.PARAMETER ApiUrl
    The API endpoint URL. Default: http://localhost:5203/api/components

.PARAMETER ProjectName
    The project name for the dashboard. Default: "TCP Checks"

.PARAMETER SystemName
    The system name for the dashboard. Default: "Network Monitoring"

.PARAMETER TimeoutMs
    Timeout for TCP connection in milliseconds. Default: 1000

.EXAMPLE
    .\Get-TcpMetrics.ps1
#>

param(
    [string]$CsvPath = "$PSScriptRoot\components.csv",
    [string]$ApiUrl = "https://overview.526443026.xyz/api/components",
    [string]$ProjectName = "TCP Checks",
    [string]$SystemName = "Network Monitoring",
    [int]$TimeoutMs = 1000
)

# Function to test TCP connection quickly
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
        $tcpClient.Close()
        $tcpClient.Dispose()
    }
}

# Check if CSV exists
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found at $CsvPath"
    exit 1
}

# Read CSV (Assuming No Headers: Host, Port)
$data = Import-Csv -Path $CsvPath -Header "Host", "Port"
# Group by Host
$groupedData = $data | Group-Object Host

Write-Host "Found $($groupedData.Count) hosts in CSV."

foreach ($group in $groupedData) {
    $hostName = $group.Name
    $messages = @()
    $failedCount = 0
    $totalCount = 0

    Write-Host "Checking $hostName..."

    foreach ($item in $group.Group) {
        $port = [int]$item.Port
        $totalCount++
        
        $isUp = Test-TcpConnection -Target $hostName -Port $port -Timeout $TimeoutMs
        
        if ($isUp) {
            $messages += "Port $port Up"
            Write-Host "  Port ${port}: UP"
        }
        else {
            $messages += "Port $port Down"
            $failedCount++
            Write-Host "  Port ${port}: DOWN"
        }
    }

    # Calculate Severity
    $severity = "ok"
    if ($failedCount -gt 0) {
        $severity = "error"
    }

    # Combine messages
    $statusMessage = $messages -join ", "

    # Build Component Payload
    $componentPayload = @{
        Name     = $hostName
        Severity = $severity
        Status   = $statusMessage
        TTL      = 60 # Assume quick updates, set TTL to 60s
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
        Write-Host "  -> Reported to Dashboard (Severity: $severity)"
    }
    catch {
        Write-Error "Failed to report $hostName to API: $_"
    }
}
