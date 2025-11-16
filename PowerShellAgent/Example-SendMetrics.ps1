<#
.SYNOPSIS
    Example script for sending dashboard metrics using the DashboardMetrics module

.DESCRIPTION
    This script demonstrates how to use the Send-DashboardMetric function to collect
    and send system metrics to the Dashboard API.
    
    This script can be scheduled to run every 2-5 minutes using Windows Task Scheduler.

.NOTES
    Author: IT Operations Team
    Version: 1.0
    Requires: PowerShell 5.1 or higher
#>

# Import the DashboardMetrics module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\DashboardMetrics.psm1" -Force

# Configuration
$ApiUrl = "http://dashboard-server:5000"  # Change to your API server address
$ComponentId = "COMP001"  # Change to your component ID from the database

# Example 1: Send all metrics (default)
Write-Host "Example 1: Sending all metrics..." -ForegroundColor Cyan
$result = Send-DashboardMetric -ApiUrl $ApiUrl -ComponentId $ComponentId -Verbose

# Example 2: Send only CPU and Memory metrics
<#
Write-Host "`nExample 2: Sending only CPU and Memory metrics..." -ForegroundColor Cyan
$result = Send-DashboardMetric -ApiUrl $ApiUrl -ComponentId $ComponentId -MetricTypes @("CPU", "Memory") -Verbose
#>

# Example 3: Collect metrics from a remote computer
<#
Write-Host "`nExample 3: Collecting from remote computer..." -ForegroundColor Cyan
$result = Send-DashboardMetric -ApiUrl $ApiUrl -ComponentId "COMP002" -ComputerName "SERVER02" -Verbose
#>

# Example 4: Use basic parsing (for Server Core)
<#
Write-Host "`nExample 4: Using basic parsing..." -ForegroundColor Cyan
$result = Send-DashboardMetric -ApiUrl $ApiUrl -ComponentId $ComponentId -UseBasicParsing -Verbose
#>

# Display result
if ($result) {
    Write-Host "`nResult:" -ForegroundColor Yellow
    $result | ConvertTo-Json -Depth 3 | Write-Host
}
